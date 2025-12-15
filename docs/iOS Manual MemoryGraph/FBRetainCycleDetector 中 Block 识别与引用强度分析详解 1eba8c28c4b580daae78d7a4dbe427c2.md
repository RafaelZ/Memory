# FBRetainCycleDetector 中 Block 识别与引用强度分析详解

## **1. 引言**

### **1.1 Block 导致的循环引用挑战**

在 Objective-C 和 Swift 开发中，自动引用计数（Automatic Reference Counting, ARC）是主要的内存管理机制。ARC 通过跟踪对象的引用数量来自动管理内存，当一个对象的引用计数降为零时，系统会回收其占用的内存。然而，ARC 并非万能，它无法自动解决“循环引用”（Retain Cycle）问题 **2**。循环引用发生在两个或多个对象相互持有对方的强引用，导致它们的引用计数永远无法降为零，即使这些对象已经不再被外部使用，它们占用的内存也无法被系统回收，从而造成内存泄漏 **2**。

Objective-C Blocks（通常简称为 Block）是导致循环引用的常见元凶之一。Block 是一种强大的语言特性，允许开发者创建内联的匿名函数，并能“捕获”（Capture）其定义时所在作用域（enclosing scope）中的变量。当 Block 捕获了 `self`（或其他持有该 Block 的对象）并且 Block 本身又被 `self`（或其拥有的其他对象）强引用时，就极易形成循环引用。例如，一个常见的场景是某个对象持有一个 Block 属性，而该 Block 内部又直接或间接强引用了该对象实例 (`self`)。

为了手动打破这种循环引用，开发者通常采用 `weakSelf/strongSelf` 模式：在 Block 外部创建一个 `self` 的弱引用 (`weakSelf`)，在 Block 内部再创建一个指向 `weakSelf` 的强引用 (`strongSelf`)，以确保在 Block 执行期间对象不会被意外释放，同时避免 Block 对 `self` 的强引用。尽管这种模式有效，但它依赖于开发者的自觉性和正确使用，对于复杂场景或疏忽情况，仍然可能遗漏，因此需要自动化的检测工具。

### **1.2 FBRetainCycleDetector：运行时分析工具**

FBRetainCycleDetector 是 Facebook 开源的一个用于在运行时检测循环引用的 iOS 库，其设计受到了 Mike Ash 的 "Circle" 项目的启发。它的核心思想是在运行时构建应用程序的对象图（Object Graph），并将对象视为图中的节点，对象间的引用关系视为图中的边，然后通过图遍历算法（如深度优先搜索 DFS）来查找图中存在的环，这些环就对应着潜在的循环引用。

本报告旨在深入剖析 FBRetainCycleDetector 的内部机制，特别是它如何在该对象图中识别出 Objective-C Block，并进一步判断 Block 所捕获的变量是通过强引用（Strong Reference）还是弱引用（Weak Reference）持有的。理解这一机制对于评估该工具的有效性和局限性，以及深入理解 Block 的内存管理行为至关重要。

*关于源码访问的说明：* 本次分析的目标是达到源码级别的理解。然而，由于提供的研究材料限制，对部分关键实现文件（如 `FBObjectiveCBlock.m`, `FBObjectiveCObject.mm`, `FBClassStrongLayout.mm`）的直接访问受限。因此，本报告的分析将主要依据公开的头文件 **15**、Objective-C Block ABI（应用程序二进制接口）文档 **16**、相关的技术讨论 **17** 以及描述该机制的二手资料 **3** 进行推导和阐述。

## **2. Objective-C Block 内部机制：检测的基础**

为了理解 FBRetainCycleDetector 如何分析 Block，首先需要了解 Block 在底层的结构和行为，这主要由其 ABI 定义。

### **2.1 Block 结构与内存布局 (ABI)**

根据 Block ABI 文档和相关资料，一个 Block 实例在内存中本质上是一个 C 结构体（通常称为 `Block_literal_1` 或类似结构）。其核心字段包括：

- `isa` 指针：指向该 Block 所属的类。这是区分 Block 类型的关键。
- `flags`：包含关于 Block 的元信息，例如是否需要 `copy`/`dispose` 辅助函数。
- `invoke` 函数指针：指向 Block 的实际执行代码。
- `descriptor` 指针：指向一个 `Block_descriptor_1` 结构，该结构包含 Block 的大小以及可选的 `copy` 和 `dispose` 辅助函数指针 。
    
    **3**
    

Block 根据其存储位置和 `isa` 指针的不同，主要分为三类：

- `_NSConcreteGlobalBlock`：全局 Block。定义在全局作用域或文件作用域，且没有捕获任何外部变量（或只捕获了静态变量）的 Block。它们存储在程序的 `.data` 段，生命周期与程序相同，复制操作是空操作。
- `_NSConcreteStackBlock`：栈 Block。定义在函数或方法内部，并且捕获了外部变量的 Block，其初始分配在栈上。当其所在的作用域结束时，栈 Block 会被销毁。
- `_NSConcreteMallocBlock`：堆 Block。当一个栈 Block 被复制（`Block_copy` 或 Objective-C 的 `copy` 消息）时，它会被拷贝到堆上，成为堆 Block。例如，将 Block 赋值给 `strong` 或 `copy` 属性、作为函数返回值或添加到集合中时，通常会发生复制。堆 Block 的生命周期由引用计数管理 。
    
    **1**
    

FBRetainCycleDetector 必须理解这种基础布局才能识别出一个对象是否是 Block，并访问其元数据。`isa` 指针是识别的主要依据，而 `descriptor` 对于分析捕获的变量至关重要。因为要将 Block 与普通对象区分开来，检测器需要一种方法来识别它。`isa` 指针指向已知的 Block 类 (`_NSConcreteXXXBlock`) 是标准的 Objective-C 机制。访问捕获的变量及其管理需要解析由 ABI 定义的结构，这通过 Block 字面量指针及其描述符来访问。

### **2.2 变量捕获机制**

Block 最强大的特性之一是能够捕获其定义时所在作用域的变量。捕获方式主要有两种：

- **按值捕获 (默认)**：对于普通的局部变量（非 `static`、非 `__block`），Block 会在定义时复制变量的值。这意味着 Block 内部持有的是变量值的一个副本，并且这个副本在 Block 内部是 `const` 的，不能被修改。后续外部变量值的改变不会影响 Block 内部捕获的值。
- **按引用捕获 (`__block`)**：使用 `__block` 修饰符声明的变量，Block 会捕获该变量的引用，允许在 Block 内部修改原始变量的值 。编译器会将 `__block` 变量包装在一个特殊的结构体中（ABI 文档中称为 `_block_byref_foo` 结构）。这个结构体包含了 `isa` 指针、指向自身的 `forwarding` 指针（用于处理变量被拷贝到堆上的情况）、`flags`、`size` 以及实际存储变量的空间。如果 `__block` 变量是 Objective-C 对象或其他需要内存管理的类型，该结构体还会包含 `byref_keep` (copy helper) 和 `byref_dispose` (dispose helper) 函数指针 。

变量捕获机制的不同决定了 FBRetainCycleDetector 查找和解释捕获变量的方式。普通捕获的变量存储在 Block 主结构之后，而 `__block` 捕获则需要通过 Block 捕获的指针间接访问 `_block_byref_foo` 结构体。ABI 为普通捕获变量（直接在 Block 的扩展结构内）和 `__block` 变量（在由 Block 指向的单独 `byref` 结构内）定义了不同的存储布局。检测器必须根据变量在原始源代码中的声明方式遵循正确的路径。

### **2.3 Copy/Dispose 辅助函数与引用管理**

Block 的内存管理，特别是对于捕获的 Objective-C 对象，依赖于 `copy` 和 `dispose` 辅助函数。

- **存在条件**：当 Block 捕获了需要进行内存管理的对象（如 Objective-C 对象、其他 Block）时，编译器会在 `Block_descriptor_1` 中生成指向 `copy` 和 `dispose` 辅助函数的指针，并在 `Block_literal_1` 的 `flags` 字段中设置 `BLOCK_HAS_COPY_DISPOSE` 标志 (值为 `1<<25`) 。
- **`copy` 辅助函数**：当 Block 从栈复制到堆时（`Block_copy`），`copy` 辅助函数会被调用。对于捕获的 `strong` 对象，它负责执行 `retain` 操作（或等效的 `_Block_object_assign` 调用），增加对象的引用计数。
- **`dispose` 辅助函数**：当堆上的 Block 被释放时（`Block_release`），`dispose` 辅助函数会被调用。对于捕获的 `strong` 对象，它负责执行 `release` 操作（或等效的 `_Block_object_dispose` 调用），减少对象的引用计数。

对于 `__block` 变量捕获的对象，其引用管理则由 `_block_byref_foo` 结构体中的 `byref_keep` 和 `byref_destroy` 函数指针负责。`byref_keep` 在 `__block` 变量结构从栈复制到堆时调用（通常伴随 Block 的复制），`byref_destroy` 在 `__block` 变量结构被销毁时调用。它们同样会根据捕获对象的强弱引用关系执行相应的 `retain` 或 `release` 操作（通过调用 `_Block_object_assign` 和 `_Block_object_dispose` 实现）。

这些辅助函数的存在与否及其具体行为，是 FBRetainCycleDetector 判断捕获变量引用强度的核心线索。由于 ARC 在源代码层面隐式管理 `retain`/`release`，编译后的 Block 依赖这些辅助函数来实现正确的内存管理语义。分析或模拟这些辅助函数的行为是确定捕获是强引用（执行 `retain`/`release`）还是弱引用（不执行）的主要途径。

## **3. FBRetainCycleDetector 中的 Block 识别**

在构建对象图并进行遍历以查找循环引用时，FBRetainCycleDetector 需要能够准确地识别出哪些节点代表的是 Block 对象，以便应用后续的特定分析逻辑。

### **3.1 在对象图中区分 Block**

该过程很可能依赖于 Objective-C 的运行时机制。当检测器在遍历对象图（可能是从通过 `addCandidate:` 方法添加的候选对象开始 **2**）遇到一个对象指针时，它会检查该指针所指向内存区域的 `isa` 字段。

如果 `isa` 指针指向已知的具体 Block 类之一（`_NSConcreteGlobalBlock`、`_NSConcreteMallocBlock` 或 `_NSConcreteStackBlock`），检测器就将该对象识别为一个 Block。随后，这个 Block 对象可能会被封装在一个专门的 `FBObjectiveCGraphElement` 子类实例中，例如 `FBObjectiveCBlock`（在头文件和 podspec 中被提及），以便在图结构中进行统一处理，并附加 Block 特有的分析逻辑。

值得注意的是，栈 Block (`_NSConcreteStackBlock`) 本身通常不会直接导致持久的循环引用，因为它们的生命周期受限于其定义的栈帧。然而，如果一个栈 Block 被复制到堆上（成为 `_NSConcreteMallocBlock`），它就可能参与形成循环引用。因此，检测器在遍历过程中仍然可能遇到并识别栈 Block，但只有堆 Block 才是循环引用的主要关注点。

这种利用 `isa` 指针进行类型识别的方法是 Objective-C 运行时的基础机制，FBRetainCycleDetector 将其整合到图遍历过程中，以便对 Block 节点应用特殊的分析策略。

## **4. 分析捕获变量的引用强度**

识别出 Block 之后，关键的下一步是确定它所捕获的变量，特别是 Objective-C 对象，是通过强引用还是弱引用持有的。这是判断是否存在循环引用的核心环节。FBRetainCycleDetector 针对普通捕获和 `__block` 捕获采用了不同的策略。

### **4.1 访问捕获的变量**

一旦确定一个对象是 Block，检测器需要解析其内部布局以找到捕获的变量。这需要遵循 Block ABI **3**。检测器会将 Block 指针强制转换为其内部已知的、模仿 ABI 结构的 C 结构体（例如，一个名为 `_FBBlockLiteral` 的内部结构），从而能够访问存储在 Block 主结构之后区域的捕获变量数据 **3**。

对于通过 `__block` 修饰符捕获的变量，情况有所不同。Block 结构中存储的不是变量本身，而是一个指向 `_block_byref_foo` 包装结构体的指针。检测器需要首先从 Block 的捕获数据区获取这个指针，然后通过该指针访问 `_block_byref_foo` 结构体，并最终通过该结构体内的 `forwarding` 指针找到实际的变量存储位置。

### **4.2 判断非 `__block` 捕获的强度（“黑盒”技术）**

对于未使用 `__block` 修饰符捕获的 Objective-C 对象，Block 的内存布局本身并不直接存储表明引用强度的标志。引用强度体现在 `copy` 和 `dispose` 辅助函数的行为中。由于无法直接查询这种隐式信息，FBRetainCycleDetector 采用了一种巧妙的“黑盒”探测技术，该技术在相关资料中有所描述：

1. **检查辅助函数**：检测器首先检查 Block 的 `flags` 字段是否包含 `BLOCK_HAS_COPY_DISPOSE` 标志 ( `1<<25` ) 。如果没有这个标志，说明 Block 没有 `copy`/`dispose` 辅助函数，因此它捕获的对象不可能是强引用的。
2. **模拟销毁过程**：如果存在 `copy`/`dispose` 辅助函数，检测器会模拟 Block 的销毁过程。它创建一个“伪造布局”（Fake Layout），该布局在内存结构上模仿 Block 实际捕获变量的区域。
3. **放置探测器**：在伪造布局中，原本存储捕获对象指针的位置，被替换为指向特殊“释放探测器”（Release Detector）对象的指针。这些探测器对象被设计用来监测是否有 `release` 消息（或等效操作）发送给它们。
4. **调用 `dispose_helper`**：检测器获取 Block 描述符中的 `dispose_helper` 函数指针，并用伪造布局作为参数调用这个函数。
5. **观察探测器**：检测器观察哪些释放探测器接收到了 `release` 消息。如果在某个位置的探测器接收到了 `release`，则意味着原始 Block 在该位置捕获的对象是通过强引用持有的，因为 `dispose_helper` 试图释放它。如果某个探测器没有收到 `release` 消息，则表明对应位置的原始捕获是弱引用（或非对象类型）。

虽然 `FBBlockStrongLayout.m` 的具体源码不可见 **19**，但根据描述 **3**，这部分逻辑很可能实现在该文件中。

这种方法体现了一种逆向工程的思路。由于运行时缺乏直接查询捕获强度的 API，检测器通过模拟运行时自身的内存管理行为（调用 `dispose_helper`）来推断原始代码的意图。`dispose_helper` 是 ARC 为 Block 捕获变量编译出的 `release` 语义的实现。通过在一个受控结构（带有探测器的伪造布局）上调用它，检测器可以观察其行为（它试图释放哪些对象），从而在没有显式元数据的情况下推断出原始捕获是强引用还是弱引用。

### **4.3 判断 `__block` 捕获的强度**

对于使用 `__block` 修饰符捕获的 Objective-C 对象变量，其引用强度信息被编码在 `_block_byref_foo` 包装结构体中，使得分析更为直接。

1. **访问包装结构**：检测器通过 Block 捕获区域中的指针找到对应的 `_block_byref_foo` 结构体。
2. **检查 `flags` 字段**：检测器检查该结构体内的 `flags` 字段。
3. **解析标志位**：根据 Block ABI 文档  中描述的、被运行时辅助函数（如 `_Block_object_assign` 和 `_Block_object_dispose`）使用的标志位来判断强度：
    
    **16**
    
    - `BLOCK_FIELD_IS_OBJECT` (值为 3) 或 `BLOCK_FIELD_IS_BLOCK` (值为 7)：表示 `__block` 变量持有的是一个 Objective-C 对象或另一个 Block。
    - `BLOCK_FIELD_IS_WEAK` (值为 16)：表示这是一个 `__weak` 引用。
    - `BLOCK_FIELD_IS_BYREF` (值为 8)：表示变量本身是 `__block` 变量（这在访问 `_block_byref_foo` 结构时已知）。
    - **推断逻辑**：
        - 如果 `flags` 中包含 `BLOCK_FIELD_IS_OBJECT` 或 `BLOCK_FIELD_IS_BLOCK`，并且 **不包含** `BLOCK_FIELD_IS_WEAK`，则判定为 **强引用**。
        - 如果 `flags` 中包含 `BLOCK_FIELD_IS_WEAK`（通常也会同时包含 `BLOCK_FIELD_IS_OBJECT` 或 `BLOCK_FIELD_IS_BLOCK`），则判定为 **弱引用**。

以下表格总结了用于判断 `__block` 变量捕获强度的关键标志位及其含义：

| **标志位 (Flags Field Bit)** | **值 (Decimal)** | **含义** | **结合判断引用强度** |
| --- | --- | --- | --- |
| `BLOCK_FIELD_IS_OBJECT` | 3 | 变量是一个 Objective-C 对象。 | 若存在此标志且不存在 `BLOCK_FIELD_IS_WEAK`，则为强引用。 |
| `BLOCK_FIELD_IS_BLOCK` | 7 | 变量是另一个 Block。 | 若存在此标志且不存在 `BLOCK_FIELD_IS_WEAK`，则为强引用。 |
| `BLOCK_FIELD_IS_WEAK` | 16 | 变量是一个 `__weak` 引用。 | 若存在此标志（通常伴随 `BLOCK_FIELD_IS_OBJECT` 或 `BLOCK_FIELD_IS_BLOCK`），则为弱引用。 |
| `BLOCK_FIELD_IS_BYREF` | 8 | 变量是一个 `__block` 变量（即此结构体描述的是 `__block` 变量）。 | 用于标识结构类型，不直接决定对象引用的强弱。 |
| `BLOCK_HAS_COPY_DISPOSE` | (1 << 25) | 适用于 `Block_literal` 结构，表示 Block 捕获了需管理的对象或 Block。 | 存在于 Block 字面量而非 `byref` 结构中，用于判断非 `__block` 捕获是否可能为强引用。 |
| `BLOCK_IS_GLOBAL` | (1 << 28) | 适用于 `Block_literal` 结构，表示是全局 Block。 | 全局 Block 不持有强引用。 |
| `BLOCK_USE_STRET` | (1 << 29) | 适用于 `Block_literal` 结构，表示 Block 返回结构体。 | 与引用强度无关。 |
| `BLOCK_HAS_SIGNATURE` | (1 << 30) | 适用于 `Block_literal` 结构，表示 Block 有签名信息。 | 与引用强度无关。 |
| `BLOCK_BYREF_HAS_LAYOUT` | (1 << 1) | 适用于 `byref` 结构，表示存在扩展布局信息（较少见）。 | 若存在，可能需要进一步解析布局来确定引用关系，但基础强弱判断仍依赖 `BLOCK_FIELD_IS_WEAK` 等标志。 |
| `BLOCK_BYREF_NEEDS_FREE` | (1 << 24) | 适用于 `byref` 结构，表示 `byref` 结构本身是在堆上分配的。 | 与内部捕获对象的引用强度无关。 |
| `BLOCK_BYREF_IS_GLOBAL` | (1 << 28) | 适用于 `byref` 结构，表示 `__block` 变量是全局或静态的。 | 与内部捕获对象的引用强度无关。 |
| `BLOCK_BYREF_HAS_COPY_DISPOSE` | (1 << 25) | 适用于 `byref` 结构，表示 `__block` 变量需要 `byref_keep`/`dispose`。 | 表明 `__block` 变量持有需管理的对象或 Block，其强弱由 `BLOCK_FIELD_IS_WEAK` 等标志决定。 |

***16***

与普通捕获不同，`__block` 变量的引用强度信息被显式编码在其包装结构体的元数据 (`flags`) 中，这使得检测器能够更直接地进行分析。`__block` 机制需要一个辅助结构来管理变量的生命周期和跨作用域共享。运行时系统依赖这个结构中的显式标志来通过 `byref_keep`/`byref_destroy` 辅助函数正确地调用 `retain`/`release`（或弱引用等效操作）。FBRetainCycleDetector 正是利用了这些相同的标志位。

### **4.4 在对象图中表示引用**

一旦检测器确定了一个捕获变量是 Objective-C 对象，并判断出其引用强度（强或弱），它就会在内部维护的对象图中添加一条相应的边。这条边从代表 Block 的节点（例如 `FBObjectiveCBlock` 实例）指向代表被捕获对象的节点。边的属性会标记为强引用或弱引用。这样，后续的循环检测算法（如 DFS）就能够利用这些边的信息来准确地发现由强引用构成的循环路径 **3**。

## **5. 结论**

### **5.1 机制总结**

FBRetainCycleDetector 通过深入理解 Objective-C 运行时和 Block ABI，实现了一套有效的 Block 循环引用检测机制。其核心步骤可以总结为：

1. **Block 识别**：在构建和遍历对象图时，通过检查对象的 `isa` 指针，识别出指向 `_NSConcreteGlobalBlock`、`_NSConcreteMallocBlock` 或 `_NSConcreteStackBlock` 的对象，将其标记为 Block 节点。
2. **捕获变量分析**：根据 Block 的 ABI 结构解析其内存布局，找到捕获的变量。
3. **引用强度判断**：
    - 对于**非 `__block` 捕获**的对象：检查 Block 是否有 `copy`/`dispose` 辅助函数。若有，则采用“黑盒”技术，通过模拟调用 Block 的 `dispose_helper` 并观察哪些“释放探测器”被触发，来推断哪些捕获是强引用 。
        
        **3**
        
    - 对于**`__block` 捕获**的对象：直接解析 `__block` 变量包装结构 (`_block_byref_foo`) 中的 `flags` 字段，通过检查 `BLOCK_FIELD_IS_OBJECT`、`BLOCK_FIELD_IS_BLOCK` 和 `BLOCK_FIELD_IS_WEAK` 等标志位的组合来确定引用是强还是弱 。
        
        **16**
        
4. **图构建**：将识别出的引用关系（标记强弱）作为边添加到对象图中，供后续的循环检测算法使用。

### **5.2 重要性**

这种基于运行时分析和对底层机制深刻理解的方法，使得 FBRetainCycleDetector 能够有效地检测出涉及 Block 的复杂循环引用，而这类循环引用是 Objective-C 和 Swift 应用中常见的内存泄漏来源。特别是其处理非 `__block` 捕获时采用的“黑盒”模拟技术，展示了在缺乏直接元数据时，通过模拟运行时行为来推断内存管理语义的巧妙思路。理解这些内部机制有助于开发者更好地利用该工具，并加深对 Block 内存管理复杂性的认识。# FBRetainCycleDetector 中 Block 识别与引用强度分析详解

示例代码：

```objectivec
@interface CCCObject : NSObject

@end

@implementation CCCObject

@end

typedef void(^TestBlock)(void);

int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    @autoreleasepool {
        // Setup code that might create autoreleased objects goes here.
        appDelegateClassName = NSStringFromClass([AppDelegate class]);
        
        CCCObject *obj = [CCCObject new];
        __weak CCCObject *obj1 = obj;
        __block CCCObject *obj3 = [CCCObject new];
        CCCObject *obj4 = [CCCObject new];
        
        __block int a = 10;
        TestBlock block = ^{
            NSLog(@"%p %p %p %p",obj1,obj1,obj3,obj4);
            printf("");
            a++;
            NSLog(@"%d",a);
        };
        block();
        NSLog(@"%p",obj);
        NSLog(@"%d",a);
    }
    return UIApplicationMain(argc, argv, nil, appDelegateClassName);
}

```

使用命令编译成C++后：

```cpp
typedef void(*TestBlock)(void);
struct __Block_byref_obj3_0 {
  void *__isa;
__Block_byref_obj3_0 *__forwarding;
 int __flags;
 int __size;
 void (*__Block_byref_id_object_copy)(void*, void*);
 void (*__Block_byref_id_object_dispose)(void*);
 CCCObject *__strong obj3;
};
struct __Block_byref_a_1 {
  void *__isa;
__Block_byref_a_1 *__forwarding;
 int __flags;
 int __size;
 int a;
};

struct __main_block_impl_0 {
  struct __block_impl impl;
  struct __main_block_desc_0* Desc;
  CCCObject *__weak obj1;
  CCCObject *__strong obj4;
  __Block_byref_obj3_0 *obj3; // by ref
  __Block_byref_a_1 *a; // by ref
  __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, CCCObject *__weak _obj1, CCCObject *__strong _obj4, __Block_byref_obj3_0 *_obj3, __Block_byref_a_1 *_a, int flags=0) : obj1(_obj1), obj4(_obj4), obj3(_obj3->__forwarding), a(_a->__forwarding) {
    impl.isa = &_NSConcreteStackBlock;
    impl.Flags = flags;
    impl.FuncPtr = fp;
    Desc = desc;
  }
};
static void __main_block_func_0(struct __main_block_impl_0 *__cself) {
  __Block_byref_obj3_0 *obj3 = __cself->obj3; // bound by ref
  __Block_byref_a_1 *a = __cself->a; // bound by ref
  CCCObject *__weak obj1 = __cself->obj1; // bound by copy
  CCCObject *__strong obj4 = __cself->obj4; // bound by copy

            NSLog((NSString *)&__NSConstantStringImpl__var_folders_nx_7c321x994rzffdr1qf5cyghr0000gn_T_testMain_f405d1_mi_0,obj1,obj1,(obj3->__forwarding->obj3),obj4);
            printf("");
            (a->__forwarding->a)++;
            NSLog((NSString *)&__NSConstantStringImpl__var_folders_nx_7c321x994rzffdr1qf5cyghr0000gn_T_testMain_f405d1_mi_1,(a->__forwarding->a));
        }
static void __main_block_copy_0(struct __main_block_impl_0*dst, struct __main_block_impl_0*src) {_Block_object_assign((void*)&dst->obj1, (void*)src->obj1, 3/*BLOCK_FIELD_IS_OBJECT*/);_Block_object_assign((void*)&dst->obj3, (void*)src->obj3, 8/*BLOCK_FIELD_IS_BYREF*/);_Block_object_assign((void*)&dst->obj4, (void*)src->obj4, 3/*BLOCK_FIELD_IS_OBJECT*/);_Block_object_assign((void*)&dst->a, (void*)src->a, 8/*BLOCK_FIELD_IS_BYREF*/);}

static void __main_block_dispose_0(struct __main_block_impl_0*src) {_Block_object_dispose((void*)src->obj1, 3/*BLOCK_FIELD_IS_OBJECT*/);_Block_object_dispose((void*)src->obj3, 8/*BLOCK_FIELD_IS_BYREF*/);_Block_object_dispose((void*)src->obj4, 3/*BLOCK_FIELD_IS_OBJECT*/);_Block_object_dispose((void*)src->a, 8/*BLOCK_FIELD_IS_BYREF*/);}

static struct __main_block_desc_0 {
  size_t reserved;
  size_t Block_size;
  void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0*);
  void (*dispose)(struct __main_block_impl_0*);
} __main_block_desc_0_DATA = { 0, sizeof(struct __main_block_impl_0), __main_block_copy_0, __main_block_dispose_0};
int main(int argc, char * argv[]) {
    NSString * appDelegateClassName;
    /* @autoreleasepool */ { __AtAutoreleasePool __autoreleasepool; 
        appDelegateClassName = NSStringFromClass(((Class (*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("AppDelegate"), sel_registerName("class")));
        CCCObject *obj = ((CCCObject *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("CCCObject"), sel_registerName("new"));
        __attribute__((objc_ownership(weak))) CCCObject *obj1 = obj;
        __attribute__((__blocks__(byref))) __Block_byref_obj3_0 obj3 = {(void*)0,(__Block_byref_obj3_0 *)&obj3, 33554432, sizeof(__Block_byref_obj3_0), __Block_byref_id_object_copy_131, __Block_byref_id_object_dispose_131, ((CCCObject *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("CCCObject"), sel_registerName("new"))};
        CCCObject *obj4 = ((CCCObject *(*)(id, SEL))(void *)objc_msgSend)((id)objc_getClass("CCCObject"), sel_registerName("new"));
        __attribute__((__blocks__(byref))) __Block_byref_a_1 a = {(void*)0,(__Block_byref_a_1 *)&a, 0, sizeof(__Block_byref_a_1), 10};
        TestBlock block = ((void (*)())&__main_block_impl_0((void *)__main_block_func_0, &__main_block_desc_0_DATA, obj1, obj4, (__Block_byref_obj3_0 *)&obj3, (__Block_byref_a_1 *)&a, 570425344));
        ((void (*)(__block_impl *))((__block_impl *)block)->FuncPtr)((__block_impl *)block);
        NSLog((NSString *)&__NSConstantStringImpl__var_folders_nx_7c321x994rzffdr1qf5cyghr0000gn_T_testMain_f405d1_mi_2,obj);
        NSLog((NSString *)&__NSConstantStringImpl__var_folders_nx_7c321x994rzffdr1qf5cyghr0000gn_T_testMain_f405d1_mi_3,(a.__forwarding->a));
    }
    return UIApplicationMain(argc, argv, nullptr, appDelegateClassName);
}

```

知识点：

1. block 被编译成了一个__main_block_impl_0指针
2. 各个变量：
    1. (未捕获）obj是普通的OC对象
    2. (值捕获weak）obj1 增加了objc_ownership(weak)
    3. (__block捕获）obj3 由一个OC指针转为了一个__Block_byref_obj3_0结构体
    4. (值捕获）obj4是普通的OC对象
    5. (__block捕获) a 包装成了一个__Block_byref_a_1结构体
3. 我们发现通过__block修饰的变量，都被包装成了结构体，结构体的前缀是__Block_byref_，后面跟的是变量名，再后面是引用捕获的顺序编号。通过对比obj3和a的结构体，发现他们的区别：
    1. a本身是值类型
    2. obj3原意是对象指针，这里被捕获后，结构体中多了2个函数指针：__Block_byref_id_object_copy、__Block_byref_id_object_dispose，分别指向下面的两个静态函数
        
        ```cpp
        static void __Block_byref_id_object_copy_131(void *dst, void *src) {
         _Block_object_assign((char*)dst + 40, *(void * *) ((char*)src + 40), 131);
        }
        static void __Block_byref_id_object_dispose_131(void *src) {
         _Block_object_dispose(*(void * *) ((char*)src + 40), 131);
        }
        
        ```
        
4. 来看一下block的结构体__main_block_impl_0：
    
    ```cpp
    struct __main_block_impl_0 {
      struct __block_impl impl;
      struct __main_block_desc_0* Desc;
      CCCObject *__weak obj1;
      CCCObject *__strong obj4;
      __Block_byref_obj3_0 *obj3; // by ref
      __Block_byref_a_1 *a; // by ref
      __main_block_impl_0(void *fp, struct __main_block_desc_0 *desc, CCCObject *__weak _obj1, CCCObject *__strong _obj4, __Block_byref_obj3_0 *_obj3, __Block_byref_a_1 *_a, int flags=0) : obj1(_obj1), obj4(_obj4), obj3(_obj3->__forwarding), a(_a->__forwarding) {
        impl.isa = &_NSConcreteStackBlock;
        impl.Flags = flags;
        impl.FuncPtr = fp;
        Desc = desc;
      }
    };
    
    ```
    
    结构体有2+N个参数，前两个参数是固定的，后面的N是捕获的变量个数。
    
    ```cpp
    struct __block_impl {
      void *isa;
      int Flags;
      int Reserved;
      void *FuncPtr;
    };
    static struct __main_block_desc_0 {
      size_t reserved;
      size_t Block_size;
      void (*copy)(struct __main_block_impl_0*, struct __main_block_impl_0*);
      void (*dispose)(struct __main_block_impl_0*);
    } __main_block_desc_0_DATA = { 0, sizeof(struct __main_block_impl_0), __main_block_copy_0, __main_block_dispose_0};
    
    ```
    
    参数1 imp是由__main_block_impl_0的构造函数参数初始化的
    
    参数2 Desc传入的是静态变量__main_block_desc_0_DATA的指针
    
    后面的参数都是捕获的变量，按照值捕获-引用捕获的顺序排列
    
    注意__main_block_desc_0_DATA初始化时传入的copy和dispose方法：
    
    ```cpp
    static void __main_block_copy_0(struct __main_block_impl_0*dst, struct __main_block_impl_0*src) 
    {
    	_Block_object_assign((void*)&dst->obj1, (void*)src->obj1, 3/*BLOCK_FIELD_IS_OBJECT*/);
    	_Block_object_assign((void*)&dst->obj2, (void*)src->obj2, 8/*BLOCK_FIELD_IS_BYREF*/);
    	_Block_object_assign((void*)&dst->obj3, (void*)src->obj3, 8/*BLOCK_FIELD_IS_BYREF*/);
    	_Block_object_assign((void*)&dst->obj4, (void*)src->obj4, 3/*BLOCK_FIELD_IS_OBJECT*/);
    	_Block_object_assign((void*)&dst->a, (void*)src->a, 8/*BLOCK_FIELD_IS_BYREF*/);
    }
    
    static void __main_block_dispose_0(struct __main_block_impl_0*src) 
    {
    	_Block_object_dispose((void*)src->obj1, 3/*BLOCK_FIELD_IS_OBJECT*/);
    	_Block_object_dispose((void*)src->obj2, 8/*BLOCK_FIELD_IS_BYREF*/);
    	_Block_object_dispose((void*)src->obj3, 8/*BLOCK_FIELD_IS_BYREF*/);
    	_Block_object_dispose((void*)src->obj4, 3/*BLOCK_FIELD_IS_OBJECT*/);
    	_Block_object_dispose((void*)src->a, 8/*BLOCK_FIELD_IS_BYREF*/);
    }
    
    ```
    
    这里对每一个捕获的变量都调用了 assign/dispose 方法，区别就是最后一个参数。再来看_Block_object_assign\_Block_object_dispose的定义(源码在libclosure/block_private.h)：
    
    ```cpp
    
    enum {
        // see function implementation for a more complete description of these fields and combinations
        BLOCK_FIELD_IS_OBJECT   =  3,  // id, NSObject, __attribute__((NSObject)), block, ...
        BLOCK_FIELD_IS_BLOCK    =  7,  // a block variable
        BLOCK_FIELD_IS_BYREF    =  8,  // the on stack structure holding the __block variable
        BLOCK_FIELD_IS_WEAK     = 16,  // declared __weak, only used in byref copy helpers
        BLOCK_BYREF_CALLER      = 128, // called from __block (byref) copy/dispose support routines.
    };
    
    void _Block_object_assign(void *destArg, const void *object, const int flags) {
        const void **dest = (const void **)destArg;
        switch (flags & BLOCK_ALL_COPY_DISPOSE_FLAGS) {
          case BLOCK_FIELD_IS_OBJECT:
            /*******
            id object = ...;
            [^{ object; } copy];
            ********/
    
            _Block_retain_object(object);
            *dest = object;
            break;
    
          case BLOCK_FIELD_IS_BLOCK:
            /*******
            void (^object)(void) = ...;
            [^{ object; } copy];
            ********/
    
            *dest = _Block_copy(object);
            break;
        
          case BLOCK_FIELD_IS_BYREF | BLOCK_FIELD_IS_WEAK:
          case BLOCK_FIELD_IS_BYREF:
            /*******
             // copy the onstack __block container to the heap
             // Note this __weak is old GC-weak/MRC-unretained.
             // ARC-style __weak is handled by the copy helper directly.
             __block ... x;
             __weak __block ... x;
             [^{ x; } copy];
             ********/
    
            *dest = _Block_byref_copy(object);
            break;
            
          case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_OBJECT:
          case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_BLOCK:
            /*******
             // copy the actual field held in the __block container
             // Note this is MRC unretained __block only. 
             // ARC retained __block is handled by the copy helper directly.
             __block id object;
             __block void (^object)(void);
             [^{ object; } copy];
             ********/
    
            *dest = object;
            break;
    
          case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_OBJECT | BLOCK_FIELD_IS_WEAK:
          case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_BLOCK  | BLOCK_FIELD_IS_WEAK:
            /*******
             // copy the actual field held in the __block container
             // Note this __weak is old GC-weak/MRC-unretained.
             // ARC-style __weak is handled by the copy helper directly.
             __weak __block id object;
             __weak __block void (^object)(void);
             [^{ object; } copy];
             ********/
    
            *dest = object;
            break;
    
          default:
            break;
        }
    }
    
    // When Blocks or Block_byrefs hold objects their destroy helper routines call this entry point
    // to help dispose of the contents
    void _Block_object_dispose(const void *object, const int flags) {
        switch (flags & BLOCK_ALL_COPY_DISPOSE_FLAGS) {
          case BLOCK_FIELD_IS_BYREF | BLOCK_FIELD_IS_WEAK:
          case BLOCK_FIELD_IS_BYREF:
            // get rid of the __block data structure held in a Block
            _Block_byref_release(object);
            break;
          case BLOCK_FIELD_IS_BLOCK:
            _Block_release(object);
            break;
          case BLOCK_FIELD_IS_OBJECT:
            _Block_release_object(object);
            break;
          case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_OBJECT:
          case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_BLOCK:
          case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_OBJECT | BLOCK_FIELD_IS_WEAK:
          case BLOCK_BYREF_CALLER | BLOCK_FIELD_IS_BLOCK  | BLOCK_FIELD_IS_WEAK:
            break;
          default:
            break;
        }
    }
    
    ```
    

这里看到在copy函数里的obj1 flags为3，被认为是强引用的对象，

但实际上通过断点发现，在copy发生时，obj1被发送的是objc_copyweak方法，该方法是空方法

继续来聊FBRetainCircleDetector，它其实判断是不是强引用，跟这个变量是不是__block类型没关系，也就是说它不关心byref的flag标识，通过一次dispose就全抓出来了。因为dispose会对每一个指针调用dispose方法，并且已经指定了它的flag

这里又引申出一个问题：

当使用__block捕获到变量时，它又是strong类型的，FB根据索引拿到其指针，它指向的实际上是一个byref结构体，结构体中的value才是真正的object的值，这个要怎么关联引用关系？
# 技术实现文档 (Tech.md)

## 1. 项目概述

ZqtOOMDetector 是一个针对 iOS 应用的 OOM (Out Of Memory) 检测工具，旨在构建当前进程的内存对象图 (Object Graph)。通过捕获和分析内存中的对象及其引用关系，帮助开发者定位内存泄漏、大对象占用以及循环引用等问题。

## 2. 技术架构

项目采用了模块化的设计，主要包含以下核心组件：

*   **ZQTOOMDetector (控制器)**: 单例模式，负责协调各个组件的工作流程，包括启动分析、停止分析、清理数据等。
*   **ZQTHeapWalker (堆扫描器)**: 负责遍历堆内存，查找存活的内存块。
*   **ZQTVMRegionWalker (VM 扫描器)**: 负责遍历虚拟内存区域 (VM Regions)，收集内存布局信息。
*   **ZQTObjCIdentifierStrategy (OC 对象识别策略)**: 负责识别内存地址是否为 Objective-C 对象。
*   **ZQTCppClassIdentifier (C++ 类识别器)**: 负责识别内存地址是否为 C++ 对象 (基于 RTTI 和 vtable)。
*   **ZQTReferenceTracer (引用追踪器)**: 负责分析已识别对象的内部引用关系，构建有向图。
*   **CustomMallocZone (自定义内存分配)**: 为了避免检测器自身的内存分配干扰被检测应用的内存状态，项目实现了一套自定义的内存分配机制。

## 3. 核心实现细节

### 3.1 内存隔离 (Custom Zone)
为了防止分析过程中产生的临时对象被计入应用的内存占用，或者导致分析过程中的无限递归（例如分析器创建的对象又被分析器扫描到），项目使用了 `CustomMallocZone`。
*   **机制**: 创建一个自定义的 `malloc_zone_t`，并配合 C++ 的 `CustomAllocator`。
*   **应用**: 核心数据结构（如 `CustomVector`, `CustomMap`, `MemoryNode` 等）均使用该分配器，确保其内存分配在独立的 Zone 中，扫描堆时可以跳过该 Zone。

### 3.2 虚拟内存扫描 (VM Region Walking)
*   **API**: 使用 `vm_region_recurse_64` 递归遍历当前任务 (`mach_task_self()`) 的虚拟内存空间。
*   **信息收集**: 收集每个 Region 的地址范围、保护属性 (Protection)、用户标签 (User Tag, 如 `VM_MEMORY_MALLOC`)、页面状态 (Resident/Swapped/Dirtied) 等。
*   **递归深度**: 支持处理嵌套的 Submap，最大递归深度设为 8。

### 3.3 堆内存扫描 (Heap Walking)
*   **API**: 使用 `malloc_get_all_zones` 获取所有注册的 Malloc Zone。
*   **遍历**: 通过 `malloc_zone_t` 的 `introspection->enumerator` 接口，枚举每个 Zone 中正在使用的内存范围 (`MALLOC_PTR_IN_USE_RANGE_TYPE`)。
*   **过滤**: 在遍历过程中，显式跳过自定义的 `ZQTCustomMallocZone`，避免自引用。
*   **回调**: 对每个内存块调用 `range_callback`，进一步尝试识别该内存块的内容。

### 3.4 对象识别 (Object Identification)

#### Objective-C 对象
*   **类列表**: 启动时通过 `objc_copyClassList` 缓存所有注册的 OC 类。
*   **识别逻辑**:
    1.  **Tagged Pointer**: 检查指针位掩码 (`OBJC_TAG_MASK`)，处理 `NSNumber`, `NSString` 等 Tagged Pointer。
    2.  **ISA 指针**: 读取内存块首地址，假设其为 ISA 指针。如果该指针指向已注册的类列表中的某个类，则认为该内存块是 OC 对象。
    3.  **大小确认**: 使用 `class_getInstanceSize` 获取实例大小。

#### C++ 对象
*   **原理**: 利用 C++ 的 RTTI (Run-Time Type Information) 和 vtable (虚函数表) 机制。
*   **初始化扫描**: 扫描 Mach-O 镜像（应用主二进制及动态库），查找特定的 Section (`__TEXT,__const`, `__DATA,__const`, `__DATA_CONST,__const`)。
*   **识别逻辑**:
    1.  假设内存块首地址是 vptr (指向 vtable 的指针)。
    2.  检查该 vptr 是否指向已扫描到的 C++ 类信息中的 `vtable[0]` 地址。
    3.  如果匹配，则通过 RTTI 获取 Demangled Name。

### 3.5 引用关系追踪 (Reference Tracing)
*   **目前支持**: Objective-C 对象的强/弱引用分析。
*   **Ivar 布局**: 使用 `class_copyIvarList` 获取类的实例变量列表。
*   **强弱引用**: 使用 `class_getIvarLayout` 和 `class_getWeakIvarLayout` 解析 Ivar 的强弱引用属性。
*   **指针验证**: 读取 Ivar 偏移处的内存值，如果该值指向已识别的内存节点 (`ZQTMemoryNode`)，则建立引用边 (`ZQTReferenceEdge`)。

## 4. 数据结构

*   **ZQTMemoryNode**: 表示内存图中的一个节点，包含地址、大小、类型 (OC/C++/CF/Unknown)、类名等信息。
*   **ZQTReferenceEdge**: 表示节点间的引用关系，包含源节点、目标节点、引用名称 (Ivar名)、偏移量和引用强度。
*   **CppClassInfo**: 存储 C++ 类的元数据，包括 `type_info` 地址、vtable 地址、Mangled/Demangled Name。

## 5. 流程总结

1.  **准备**: 初始化自定义 Zone，缓存类列表，扫描 Mach-O 获取 C++ 信息。
2.  **VM 扫描**: 遍历 VM Regions，建立基础内存视图。
3.  **堆扫描**: 遍历 Malloc Zones，获取所有活跃内存块。
4.  **对象识别**: 对每个内存块尝试识别为 OC 对象或 C++ 对象，生成 `MemoryNode`。
5.  **引用分析**: 遍历已识别的 OC 对象，解析 Ivar，建立节点间的引用边。
6.  **输出**: 生成内存图数据 (Nodes + Edges)。

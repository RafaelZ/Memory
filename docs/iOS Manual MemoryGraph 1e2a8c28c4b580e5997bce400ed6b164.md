# iOS  Manual MemoryGraph

# 虚拟内存：

连续的64位虚拟内存空间

通过MMU将虚拟内存地址映射到物理内存（ASLR，地址空间布局随机化，引入随机偏移量，使得虚拟内存的起始位避免总是固定的从0x00000000开始）

虚拟内存空间，分5大部分？

- 栈区
- 堆区
- 系统resource
- 动态库映射（data_text）
- App二进制文件映射(data_text)

每一段连续的虚拟内存空间的地址，都被一个VMRegion管理，它占用的空间最小单位为page（16kb），对应的物理内存也是16kb的大小

为什么要有VMRegion？

应用占用的内存，我们一般统计的叫foot print，只包含dirty size和compressed size。clean size不在内，因为它被认为是未使用的，或者可被系统回收，使用时再重建的。

footPrint = dirtySize+compressedSize

Xcode navigator 查看性能时，那里也是foot print

我们关心foot print，主要也就是关心在堆（heap）上的内存分配

堆上又有很多库往上面添加对象。例如 malloc、alloc等等

我们只关心Object对象、CF对象和C++对象

Object又包含OC和swift对象

# 整体流程：

- 暂停线程
- 抓取所有内存数据
    - 遍历VM Region，记录Region信息
    - 获取所有OC/swift类信息，包括ivar布局，重要的是ivar强引用列表
    - 获取所有C++类（有vtable的）
    - 遍历Zone
        - 获取zone→introspect
        - introspect遍历address
        - 判断address对应的地址是OC/swift对象/CF对象/C++对象/buffer
        - 将address等信息构建成一个新的结构体，保存到一个vector里
        - 此时就获得了栈内所有内存块的信息
- 遍历数据，建立引用关系
    - 遍历每一个内存块
        - 由于内存是对齐的，遍历address- address+size范围，看地址内保存的是不是指针，该指针是否在大列表中，在的话就建立引用关系
        - 如果内存快是OC/Swift类，根据偏移量，查找IVAR，找到它们的对应关系，补充到引用关系里
- 恢复线程
- 写文件

# 问题

## 1. 如何将获取的内存与class关联

1. objc_getClassList，获取所有class列表
2. 遍历zone，拿到range.address，将其转为mock_objc结构体，
3. 指向的内存第一部分，取出来，认为其是isa
4. 如果我们保存的class列表中包含该isa
5. 则认为其是个NSObject/swift object

## 2.如何将获取的内存与CFType关联

CF对象的isa指向的统一都是__NSCFType类，将object转成CFTypeRef后，调用CFGetTypeID，获取CFTypeID，根据ID映射获得实际CF类型

## 3. 如何避免在抓取过程中创建的内存影响统计结果

1. 自定义zone
    1. OC对象使用allocWithZone
2. 自定义CFAllocator
    1. allocate
    2. deallocate
    3. reallocate
3. C++对象/struct
    1. 使用new创建
    2. 重写new/delete operator，使用自定义zone分配
    3. 重写reallocate方法

## 4. 如何获取heap里的存活的Object对象？

通过malloc_zone，遍历所有zone，通过zone的instropection便利内部所有指针，判断指针指向的地址是不是objc_object_t

这里的判断，借助 isa指针。同时要考虑到在arm64架构下，对象不一定有isa，也能是 taggedPointer，指针内部存储的就是实际的value，以及一些标记位

## 5. 如何获取C++对象

C++对象根据是否包含虚表可以分成两类。对于不包含虚表的对象，因为缺乏运行时数据，无法进行处理。对于对于包含虚表的对象，在调研 mach-o 和 C++的 ABI 文档后，可以通过 std::type_info 和以下几个 section 的信息获取对应的类型信息。

## 6. 如何建立对象间的引用关系

利用内存对齐的特性，一个对象所在的内存区域是连续的，它的ivar指针肯定是在它的起始地址+8nbyte处。如此遍历该内存，就能得到引用关系。

❓ 新的问题，如果是链表，内存就不是连续的。此时如何关联他们的引用关系？

假设 A 持有一个链表B，也就是A的布局中存在B的head指针b0，可以关联A- b0，b0本身也在heap上，可以关联b0-b1，依次类推，可以获得一系列引用对 A-b0，b0-b1,b1-b2,b2-b3,b3-b4…..bn-1-bn。最终在前台加工后，可以展示出这个链条

❓ 新的问题，associateObject如何关联引用关系

首先回顾一下关联对象的实现方式。简单理解：关联对象是保存在一个全局的hashmap中，key为对象地址：value为另一个map。map中保存的关联对象的key和value。

在Memory Graph中，也没有明确表明关联对象和被关联对象的引用关系，如果要获得这个关系，需要hook objc_setAssociate方法

这个方法会导致额外的内存占用，同样需要使用特定的zone来管理这些内存

## 7.如何使用mmap写文件

使用mmap映射一个文件，然后顺序写入内容，这样不会占用太多内存，但是需要在本地创建一个文件，使用ft。。。方法将文件扩展至非常大？具体多大？然后操作内存写文件，具体写文件，每次要写多少内容，如果我要写一个json格式的文件，如何直接写二进制？

 跟ofstream的区别是什么？

mmap: 文件映射机制，可以随机访问内存，无需内存缓冲，性能更高

ofstream: C++文件输出的流，使用内存缓冲区

## 8.如何获取JSCore占用的内存

## 9.如何避免抓取时崩溃

## 10.如何避免整个抓取过程耗时过长

提高效率，多线程处理

## 11. 整个框架对性能的额外开销如何

## 12. 什么数据会在栈上，栈上的数据会泄漏吗

值类型、指针类型会被分配在栈上。

直接分配在栈上的内存不会产生泄漏，因为栈的特性，栈帧销毁时会释放内存

但是栈上的指针指向的堆内存，有可能泄漏

## 13.成果如何量化

## 14.为什么抓取的内存图存在某个高地址0x140400000，但是在xcode memory graph中找不到该地址。在所有捕获的vm region中也不包含该地址？

答案： 肯定是抓取过程中创建的内存，又被抓取到了。抓取结束后该内存被释放了

## 15. 如何避免在抓取过程中创建的对象也被抓进去？

尝试1 ： 对所有struct都 继承 base，重写new方法 （不行）

尝试2 ：对vector重写allocator，还没尝试

MetricKit Demo 测试：

单纯遍历zone计数：

|  | 定时触发 | 手动触发 |
| --- | --- | --- |
| 不添加zqtObject | 25928 | 26607 |
| 添加2000个zqtobject | 34486 | 34620 |
| 添加2000个zqtobject（无属性） | 28501 | 28718 |

与

Introments统计数据相当

调用 objc_getClassList后，内存块计数大概增加10w+，这是由于系统会为创建类

单纯遍历zone计数+获取class列表

## 16. block导致的retain Circle能不能检测出来

理论上可行，block本质也是一个object，它捕获的变量会存在它自己的表量表中

参考FBRetainCircleDetect

❓ weak修饰的外部变量，如何在block中不增加引用计数的

## 17. 全局变量/单例是在堆上还是全局变量区

全局变量的指针本身是在mach-o的data段或bss段中，它指向的内存是在运行时创建的，并且分配在堆上。单例实际上也是通过静态变量来实现的。

## 18. MachO的布局，segment、load command、section、text、data是什么意思，怎么布局的

[Mach-O](iOS%20Manual%20MemoryGraph/Mach-O%201e9a8c28c4b580739798f3fb9e558919.md)

## 19.  FB Recycle detector /  MLeaksFinder原理

[https://zhuanlan.zhihu.com/p/524626759](https://zhuanlan.zhihu.com/p/524626759)

MleaksFinder 是hook VC的生命周期和pop方法等，通过定时检测view-viewcontroller的泄漏

结合FB，检测到view-viewController泄漏后，调用FB方法判断为什么泄漏

FB是hook objc_setAssociateObject等方法，维护了一个retain的map

{

object: [key1,key2,key3]

}

结合到我们这个功能，可以在抓取内存图的时候，遍历这个map，将这段关联信息也打印到文件中

object ptr→[(key:value ptr),(key:value ptr)]

## 20. 数据结构 图

DFS BFS

# 难点：

1. ivar属性获取
2. block属性获取
    
    [**FBRetainCycleDetector 中 Block 识别与引用强度分析详解**](iOS%20Manual%20MemoryGraph/FBRetainCycleDetector%20%E4%B8%AD%20Block%20%E8%AF%86%E5%88%AB%E4%B8%8E%E5%BC%95%E7%94%A8%E5%BC%BA%E5%BA%A6%E5%88%86%E6%9E%90%E8%AF%A6%E8%A7%A3%201eba8c28c4b580daae78d7a4dbe427c2.md)
    
3. c++类型获取
4. 引用关系的绑定
5. 强弱引用的处理
6. 关联对象的强引用处理
7. CGRasterData

未尽事宜：

数据分析脚本：

可视化后台开发

[解决的问题](iOS%20Manual%20MemoryGraph/%E8%A7%A3%E5%86%B3%E7%9A%84%E9%97%AE%E9%A2%98%201f2a8c28c4b5804abcded09213488c1f.md)

[待复盘](iOS%20Manual%20MemoryGraph/%E5%BE%85%E5%A4%8D%E7%9B%98%201f3a8c28c4b5803c90c4ccaf15a28dbe.md)

[**运行时扫描Mach-O镜像以识别C++类：问题排查与解决过程总结**](iOS%20Manual%20MemoryGraph/%E8%BF%90%E8%A1%8C%E6%97%B6%E6%89%AB%E6%8F%8FMach-O%E9%95%9C%E5%83%8F%E4%BB%A5%E8%AF%86%E5%88%ABC++%E7%B1%BB%EF%BC%9A%E9%97%AE%E9%A2%98%E6%8E%92%E6%9F%A5%E4%B8%8E%E8%A7%A3%E5%86%B3%E8%BF%87%E7%A8%8B%E6%80%BB%E7%BB%93%201f4a8c28c4b58041b4f1e5be507be398.md)

[进度](iOS%20Manual%20MemoryGraph/%E8%BF%9B%E5%BA%A6%201f4a8c28c4b580eebcf9c749e38d9193.md)
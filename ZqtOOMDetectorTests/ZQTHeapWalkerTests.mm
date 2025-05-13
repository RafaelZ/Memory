#import <XCTest/XCTest.h>
#include "ZQTHeapWalker.h"
#include <mach/mach.h>
#include <malloc/malloc.h>
#include <objc/runtime.h>
#include "ZQTObjCIdentifierStrategy.h"
@interface ZQTHeapWalkerTests : XCTestCase

@end

@implementation ZQTHeapWalkerTests

- (void)setUp {
    [super setUp];
    // 在每个测试用例开始前执行
    NSLog(@"%s",__FUNCTION__);
    // 创建自定义 zone
    ZQTCreateCustomMallocZone();
}

- (void)tearDown {
    // 在每个测试用例结束后执行
    NSLog(@"%s",__FUNCTION__);
        // 销毁自定义 zone
    ZQTDestroyCustomMallocZone();
    [super tearDown];
}

- (void)testHeapWalkerInitialization {
    @autoreleasepool {
        ZQT::HeapWalker walker;
        NSLog(@"%s",__FUNCTION__);
        XCTAssertEqual(walker.getNodes().size(), 0, @"初始化时 nodes 应该为空");
        XCTAssertEqual(walker.getNodePtrs().size(), 0, @"初始化时 nodePtrs 应该为空");
    }
}

- (void)testHeapWalkerBasicObjects {
    @autoreleasepool {
        ZQT::HeapWalker walker;
        NSLog(@"%s",__FUNCTION__);
        
        // 创建一些测试对象
        NSObject *obj1 = [[NSObject alloc] init];
        // 使用非 tagged pointer 的字符串
        NSString *str1 = [[NSString alloc] initWithFormat:@"test_%d", rand()];
        // 使用可变数组确保不是 tagged pointer
        NSMutableArray *arr1 = [NSMutableArray arrayWithObjects:@1, @2, @3, nil];
        
        // 开始扫描
        walker.scanHeap();
        const auto& nodes = walker.getNodes();
        NSLog(@"%s node size %ld",__func__,nodes.size());
        // 验证基本属性
        XCTAssertGreaterThan(nodes.size(), 0, @"应该至少找到一个内存节点");
        
        // 查找我们创建的对象
        bool foundNSObject = false;
        bool foundNSString = false;
        bool foundNSArray = false;
        
        for (const auto& pair : nodes) {
            const auto& node = pair.second;
            if (node.address == (uintptr_t)obj1) {
                foundNSObject = true;
                XCTAssertGreaterThan(node.size, 0, @"对象大小应该大于 0");
            } else if (node.address == (uintptr_t)str1) {
                foundNSString = true;
                XCTAssertGreaterThan(node.size, 0, @"对象大小应该大于 0");
            } else if (node.address == (uintptr_t)arr1) {
                foundNSArray = true;
                XCTAssertGreaterThan(node.size, 0, @"对象大小应该大于 0");
            }
        }
        
        XCTAssertTrue(foundNSObject, @"应该找到 NSObject 实例");
        XCTAssertTrue(foundNSString, @"应该找到 NSString 实例");
        XCTAssertTrue(foundNSArray, @"应该找到 NSArray 实例");
    }
}

- (void)testHeapWalkerCircularReferences {
    @autoreleasepool {
        ZQT::HeapWalker walker;
        NSLog(@"%s",__FUNCTION__);
        
        // 创建循环引用
        NSMutableArray *arr1 = [NSMutableArray array];
        NSMutableArray *arr2 = [NSMutableArray array];
        [arr1 addObject:arr2];
        [arr2 addObject:arr1];
        
        // 开始扫描
        walker.scanHeap();
        const auto& nodes = walker.getNodes();
        
        // 查找循环引用的对象
        bool foundArr1 = false;
        bool foundArr2 = false;
        
        for (const auto& pair : nodes) {
            const auto& node = pair.second;
            if (node.address == (uintptr_t)arr1) {
                foundArr1 = true;
                XCTAssertGreaterThan(node.size, 0, @"对象大小应该大于 0");
            } else if (node.address == (uintptr_t)arr2) {
                foundArr2 = true;
                XCTAssertGreaterThan(node.size, 0, @"对象大小应该大于 0");
            }
        }
        
        XCTAssertTrue(foundArr1, @"应该找到第一个数组");
        XCTAssertTrue(foundArr2, @"应该找到第二个数组");
    }
}

- (void)testHeapWalkerLargeObjects {
    @autoreleasepool {
        ZQT::HeapWalker walker;
        NSLog(@"%s",__FUNCTION__);
        
        // 创建大对象
        const size_t largeSize = 1024 * 1024; // 1MB
        void *largePtr = malloc(largeSize);
        memset(largePtr, 0xAA, largeSize);
        
        // 开始扫描
        walker.scanHeap();
        const auto& nodes = walker.getNodes();
        
        // 查找大对象
        bool foundLargeObject = false;
        for (const auto& pair : nodes) {
            const auto& node = pair.second;
            if (node.address == (uintptr_t)largePtr) {
                foundLargeObject = true;
                XCTAssertGreaterThanOrEqual(node.size, largeSize, @"对象大小应该大于等于分配的大小");
                break;
            }
        }
        
        XCTAssertTrue(foundLargeObject, @"应该找到大对象");
        
        // 清理
        free(largePtr);
    }
}

- (void)testHeapWalkerClear {
    @autoreleasepool {
        ZQT::HeapWalker walker;
        
        // 先扫描一次
        walker.scanHeap();
        XCTAssertGreaterThan(walker.getNodes().size(), 0, @"扫描后应该有节点");
        
        // 清理
        walker.clear();
        XCTAssertEqual(walker.getNodes().size(), 0, @"清理后应该没有节点");
        XCTAssertEqual(walker.getNodePtrs().size(), 0, @"清理后应该没有节点指针");
        
        // 再次扫描
        walker.scanHeap();
        XCTAssertGreaterThan(walker.getNodes().size(), 0, @"再次扫描后应该有节点");
    }
}

- (void)testHeapWalkerMoveSemantics {
    @autoreleasepool {
        ZQT::HeapWalker walker1;
        walker1.scanHeap();
        
        // 移动构造
        ZQT::HeapWalker walker2(std::move(walker1));
        XCTAssertGreaterThan(walker2.getNodes().size(), 0, @"移动构造后应该保留节点");
        
        // 移动赋值
        ZQT::HeapWalker walker3;
        walker3 = std::move(walker2);
        XCTAssertGreaterThan(walker3.getNodes().size(), 0, @"移动赋值后应该保留节点");
    }
}

- (void)testHeapWalkerMemoryTracking {
    @autoreleasepool {
        ZQT::HeapWalker walker;
        
        // 创建一些对象
        NSMutableArray *arr1 = [NSMutableArray array];
        NSMutableArray *arr2 = [arr1 mutableCopy];
        
        // 扫描并检查内存使用情况
        walker.scanHeap();
        
        // 验证内存使用情况
        size_t peakMemory = walker.getPeakMemoryUsage();
        NSLog(@"Peak memory usage: %zu bytes", peakMemory);
        XCTAssertGreaterThan(peakMemory, 0, @"应该有内存使用记录");
    }
}

- (void)testHeapWalkerCustomZone {
    @autoreleasepool {
        ZQT::HeapWalker walker;
        NSLog(@"%s",__FUNCTION__);
        
        // 在自定义 zone 中分配内存
        void *customPtr = malloc_zone_malloc(ZQTCustomMallocZone, 1024);
        XCTAssertNotEqual(customPtr, nullptr, @"自定义 zone 内存分配应该成功");
        
        // 在默认 zone 中分配内存
        void *defaultPtr = malloc(1024);
        XCTAssertNotEqual(defaultPtr, nullptr, @"默认 zone 内存分配应该成功");
        
        // 开始扫描
        walker.scanHeap();
        const auto& nodes = walker.getNodes();
        
        // 查找分配的内存
        bool foundCustomPtr = false;
        bool foundDefaultPtr = false;
        
        for (const auto& pair : nodes) {
            const auto& node = pair.second;
            if (node.address == (uintptr_t)customPtr) {
                foundCustomPtr = true;
            } else if (node.address == (uintptr_t)defaultPtr) {
                foundDefaultPtr = true;
            }
        }
        
        // 验证结果
        XCTAssertFalse(foundCustomPtr, @"不应该找到自定义 zone 中的内存");
        XCTAssertTrue(foundDefaultPtr, @"应该找到默认 zone 中的内存");
        
        // 清理
        malloc_zone_free(ZQTCustomMallocZone, customPtr);
        free(defaultPtr);
    }
}

- (void)testHeapWalkerDifferentTypes {
    @autoreleasepool {
        ZQT::ObjCIdentifierStrategy *abc = new ZQT::ObjCIdentifierStrategy();
        NSLog(@"%s",__FUNCTION__);
        
        ZQT::HeapWalker * walker = new ZQT::HeapWalker(abc);
        // 1. 创建 CFTypeRef 实例
        CFStringRef cfString = CFStringCreateWithCString(NULL, "CFString Test", kCFStringEncodingUTF8);
        XCTAssertNotEqual(cfString, nullptr, @"CFString 创建应该成功");
        
        // 2. 创建 Objective-C 对象实例
        NSObject *obj = [[NSObject alloc] init];
        XCTAssertNotNil(obj, @"NSObject 创建应该成功");
        
        // 3. 创建 Swift 对象实例 (通过 NSString 桥接)
        NSString *swiftString = [NSString stringWithFormat:@" %d", rand()];
        XCTAssertNotNil(swiftString, @"Swift String 创建应该成功");
        
        // 4. 创建 NSTaggedString 实例
        NSString *taggedString = @"TString";
        XCTAssertNotNil(taggedString, @"Tagged String 创建应该成功");
        
        // 5. 创建 malloc 内存块
        const size_t mallocSize = 1024;
        void *mallocPtr = malloc(mallocSize);
        XCTAssertNotEqual(mallocPtr, nullptr, @"malloc 内存分配应该成功");
        memset(mallocPtr, 0xAA, mallocSize);
        
        // 开始扫描
        walker->scanHeap();
        const auto& nodes = walker->getNodes();
        
        // 验证结果
        bool foundCFString = false;
        bool foundNSObject = false;
        bool foundSwiftString = false;
        bool foundTaggedString = false;
        bool foundMallocPtr = false;
        
        for (const auto& pair : nodes) {
            const auto& node = pair.second;
            if (node.address == (uintptr_t)cfString) {
                foundCFString = true;
                XCTAssertGreaterThan(node.size, 0, @"CFString 大小应该大于 0");
            } else if (node.address == (uintptr_t)obj) {
                foundNSObject = true;
                XCTAssertGreaterThan(node.size, 0, @"NSObject 大小应该大于 0");
            } else if (node.address == (uintptr_t)swiftString) {
                foundSwiftString = true;
                XCTAssertGreaterThan(node.size, 0, @"Swift String 大小应该大于 0");
            } else if (node.address == (uintptr_t)taggedString) {
                foundTaggedString = true;
                XCTAssertGreaterThan(node.size, 0, @"Tagged String 大小应该大于 0");
            } else if (node.address == (uintptr_t)mallocPtr) {
                foundMallocPtr = true;
                XCTAssertGreaterThanOrEqual(node.size, mallocSize, @"malloc 块大小应该大于等于分配的大小");
            }
        }
        
        // 验证所有对象都被找到
        XCTAssertTrue(foundCFString, @"应该找到 CFString 实例");
        XCTAssertTrue(foundNSObject, @"应该找到 NSObject 实例");
        XCTAssertTrue(foundSwiftString, @"应该找到 Swift String 实例");
        XCTAssertTrue(foundTaggedString, @"应该找到 Tagged String 实例");
        XCTAssertTrue(foundMallocPtr, @"应该找到 malloc 内存块");
        
        // 清理资源
        CFRelease(cfString);
        free(mallocPtr);
    }
}

- (void)innerMethod:(int)i lastResidengSize:(NSInteger *)lastResidentSize lastNodeCount:(NSInteger *)nodeCount
{
    struct task_basic_info t_info;
    mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT;
    @autoreleasepool {
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
        NSLog(@"第 %d 次迭代 before malloc 内存增长: curr:%zu last:%zu diff:%ld",
              i + 1, t_info.resident_size,*lastResidentSize,(NSInteger)t_info.resident_size-*lastResidentSize);

        ZQTCreateCustomMallocZone();

        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
        NSLog(@"第 %d 次迭代 after malloc 内存增长: curr:%zu last:%zu diff:%ld",
              i + 1, t_info.resident_size,*lastResidentSize,(NSInteger)t_info.resident_size-*lastResidentSize);

        // 创建新的 walker 实例
        ZQT::HeapWalker *walker = new ZQT::HeapWalker();
        
        // 使用不同的内存分配方式
        const size_t largeSize = 1024 * 1024 * (50 + i * 10); // 每次增加10MB
        void* testPtr = NULL;
        
        // 分配内存
        testPtr = malloc_zone_malloc(ZQTCustomMallocZone, largeSize);
        XCTAssertNotEqual(testPtr, nullptr, @"测试内存分配应该成功");
        
        // 记录分配后的内存状态
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
        NSLog(@"第 %d 次迭代 after malloc 内存增长: curr:%zu last:%zu diff:%ld",
              i + 1, t_info.resident_size,*lastResidentSize,(NSInteger)t_info.resident_size-*lastResidentSize);
        
        
        // 填充内存
        memset(testPtr, 0xAA, largeSize);
        
        // 记录填充后的内存状态
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
        NSLog(@"第 %d 次迭代 after memset 内存增长: curr:%zu last:%zu diff:%ld",
              i + 1, t_info.resident_size,*lastResidentSize,(NSInteger)t_info.resident_size-*lastResidentSize);

        // 扫描堆
        walker->scanHeap();
        
        // 记录内存使用情况
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
        NSLog(@"第 %d 次迭代  scan 内存增长: curr:%zu last:%zu diff:%ld",
              i + 1, t_info.resident_size,*lastResidentSize,(NSInteger)t_info.resident_size-*lastResidentSize);

        // 记录节点数量和详细信息
        size_t currentCount = walker->getNodes().size();
        
        // 清理测试内存
        if (testPtr) {
            // 在释放前检查内存状态
            
            malloc_zone_free(ZQTCustomMallocZone, testPtr);
            

            
            // 记录释放后的内存状态
            task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
            NSLog(@"第 %d 次迭代 after free 内存增长: curr:%zu last:%zu diff:%ld",
                  i + 1, t_info.resident_size,*lastResidentSize,(NSInteger)t_info.resident_size-*lastResidentSize);
        }
        
        // 清理 walker
        delete walker;
        
        // 销毁 zone
        ZQTDestroyCustomMallocZone();
        
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
        NSLog(@"第 %d 次迭代  after destroy 内存增长: curr:%zu last:%zu diff:%ld",
              i + 1, t_info.resident_size,*lastResidentSize,(NSInteger)t_info.resident_size-*lastResidentSize);

        *lastResidentSize = t_info.resident_size;
        *nodeCount = currentCount;
    }
    
    // 增加等待时间，给系统更多时间回收内存
    [NSThread sleepForTimeInterval:0.5];

    task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
    NSLog(@"第 %d 次迭代  after sleep 内存增长: curr:%zu last:%zu diff:%ld",
          i + 1, t_info.resident_size,*lastResidentSize,(NSInteger)t_info.resident_size-*lastResidentSize);
}

- (void)testHeapWalkerMemoryStability {
    @autoreleasepool {
        // 等待一小段时间，让系统有机会清理
        [NSThread sleepForTimeInterval:1];
        
        // 记录初始内存使用情况
        struct task_basic_info t_info;
        mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT;
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
        vm_size_t initialMemory = t_info.resident_size;
        NSLog(@"测试开始前内存用量： %ld", initialMemory);
                                
        // 执行多次创建、扫描、销毁操作
        const int iterations = 5;  // 减少迭代次数，方便观察
        
        NSInteger lastResidentSize = initialMemory;
        NSInteger lastNodeCount = 0;
        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                [self innerMethod:i lastResidengSize:&lastResidentSize lastNodeCount:&lastNodeCount];
            }
        }
        
        // 等待更长时间，让系统有机会清理内存
        [NSThread sleepForTimeInterval:2];
//        usleep(100000); // 100ms

        // 验证最终内存使用情况
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
        vm_size_t finalmemoryUse = t_info.resident_size;
        NSInteger finalMemoryGrowth = (NSInteger)finalmemoryUse - (NSInteger)initialMemory;
        NSLog(@"最终内存增长: %lu -%lu  %ld  bytes",
              initialMemory, t_info.resident_size, finalMemoryGrowth);
//        XCTAssertLessThanOrEqual(finalMemoryGrowth, 1024 * 1024, 
//            @"最终内存使用不应比初始状态增加超过1MB");
    }
}

kern_return_t memory_reader(task_t task, vm_address_t remote_address, vm_size_t size, void **local_memory)
{
    *local_memory = (void*) remote_address;
    return KERN_SUCCESS;
}

long _zqtNodeCounts = 0;
long _zqtCustomZoneNodeCounts = 0;
// 将 range_callback 改为静态成员函数
void range_callback(task_t task, void *context, unsigned type, vm_range_t *ranges, unsigned rangeCount)
{
    int temp = 0;
    if (context != nullptr) {
        temp = *(int *)context;
    }
    for (unsigned i = 0; i < rangeCount; i++) {
        vm_range_t range = ranges[i];
        if (range.address && range.size > 0) {
            _zqtNodeCounts++;
            if (temp != 0) {
                _zqtCustomZoneNodeCounts++;
            }
        }
    }
}

-(void)simpleCountMallocNode
{
    _zqtNodeCounts = 0;
    _zqtCustomZoneNodeCounts = 0;
    // 获取所有 malloc zones
    unsigned int count;
    vm_address_t *zones = NULL;
    kern_return_t err = malloc_get_all_zones(mach_task_self(), memory_reader, &zones, &count);
    if (err != KERN_SUCCESS) {
        return;
    }

    // 遍历所有 zones
    for (unsigned int i = 0; i < count; i++) {
        malloc_zone_t *zone = (malloc_zone_t *)zones[i];
        if (!zone) continue;
        
        const char* zoneName = malloc_get_zone_name(zone);
//        NSLog(@"Zone %d: %s", i, zoneName ? zoneName : "unnamed");
        
        int isCustomMalloc = 0;
        // 检查是否是自定义 zone
        if (zoneName && strcmp(zoneName, ZQTCustomMallocZoneName) == 0) {
            isCustomMalloc = 1; // 跳过自定义 zone
        }

//        int regionCount = 0;
        
        // 检查这个 region 是否属于当前 zone
        if (zone->introspect && zone->introspect->enumerator) {
            // 使用 zone 的 enumerator 检查
            zone->introspect->enumerator(mach_task_self(),
                                       &isCustomMalloc,
                                       MALLOC_PTR_IN_USE_RANGE_TYPE,
                                         (vm_address_t)zone,
                                       memory_reader,
                                    &range_callback);
        }
                    
//        NSLog(@"Zone %s 中的 region 数量: %d", zoneName ? zoneName : "unnamed", regionCount);
    }
}

- (void)getNodeCount
{
    [self simpleCountMallocNode];
    NSLog(@"总共count  %ld   customZone:%ld",_zqtNodeCounts,_zqtCustomZoneNodeCounts);
}

- (void)innerMethod:(int)i lastNodeCount:(NSInteger *)nodeCount
{
    [self simpleCountMallocNode];
    NSLog(@"--%d-- before malloc %ld %ld %ld",i,*nodeCount,_zqtNodeCounts,_zqtCustomZoneNodeCounts);
    @autoreleasepool {

        ZQTCreateCustomMallocZone();
        
        // 创建新的 walker 实例
        ZQT::HeapWalker *walker = new ZQT::HeapWalker();
        
        // 使用不同的内存分配方式
        const size_t largeSize = 1024 * 1024 * (50 + i * 10); // 每次增加10MB
        void* testPtr = NULL;
        
        // 分配内存
        testPtr = malloc_zone_malloc(ZQTCustomMallocZone, largeSize);
        XCTAssertNotEqual(testPtr, nullptr, @"测试内存分配应该成功");
                
        // 填充内存
        memset(testPtr, 0xAA, largeSize);
        
        // 扫描堆
        walker->scanHeap();
        
        // 记录节点数量和详细信息
        size_t currentCount = walker->getNodes().size();
        
        // 清理测试内存
        if (testPtr) {
            // 在释放前检查内存状态
            
            malloc_zone_free(ZQTCustomMallocZone, testPtr);
            
        }
        
        [self simpleCountMallocNode];
        NSLog(@"--%d-- after malloc %ld %ld %ld",i,currentCount,_zqtNodeCounts,_zqtCustomZoneNodeCounts);
        
        // 清理 walker
        delete walker;
        
        // 销毁 zone
        ZQTDestroyCustomMallocZone();
        
        *nodeCount = currentCount;
    }
    
    // 增加等待时间，给系统更多时间回收内存
    [NSThread sleepForTimeInterval:0.5];

    [self simpleCountMallocNode];
    NSLog(@"--%d-- after destroy %ld %ld %ld",i,*nodeCount,_zqtNodeCounts,_zqtCustomZoneNodeCounts);
}


- (void)testHeapScanNodeCount
{
    @autoreleasepool {
        // 等待一小段时间，让系统有机会清理
        [NSThread sleepForTimeInterval:1];
        
        [self simpleCountMallocNode];
        NSLog(@"start 总共count  %ld   customZone:%ld",_zqtNodeCounts,_zqtCustomZoneNodeCounts);

        // 执行多次创建、扫描、销毁操作
        const int iterations = 5;  // 减少迭代次数，方便观察
        
        NSInteger lastNodeCount = _zqtNodeCounts;
        for (int i = 0; i < iterations; i++) {
            @autoreleasepool {
                [self innerMethod:i lastNodeCount:&lastNodeCount];
            }
        }
        
        // 等待更长时间，让系统有机会清理内存
        [NSThread sleepForTimeInterval:2];
//        usleep(100000); // 100ms
        [self simpleCountMallocNode];
        NSLog(@"end 总共count  %ld   customZone:%ld",_zqtNodeCounts,_zqtCustomZoneNodeCounts);

//        XCTAssertLessThanOrEqual(finalMemoryGrowth, 1024 * 1024,
//            @"最终内存使用不应比初始状态增加超过1MB");
    }

}

@end

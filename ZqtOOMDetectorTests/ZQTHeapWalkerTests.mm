#import <XCTest/XCTest.h>
#include "ZQTHeapWalker.h"
#include <mach/mach.h>
#include <malloc/malloc.h>
#include <objc/runtime.h>

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

- (void)testHeapWalkerMemoryStability {
    // 记录初始内存使用情况
    struct task_basic_info t_info;
    mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT;
    task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
    vm_size_t initialMemory = t_info.resident_size;
    
    // 记录初始扫描结果
    ZQTCreateCustomMallocZone();
    ZQT::HeapWalker *initialWalker = new ZQT::HeapWalker();
    initialWalker->scanHeap();
    size_t initialNodeCount = initialWalker->getNodes().size();
    NSLog(@"初始节点数量: %zu 内存使用： %ld", initialNodeCount,initialMemory);
    delete initialWalker;
    ZQTDestroyCustomMallocZone();
    
    // 执行多次创建、扫描、销毁操作
    const int iterations = 5;
    NSMutableArray<NSNumber *> *memorySizes = [NSMutableArray array];
    NSMutableArray<NSNumber *> *nodeCounts = [NSMutableArray array];
    
    for (int i = 0; i < iterations; i++) {
        // 创建 zone
        ZQTCreateCustomMallocZone();
        
        // 创建新的 walker 实例
        ZQT::HeapWalker *walker = new ZQT::HeapWalker();
        
        // 分配一些测试内存
        void* testPtr = malloc_zone_malloc(ZQTCustomMallocZone, 1024);
        XCTAssertNotEqual(testPtr, nullptr, @"测试内存分配应该成功");
        
        // 扫描堆
        walker->scanHeap();
        
        // 记录内存使用情况
        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
        [memorySizes addObject:@(t_info.resident_size)];
        
        // 记录节点数量
        size_t currentCount = walker->getNodes().size();
        [nodeCounts addObject:@(currentCount)];
        NSLog(@"第 %d 次迭代节点数量: %zu", i + 1, currentCount);
        
        // 清理 walker
        delete walker;
        
        // 销毁 zone
        ZQTDestroyCustomMallocZone();
    }
    
    // 验证内存使用情况
    for (int i = 1; i < memorySizes.count; i++) {
        NSNumber *prevSize = memorySizes[i-1];
        NSNumber *currSize = memorySizes[i];
        double memoryGrowth = [currSize doubleValue] - [prevSize doubleValue];
        NSLog(@"第 %d 次迭代的内存增长:%f - %f = %f bytes", i,[currSize doubleValue],[prevSize doubleValue], memoryGrowth);
        XCTAssertLessThanOrEqual(memoryGrowth, 1024 * 1024,
            @"每次迭代的内存增长不应超过1MB");
    }
    
    // 验证节点数量
    for (int i = 1; i < nodeCounts.count; i++) {
        NSNumber *prevCount = nodeCounts[i-1];
        NSNumber *currCount = nodeCounts[i];
        NSInteger countDiff = [currCount integerValue] - [prevCount integerValue];
        NSLog(@"第 %d 次迭代的节点数量变化: %ld", i, countDiff);
        XCTAssertEqual([currCount integerValue], [prevCount integerValue], 
            @"每次迭代扫描到的节点数量应该相同");
    }
    
    // 验证最终内存使用情况
    task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
    double finalMemoryGrowth = t_info.resident_size - initialMemory;
    NSLog(@"最终内存增长: %f bytes", finalMemoryGrowth);
    XCTAssertLessThanOrEqual(finalMemoryGrowth, 1024 * 1024, 
        @"最终内存使用不应比初始状态增加超过1MB");
}

@end 

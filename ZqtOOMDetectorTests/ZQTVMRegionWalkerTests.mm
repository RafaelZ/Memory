#import <XCTest/XCTest.h>
#include "ZQTVMRegionWalker.h"
#include <mach/mach.h>
#include <malloc/malloc.h>

@interface ZQTVMRegionWalkerTests : XCTestCase

@end

@implementation ZQTVMRegionWalkerTests

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

- (void)testVMRegionWalkerInitialization {
    @autoreleasepool {
        ZQT::VMRegionWalker walker;
        NSLog(@"%s",__FUNCTION__);
        XCTAssertEqual(walker.getRegionInfos().size(), 0, @"初始化时 regionInfos 应该为空");
    }
}

- (void)testVMRegionWalkerScan {
    @autoreleasepool {
        ZQT::VMRegionWalker walker;
        NSLog(@"%s",__FUNCTION__);
        walker.startWalkingFromTask(mach_task_self());
        
        const auto& regions = walker.getRegionInfos();
        XCTAssertGreaterThan(regions.size(), 0, @"应该至少找到一个 VM Region");
        
        // 验证第一个 region 的基本属性
        if (!regions.empty()) {
            const auto& firstRegion = regions[0];
            XCTAssertGreaterThan(firstRegion.address, 0, @"Region 地址应该大于 0");
            XCTAssertGreaterThan(firstRegion.size, 0, @"Region 大小应该大于 0");
        }
    }
}

- (void)testVMRegionWalkerMallocRegions {
    @autoreleasepool {
        ZQT::VMRegionWalker walker;
        NSLog(@"%s",__FUNCTION__);
        // 分配一些测试内存
        void* testPtr1 = malloc(1024);
        void* testPtr2 = malloc(2048);
        
        walker.startWalkingFromTask(mach_task_self());
        const auto& regions = walker.getRegionInfos();
        
        // 查找 malloc 区域
        bool foundMallocRegion = false;
        for (const auto& region : regions) {
            if (region.is_malloc) {
                foundMallocRegion = true;
                XCTAssertTrue(region.is_readable, @"Malloc region 应该是可读的");
                break;
            }
        }
        
        XCTAssertTrue(foundMallocRegion, @"应该找到至少一个 malloc region");
        
        // 清理测试内存
        free(testPtr1);
        free(testPtr2);
    }
}

- (void)testVMRegionWalkerClear {
    @autoreleasepool {
        ZQT::VMRegionWalker walker;
        
        // 先扫描一次
        walker.startWalkingFromTask(mach_task_self());
        XCTAssertGreaterThan(walker.getRegionInfos().size(), 0, @"扫描后应该有 regions");
        
        // 清理
        walker.clear();
        XCTAssertEqual(walker.getRegionInfos().size(), 0, @"清理后应该没有 regions");
        
        // 再次扫描
        walker.startWalkingFromTask(mach_task_self());
        XCTAssertGreaterThan(walker.getRegionInfos().size(), 0, @"再次扫描后应该有 regions");
    }
}

- (void)testVMRegionWalkerMoveSemantics {
    @autoreleasepool {
        ZQT::VMRegionWalker walker1;
        walker1.startWalkingFromTask(mach_task_self());
        
        // 移动构造
        ZQT::VMRegionWalker walker2(std::move(walker1));
        XCTAssertGreaterThan(walker2.getRegionInfos().size(), 0, @"移动构造后应该保留 regions");
        
        // 移动赋值
        ZQT::VMRegionWalker walker3;
        walker3 = std::move(walker2);
        XCTAssertGreaterThan(walker3.getRegionInfos().size(), 0, @"移动赋值后应该保留 regions");
    }
}

- (void)testVMRegionWalkerInvalidTask {
    @autoreleasepool {
        ZQT::VMRegionWalker walker;
        walker.startWalkingFromTask(MACH_PORT_NULL);
        XCTAssertEqual(walker.getRegionInfos().size(), 0, @"无效的 task 不应该产生 regions");
    }
}

@end 

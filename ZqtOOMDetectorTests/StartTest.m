//
//  StartTest.m
//  ZqtOOMDetectorTests
//
//  Created by 张千通 on 2025/5/12.
//

#import <XCTest/XCTest.h>
#include <mach/mach.h>
#include <malloc/malloc.h>

@interface StartTest : XCTestCase

@end

@implementation StartTest

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testExample {
    // 等待一小段时间，让系统有机会清理
    [NSThread sleepForTimeInterval:1];
    
    // 记录初始内存使用情况
    struct task_basic_info t_info;
    mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT;
    task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
    vm_size_t initialMemory = t_info.resident_size;
    NSLog(@"测试开始前内存用量： %ld", initialMemory);

    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
}

//- (void)testPerformanceExample {
//    // This is an example of a performance test case.
//    [self measureBlock:^{
//        // Put the code you want to measure the time of here.
//    }];
//}

@end

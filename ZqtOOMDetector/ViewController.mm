//
//  ViewController.m
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/10.
//

#import "ViewController.h"
#include "ZQTHeapWalker.h"
#import <malloc/malloc.h>

@interface ViewController ()

@end

size_t getUsedMemory(void) {
    malloc_statistics_t stats;
    // 传入NULL代表获取默认内存区域的统计信息
    malloc_zone_statistics(NULL, &stats);
    return stats.size_in_use;
}

@implementation ViewController
{
    void * _testptr;
}

- (void)viewDidLoad {
    [super viewDidLoad];
//    NSLog(@"a %zu",getUsedMemory()/(1024*1024));
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        [self test];
//    });
//    // Do any additional setup after loading the view.
//
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        NSLog(@"c %zu",getUsedMemory()/(1024*1024));
//    });
}


- (void)test
{
    ZQTCreateCustomMallocZone();
    const size_t largeSize = 1024 * 1024 * 50;
    void* ptr = malloc_zone_malloc(ZQTCustomMallocZone,largeSize);
    memset(ptr, 0xAA, largeSize);
    
    // 检查分配的内存大小
    size_t allocatedSize = malloc_size(ptr);
    NSLog(@"分配的内存大小: %zu MB", allocatedSize / (1024 * 1024));
    NSLog(@"b %zu",getUsedMemory()/(1024*1024));
    // 释放内存
//    free(ptr);
    ZQTDestroyCustomMallocZone();
    
    // 尝试再次使用刚释放的内存（危险！仅用于测试）
    // memset(ptr, 0x55, largeSize); // 这会导致崩溃，证明内存已释放
    
    // 强制触发内存回收（仅供研究，不建议在生产环境使用）
    return;
    // 记录初始内存使用情况
//    struct task_basic_info t_info;
//    mach_msg_type_number_t t_info_count = TASK_BASIC_INFO_COUNT;
//    task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
//    vm_size_t initialMemory = t_info.resident_size;
//    NSLog(@"测试开始前内存用量： %ld", initialMemory);

//    ZQTCreateCustomMallocZone();
//    const size_t largeSize = 1024 * 1024 * (50 ); // 每次增加10MB
////    testPtr = malloc_zone_malloc(ZQTCustomMallocZone, largeSize);
//    _testptr = malloc(largeSize);
//
//    memset(_testptr, 0xAA, largeSize);
    
    // 记录初始内存使用情况
//    task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
//    NSLog(@"测试开始前内存用量： %ld", t_info.resident_size);

//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//    [NSThread sleepForTimeInterval:5];
//        malloc_zone_free(ZQTCustomMallocZone, testPtr);
//        ZQTDestroyCustomMallocZone();
//        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
//        NSLog(@"测试开始前内存用量： %ld", t_info.resident_size);
//        task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)&t_info, &t_info_count);
//        NSLog(@"测试开始前内存用量： %ld", t_info.resident_size);

//    });
}

@end

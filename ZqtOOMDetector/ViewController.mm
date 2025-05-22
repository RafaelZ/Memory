//
//  ViewController.m
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/10.
//

#import "ViewController.h"
#include "ZQTHeapWalker.h"
#import <malloc/malloc.h>
#include "ZqtCppTest.hpp"
#include <iostream>
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self simpleCountMallocNode];
        NSLog(@"start 总共count  %ld   customZone:%ld",_zqtNodeCounts,_zqtCustomZoneNodeCounts);
    });
//    CreateAndUseTestClasses();
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

kern_return_t memory_reader(task_t task, vm_address_t remote_address, vm_size_t size, void **local_memory)
{
    *local_memory = (void*) remote_address;
    return KERN_SUCCESS;
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

@end

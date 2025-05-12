//
//  ZQTVMRegionWalker.m
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/10.
//

#import "ZQTVMRegionWalker.h"
#import <mach/mach.h>
#import <mach/vm_map.h>
#import "ZQTCustomMallocZone.h"
#import "FLEXObjcInternal.h"
#include "ZQTVMStatistics.hpp"

namespace ZQT {

VMRegionWalker::VMRegionWalker() {
    regionInfos.reserve(MAX_REGIONS);
}

VMRegionWalker::~VMRegionWalker() {
    clear();
}

VMRegionWalker::VMRegionWalker(VMRegionWalker&& other) noexcept
    : regionInfos(std::move(other.regionInfos))
{}

VMRegionWalker& VMRegionWalker::operator=(VMRegionWalker&& other) noexcept {
    if (this != &other) {
        regionInfos = std::move(other.regionInfos);
    }
    return *this;
}

void VMRegionWalker::startWalkingFromTask(task_t task) {
    if (task == MACH_PORT_NULL) {
        NSLog(@"Invalid task port");
        return;
    }
    
    // 清理之前的数据
    clear();
    
    // 从地址 0 开始遍历
    vm_address_t address = 0;
    natural_t depth = 0;
    
    while (true) {
        vm_size_t size;
        struct vm_region_submap_info_64 info;
        mach_msg_type_number_t infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;
        
        kern_return_t krc = vm_region_recurse_64(task, &address, &size, &depth, (vm_region_info_64_t)&info, &infoCount);
        if (krc == KERN_INVALID_ADDRESS) {
            break;
        }
        
        if (krc != KERN_SUCCESS) {
            NSLog(@"Failed to get region info: %d", krc);
            break;
        }
        
        if (regionInfos.size() >= MAX_REGIONS) {
            NSLog(@"Maximum number of regions reached");
            break;
        }
        
        if (info.is_submap) {
            if (depth < MAX_RECURSION_DEPTH) {
                depth++;
                continue;
            }
        } else {
            const char *regionName = vm_region_usertag_name(info.user_tag);
            bool isReadable = isPointerReadable((void *)address);
            bool isMalloc = vm_region_is_malloc_usertag(info.user_tag);
            
            VMRegionInfo regionInfo;
            regionInfo.address = address;
            regionInfo.size = size;
            regionInfo.protection = info.protection;
            regionInfo.max_protection = info.max_protection;
            regionInfo.inheritance = info.inheritance;
            regionInfo.offset = info.offset;
            regionInfo.behavior = info.behavior;
            regionInfo.user_tag = info.user_tag;
            regionInfo.pages_resident = info.pages_resident;
            regionInfo.pages_swapped_out = info.pages_swapped_out;
            regionInfo.pages_dirtied = info.pages_dirtied;
            regionInfo.region_name = regionName ? regionName : "";
            regionInfo.is_readable = isReadable;
            regionInfo.is_malloc = isMalloc;
            
            regionInfos.push_back(std::move(regionInfo));
            
//            NSLog(@"Found VM Region: 0x%lx-0x%lx size:%ld depth=%d user_tag=%d regionName:%s readable:%d isMalloc:%d",
//                  address, (address+size), size, depth, info.user_tag, regionName, isReadable, isMalloc);
        }
        
        // 移动到下一个区域
        address += size;
    }
}

bool VMRegionWalker::isPointerReadable(void* ptr) {
    if (!ptr) {
        return false;
    }
    
    vm_size_t size = 0;
    kern_return_t result = vm_read_overwrite(mach_task_self(), (vm_address_t)ptr, 1, (vm_address_t)ptr, &size);
    return result == KERN_SUCCESS;
}

void VMRegionWalker::clear() {
    regionInfos.clear();
}

} // namespace ZQT

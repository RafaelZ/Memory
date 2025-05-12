//
//  ZQTVMRegionWalker.h
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/10.
//

#ifndef ZQTVMRegionWalker_h
#define ZQTVMRegionWalker_h

#include <mach/mach.h>
#include <vector>
#include <string>
#include "ZQTMemoryTypes.hpp"

namespace ZQT {

struct VMRegionInfo {
    vm_address_t address;
    vm_size_t size;
    vm_prot_t protection;
    vm_prot_t max_protection;
    vm_inherit_t inheritance;
    memory_object_offset_t offset;
    vm_behavior_t behavior;
    unsigned short user_tag;
    unsigned int pages_resident;
    unsigned int pages_swapped_out;
    unsigned int pages_dirtied;
    std::string region_name;
    bool is_readable;
    bool is_malloc;
    bool is_custom_zone;
};

class VMRegionWalker {
public:
    static constexpr size_t MAX_RECURSION_DEPTH = 8;
    static constexpr size_t MAX_REGIONS = 10000;
    
    VMRegionWalker();
    ~VMRegionWalker();
    
    // 禁用拷贝
    VMRegionWalker(const VMRegionWalker&) = delete;
    VMRegionWalker& operator=(const VMRegionWalker&) = delete;
    
    // 允许移动
    VMRegionWalker(VMRegionWalker&& other) noexcept;
    VMRegionWalker& operator=(VMRegionWalker&& other) noexcept;
    
    void startWalkingFromTask(task_t task);
    void clear();
    
    const CustomVector<VMRegionInfo>& getRegionInfos() const { return regionInfos; }
    
private:
    void walkRegionsFromTask(task_t task, vm_address_t address, natural_t depth);
    bool isPointerReadable(void* ptr);
    
    CustomVector<VMRegionInfo> regionInfos;
};

} // namespace ZQT

#endif /* ZQTVMRegionWalker_h */

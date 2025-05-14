#ifndef ZQTHeapWalker_hpp
#define ZQTHeapWalker_hpp

#include "ZQTMemoryTypes.hpp"
#include <mach/mach.h>
#include "ZQTObjCIdentifierStrategy.h"

namespace ZQT {

class HeapWalker {
public:
    static constexpr size_t INITIAL_CAPACITY = 1024;
    HeapWalker(ObjCIdentifierStrategy* strategy = nullptr);
    ~HeapWalker();
    
    // 禁用拷贝
    HeapWalker(const HeapWalker&) = delete;
    HeapWalker& operator=(const HeapWalker&) = delete;
    
    // 允许移动
    HeapWalker(HeapWalker&& other) noexcept;
    HeapWalker& operator=(HeapWalker&& other) noexcept;
    
    void scanHeap();
    void processNodes();
    void clear();
    
    const CustomMap<uintptr_t, MemoryNode>& getNodes() const { return nodes; }
    const CustomVector<MemoryNode*>& getNodePtrs() const { return nodePtrs; }
    
    size_t getPeakMemoryUsage() const { return tracker.peak_allocated; }
    size_t getCopyCount() const { return tracker.copy_count; }
    
    // 添加静态回调函数声明
    static void range_callback(task_t task, void *context, unsigned type, vm_range_t *ranges, unsigned rangeCount);
    
private:
    struct MemoryTracker {
        size_t total_allocated = 0;
        size_t peak_allocated = 0;
        size_t copy_count = 0;
        
        void record_allocation(size_t size) {
            total_allocated += size;
            peak_allocated = std::max(peak_allocated, total_allocated);
        }
        
        void record_deallocation(size_t size) {
            total_allocated -= size;
        }
        
        void record_copy() {
            copy_count++;
        }
    };
    
    CustomMap<uintptr_t, MemoryNode> nodes;
    CustomVector<MemoryNode*> nodePtrs;
    MemoryTracker tracker;
    ObjCIdentifierStrategy* objcIdentifierStrategy;

    bool is_from_custom_zone(void* ptr) {
        if (!ptr) return false;
        return malloc_zone_from_ptr(ptr) == ZQTCustomMallocZone;
    }
    
    void scanMallocZone(malloc_zone_t* zone);
    void scanVMRange(vm_address_t address, vm_size_t size);
};

} // namespace ZQT

#endif /* ZQTHeapWalker_hpp */ 

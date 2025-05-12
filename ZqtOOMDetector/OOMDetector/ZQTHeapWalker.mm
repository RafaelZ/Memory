#include "ZQTHeapWalker.h"
#include <mach/mach.h>
#include <malloc/malloc.h>
#import "FLEXObjcInternal.h"


namespace ZQT {

HeapWalker::HeapWalker() {
    nodes.reserve(INITIAL_CAPACITY);
    nodePtrs.reserve(INITIAL_CAPACITY);
}

HeapWalker::~HeapWalker() {
    clear();
}

HeapWalker::HeapWalker(HeapWalker&& other) noexcept
    : nodes(std::move(other.nodes))
    , nodePtrs(std::move(other.nodePtrs))
    , tracker(std::move(other.tracker))
{}

HeapWalker& HeapWalker::operator=(HeapWalker&& other) noexcept {
    if (this != &other) {
        nodes = std::move(other.nodes);
        nodePtrs = std::move(other.nodePtrs);
        tracker = std::move(other.tracker);
    }
    return *this;
}

kern_return_t memory_reader(task_t task, vm_address_t remote_address, vm_size_t size, void **local_memory)
{
    *local_memory = (void*) remote_address;
    return KERN_SUCCESS;
}

// 将 range_callback 改为静态成员函数
void HeapWalker::range_callback(task_t task, void *context, unsigned type, vm_range_t *ranges, unsigned rangeCount)
{
    HeapWalker* walker = static_cast<HeapWalker*>(context);
    if (!walker) return;
    
    for (unsigned i = 0; i < rangeCount; i++) {
        vm_range_t range = ranges[i];
        if (range.address && range.size > 0) {
            walker->scanVMRange(range.address, range.size);
        }
    }
}

void HeapWalker::scanHeap() {
    // 清理并预分配
    clear();
    nodes.reserve(INITIAL_CAPACITY);
    nodePtrs.reserve(INITIAL_CAPACITY);
    
    // 扫描所有 malloc zones
    unsigned int count;
    vm_address_t *zones = NULL;
    kern_return_t err = malloc_get_all_zones(mach_task_self(), memory_reader, &zones, &count);
    if (err != KERN_SUCCESS) {
        return;
    }

    for (unsigned int i = 0; i < count; i++) {
        malloc_zone_t *zone = (malloc_zone_t *)zones[i];
        if (zone) {
            scanMallocZone(zone);
        }
    }
}

void HeapWalker::scanMallocZone(malloc_zone_t* zone) {
    if (!zone || !zone->introspect) {
        return;
    }
    
    // 使用字符串比较来判断 zone
    const char* zoneName = malloc_get_zone_name(zone);
    if (zoneName && strcmp(zoneName, ZQTCustomMallocZoneName) == 0) {
        return;
    }
    
    malloc_introspection_t *introspection = zone->introspect;

    // 检查必要的函数指针是否有效
    void (*lock_zone)(malloc_zone_t *zone) = introspection->force_lock;
    void (*unlock_zone)(malloc_zone_t *zone) = introspection->force_unlock;
    
    BOOL lockZoneValid = FLEXPointerIsReadable((const void *)lock_zone);
    BOOL unlockZoneValid = FLEXPointerIsReadable((const void *)unlock_zone);

    if (!lockZoneValid || !unlockZoneValid) {
        return;
    }

    // 锁定 zone 并扫描
    lock_zone(zone);
    @try {
        introspection->enumerator(mach_task_self(),
                                (void *)this,  // 传递 this 作为上下文
                                MALLOC_PTR_IN_USE_RANGE_TYPE,
                                (vm_address_t)zone,
                                memory_reader,
                                &HeapWalker::range_callback);  // 使用静态成员函数
    } @catch (NSException *exception) {
        // 处理可能的异常
        NSLog(@"Exception while scanning zone: %@", exception);
    } @finally {
        // 确保解锁
        unlock_zone(zone);
    }
}

void HeapWalker::scanVMRange(vm_address_t address, vm_size_t size) {
    // 创建新节点
    auto node = make_unique_custom<MemoryNode>();
    node->address = address;
    node->size = size;
        
    // 插入节点
    nodes[address] = std::move(*node);
    nodePtrs.push_back(&nodes[address]);
    
    // 记录内存使用
    tracker.record_allocation(sizeof(MemoryNode));
}

void HeapWalker::clear() {
    nodes.clear();
    nodePtrs.clear();
    tracker = MemoryTracker();
}

} // namespace ZQT 

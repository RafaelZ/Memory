#include "ZQTHeapWalker.h"
#include <mach/mach.h>
#include <malloc/malloc.h>
#include "ZQTCFStringHelper.h"
#import "FLEXObjcInternal.h"
#include "CppClassInfo.h"

namespace ZQT {



HeapWalker::HeapWalker(ObjCIdentifierStrategy* strategy) {
    if (strategy) {
        objcIdentifierStrategy = strategy;
    }
    nodes.reserve(INITIAL_CAPACITY);
    nodePtrs.reserve(INITIAL_CAPACITY);
}

HeapWalker::~HeapWalker() {
    delete objcIdentifierStrategy;
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

void range_callback(task_t task, void *context, unsigned type, vm_range_t *ranges, unsigned rangeCount)
{
    int temp = 0;
    if (context != nullptr) {
        temp = *(int *)context;
    }
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

void HeapWalker::processNodes() {
    for (int i = 0; i < nodePtrs.size();i++) {
        MemoryNode *node = nodePtrs[i];
        if (node->type == MemoryNodeType::CFObj) {
            CFTypeID cftypeid = CFGetTypeID((CFTypeRef)node->address);
            try {
                CFStringRef cfClassName = CFCopyTypeIDDescription(cftypeid);
                std::string name = ZQT_CFStringToStdString(cfClassName);
                node->name = name;
            } catch (...) {
                node->name = "__NSCFUnknowType";
                printf("catch exception");
            }
        }
    }
}

void HeapWalker::scanHeap() {
    // 清理并预分配
    clear();
    nodes.reserve(INITIAL_CAPACITY);
    nodePtrs.reserve(INITIAL_CAPACITY);
    objcIdentifierStrategy->updateClassList();
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
            // 检查是否是自定义 zone
            const char* zoneName = malloc_get_zone_name(zone);
            if (zoneName && strcmp(zoneName, ZQTCustomMallocZoneName) == 0) {
                continue; // 跳过自定义 zone
            }
            scanMallocZone(zone);
        }
    }
}

void HeapWalker::scanMallocZone(malloc_zone_t* zone) {
    if (!zone || !zone->introspect) {
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
                                &(range_callback));  // 使用静态成员函数
    } @catch (NSException *exception) {
        // 处理可能的异常
        NSLog(@"Exception while scanning zone: %@", exception);
    } @finally {
        // 确保解锁
        unlock_zone(zone);
    }
}

void HeapWalker::scanVMRange(vm_address_t address, vm_size_t size) {
    MemoryNode *node = nullptr;
    if (objcIdentifierStrategy != nullptr) {
        node = objcIdentifierStrategy->identifyObjectAtAddress(address, size);
    }
    if (node == nullptr) {
        return;
    }
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

void HeapWalker::walkHeapChunkAndIdentifyObjects(const HeapChunkInfo& chunk) {
    if (!objcIdentifierStrategy || !delegate_) {
        ZQTLOG_WARNING("HeapWalker: Strategy or Delegate not set.");
        return;
    }
    ZQTLOG_INFO("HeapWalker: Walking chunk '%s' from 0x%lx to 0x%lx", chunk.name.c_str(), chunk.startAddress, chunk.endAddress);

    vm_address_t currentAddress = chunk.startAddress;
    while (currentAddress < chunk.endAddress) {
        if (currentAddress == 0) { // 安全检查，防止currentAddress变为0导致死循环
            ZQTLOG_WARNING("HeapWalker: currentAddress is 0, breaking loop to prevent infinite loop in chunk %s", chunk.name.c_str());
            break;
        }
        if (visitedAddresses_.count(currentAddress)) {
            // 这个地址已经被作为某个对象的一部分访问过了，或者它是一个已知对象的起始地址
            // 我们需要知道之前跳过了多大的块才能正确前进，但这由 processPotentialObject 内部的 malloc_size 决定
            // 最简单的方式是，如果它已被访问，则它已经被正确地跳过了。
            // 但为了保险，如果一个地址已经被标记为对象的起始，我们可能需要一种方式知道该对象的大小以确保正确跳跃。
            // 不过，目前的逻辑是 processPotentialObject 会处理跳跃。
            // 这里简单地前进一个对齐单位，依赖于 processPotentialObject 中更精确的跳跃。
            // 更好的做法是 visitedAddresses_ 存储<地址, 大小>对，但这会增加复杂性。
            // 假设 processPotentialObject 发现对象后会正确标记并让外部循环跳过。
            // 如果 visitedAddresses_ 仅仅标记了起始地址，而没有关联大小，那么这里简单前进可能导致重复检查对象的内部。
            // **修正思路**：processPotentialObject 在找到对象并使用 malloc_size 后，
            // 它应该负责更新 currentAddress 到下一个潜在对象的起始位置。
            // 因此，这里的外部循环应该在 processPotentialObject 内部处理currentAddress的更新。
            // 为简化，我们先让 processPotentialObject 返回它处理了多少字节，然后在这里更新。
            // 或者，processPotentialObject 自己更新一个外部的 currentAddress (通过引用传递)。
            // 我们将采用让 processPotentialObject 返回消耗字节数的方式。
            
            // 此处的逻辑需要调整，因为 currentAddress 的主要推进应该由 processPotentialObject 内部的 malloc_size 驱动。
            // 如果一个地址在 visitedAddresses_ 中，意味着它已经被处理过，并且 walk 已从那里跳过。
            // 因此，如果进入这个if，说明之前的跳跃可能有问题，或者对齐导致重新命中。
            // 一个更简单的方式是，如果 processPotentialObject 识别了一个对象，它会告诉我们跳过多远。
            currentAddress += alignment_; // 暂时简单前进，依赖processPotentialObject的精确跳跃
            continue;
        }

        processPotentialObject(currentAddress, chunk); // processPotentialObject 现在需要负责更新 currentAddress 或返回消耗的字节数
        
        // processPotentialObject 内部会处理 currentAddress 的前进，基于 malloc_size。
        // 所以外部循环的 currentAddress += alignment_ 需要移除或调整。
        // 现在假设 processPotentialObject 不直接修改 currentAddress，而是我们在这里根据其结果调整。
        // 但为了让 processPotentialObject 控制跳跃，我们将修改其职责。
        // **重要修改**：processPotentialObject 将会尝试识别对象，如果成功，
        // 它会使用 malloc_size 来确定整个分配块的大小，并返回这个大小。
        // 如果未识别对象或 malloc_size 为0，则返回 alignment_。
        // walkHeapChunkAndIdentifyObjects 将使用这个返回值来增加 currentAddress。
        
        // **以下是调用 processPotentialObject 的新逻辑，并由它返回跳跃的字节数**
        // vm_size_t bytesConsumed = processAndAdvance(currentAddress, chunk);
        // currentAddress += bytesConsumed; 
        // (上面的逻辑移入下一段，processPotentialObject直接修改currentAddress)

        // **修改后的逻辑：processPotentialObject 现在直接修改 currentAddress**
        // 因此，外部循环只需要检查 currentAddress 是否越界。
        // 为了避免 processPotentialObject 签名大改，我们暂时让它返回消耗的字节数。

        vm_address_t nextAddressAfterProcessing = currentAddress; // 记录处理前的地址
        processPotentialObject(currentAddress, chunk); // 让它在内部处理，或者返回信息

        // 如果 processPotentialObject 内部没有推进 currentAddress 的逻辑，我们需要在这里推进
        // 假设 processPotentialObject 发现对象后，会标记 visited，而实际的跳跃由 malloc_size 决定
        // ZQTHeapWalker::processPotentialObject 需要被修改以返回跳过的字节数

        // **重构 ZQTHeapWalker::processPotentialObject**
        // 让它返回实际应该跳过的字节数（基于malloc_size或对齐）
        vm_size_t jumpSize = getSizeToJump(currentAddress, chunk); // 新辅助函数
        if (jumpSize == 0) { // 保护，防止无限循环
            ZQTLOG_ERROR("HeapWalker: Detected jumpSize of 0 at 0x%lx for chunk %s. Advancing by alignment_ to prevent stall.", currentAddress, chunk.name.c_str());
            currentAddress += alignment_;
        } else {
            currentAddress += jumpSize;
        }
    }
}

// 新的辅助函数，用于决定在给定地址处应该跳过多少字节
// 它会尝试识别对象，并使用 malloc_size 来确定实际分配大小
vm_size_t HeapWalker::getSizeToJump(vm_address_t address, const HeapChunkInfo& chunk) {
    if (address == 0 || address >= chunk.endAddress) {
        return alignment_; // 或返回一个特殊值表示结束
    }

    if (visitedAddresses_.count(address)) {
        // 如果已经被访问过，理论上我们应该知道它的大小并跳过。
        // 但由于 visitedAddresses_ 只存起始地址，这里简单返回 alignment_，依赖之前的正确跳跃。
        // 这是一个潜在的低效点，如果对齐导致重复命中已处理对象的内部。
        return alignment_;
    }

    vm_size_t allocatedSize = 0;
    if (ZQT::Utils::isReadableAddress(address, 1)) { // 确保至少能读一个字节以调用malloc_size
        allocatedSize = malloc_size(reinterpret_cast<const void*>(address));
    }

    if (allocatedSize < minObjectSize_ && allocatedSize != 0) { // malloc_size 可能返回小于minObjectSize但非0的值，比如小的系统分配
        // 如果分配大小过小，直接跳过这个分配块，除非它是0（表示可能是非malloc指针）
        return allocatedSize > 0 ? allocatedSize : alignment_;
    }
    
    // 即使 allocatedSize 为 0 (例如非 malloc 指针或无效指针)，仍尝试识别
    // 因为某些对象可能不在标准 malloc 堆上，但我们仍想识别它们 (例如直接vm_allocate的区域)
    // 但对于常规堆扫描，allocatedSize > 0 是主要情况。

    ObjectIdentifierStrategy::MemoryNode* memoryNode = objcIdentifierStrategy->identifyObjectAtAddress(address, allocatedSize);

    if (memoryNode) {
        // 对象被识别
        if (memoryNode->size == 0 && allocatedSize > 0) {
            // 如果策略没有返回实例大小 (例如C++对象)，但我们有分配大小，用它来记录节点大小
            // 但 MemoryNode->size 应该代表"实例"大小，HeapWalker用allocatedSize跳。
            // 这里主要是为了让delegate得到一个有意义的size（即使是分配大小）
            // 但我们坚持MemoryNode.size是实例大小，策略自己填，这里就不覆盖了
        }

        // 检查对象大小是否在合理范围内 (注意：memoryNode->size 是实例大小)
        // 而 allocatedSize 是整个内存块的大小
        bool sizeValid = (allocatedSize == 0) || // 如果没有分配大小信息，则跳过大小检查
                         (allocatedSize >= minObjectSize_ && allocatedSize <= maxObjectSize_);
        
        // 主要的判断是，我们有一个分配块 allocatedSize
        // 里面有一个对象 memoryNode->name，其宣称的实例大小是 memoryNode->size

        if (sizeValid) { // 或者我们可以只依赖 allocatedSize 是否合理
            if (delegate_) {
                // 传递给delegate的size应该是实例大小
                // 如果 memoryNode->size 为0 (比如C++对象)，可以考虑传 allocatedSize，但这会混淆语义
                // 我们需要明确 MemoryNode.size 的定义。之前定为实例大小。
                delegate_->walkerDidFindObject(this, *memoryNode, allocatedSize, chunk);
            }
            // 标记整个分配块为已访问，从 address 开始，长度为 allocatedSize
            // 确保至少跳过 alignment_
            markMemoryAsVisited(address, allocatedSize > 0 ? allocatedSize : alignment_); 
            ZQT::Utils::destroyCustomUniquePtr(memoryNode); // 释放策略创建的节点
            return allocatedSize > 0 ? allocatedSize : alignment_;
        } else {
            ZQTLOG_DEBUG("HeapWalker: Object '%s' at 0x%lx has invalid allocated size %lu (instance size %lu). Min: %lu, Max: %lu", 
                         memoryNode->name, address, allocatedSize, memoryNode->size, minObjectSize_, maxObjectSize_);
            ZQT::Utils::destroyCustomUniquePtr(memoryNode);
        }
    } else {
        // 没有识别到对象，或者 allocatedSize < minObjectSize_ (已在前面处理)
        // 如果 allocatedSize > 0，说明这是一块已分配但未识别为我们关心对象的内存，跳过它
        if (allocatedSize > 0) {
            markMemoryAsVisited(address, allocatedSize); // 标记为已访问，即使未识别
            return allocatedSize;
        }
    }
    // 默认情况下，如果没有识别到对象且没有 allocatedSize，则只前进一个对齐单位
    return alignment_;
}


void HeapWalker::processPotentialObject(vm_address_t address, const HeapChunkInfo& chunk) {
    // 这个函数现在被 getSizeToJump 替代了主要逻辑。
    // 保留它是为了最小化对 walkHeapChunkAndIdentifyObjects 的直接修改，
    // 但实际上 walkHeapChunkAndIdentifyObjects 现在应该调用 getSizeToJump 并用其返回值前进。
    // 为了清晰，我们将把 getSizeToJump 的逻辑直接内联或让 walkHeapChunkAndIdentifyObjects 调用它。
    // 此函数不再被 walkHeapChunkAndIdentifyObjects 的主循环直接调用来驱动currentAddress的前进。
}


void HeapWalker::markMemoryAsVisited(vm_address_t startAddress, vm_size_t actualAllocatedSize) {
    if (actualAllocatedSize == 0) return;
    // 标记这个内存块的起始地址。当下次迭代到这个地址时，
    // getSizeToJump 中的 visitedAddresses_.count(address) 会检测到，并返回 alignment_，
    // 这依赖于 getSizeToJump 的返回值被正确用于推进 currentAddress。
    // 一个更鲁棒的方法是，如果一个地址被访问过，我们就知道它的大小，然后直接跳过那么多。
    // 但这需要 visitedAddresses_ 存储 <地址, 大小>。
    // 目前的简化版：只标记起始地址。
    visitedAddresses_.insert(startAddress);
    
    // 如果需要标记整个范围内的每个对齐点（可能过于消耗内存和时间）：
    // for (vm_address_t i = 0; i < actualAllocatedSize; i += alignment_) {
    //     visitedAddresses_.insert(startAddress + i);
    // }
}

} // namespace ZQT 

//
//  MemoryNode.h
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/14.
//

#ifndef MemoryNode_h
#define MemoryNode_h
#include <objc/runtime.h>
#include "ZQTCustomAllocator.hpp"
#include "ZQTMemoryTypes.hpp"
#include <mach/mach.h>

namespace ZQT {
enum class MemoryNodeType:int {
    Unknown = 0,
    Obj = 1,
    CFObj = 2,
    PointerTagged = 3,
    Cpp = 4,
    Malloc = 5,
};

// 内存节点结构体
struct MemoryNode {
    Class objectClass;
    CustomString name;
    uintptr_t address;
    size_t size;
    MemoryNodeType type;
    CustomVector<uintptr_t> references;
    
    MemoryNode() = default;
    
    MemoryNode(const MemoryNode& other)
        : address(other.address)
        , size(other.size)
        , type(other.type)
        , references(other.references)
        , objectClass(other.objectClass)
        , name(other.name)
    {
        if (!is_from_custom_zone(this)) {
            throw std::runtime_error("Copy allocation not from custom zone");
        }
    }
    
    MemoryNode& operator=(const MemoryNode& other) {
        if (this != &other) {
            address = other.address;
            size = other.size;
            type = other.type;
            references = other.references;
            name = other.name;
            objectClass = other.objectClass;
            if (!is_from_custom_zone(this)) {
                throw std::runtime_error("Copy assignment not from custom zone");
            }
        }
        return *this;
    }
    
    MemoryNode(MemoryNode&& other) noexcept
        : address(other.address)
        , size(other.size)
        , type(std::move(other.type))
        , references(std::move(other.references))
        , objectClass(other.objectClass)
        , name(other.name)
    {}
    
    MemoryNode& operator=(MemoryNode&& other) noexcept {
        if (this != &other) {
            address = other.address;
            size = other.size;
            type = std::move(other.type);
            references = std::move(other.references);
            name = other.name;
            objectClass = other.objectClass;
        }
        return *this;
    }
    
private:
    bool is_from_custom_zone(void* ptr) {
        if (!ptr) return false;
        return malloc_zone_from_ptr(ptr) == ZQTCustomMallocZone;
    }
};

} // namespace ZQT

#endif /* MemoryNode_h */

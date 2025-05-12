#ifndef ZQTMemoryTypes_hpp
#define ZQTMemoryTypes_hpp

#include <memory>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include "ZQTCustomMallocZone.h"
#include <mach/mach.h>
#include <objc/runtime.h>

namespace ZQT {

// 自定义分配器
template<typename T>
class CustomZoneAllocator {
public:
    using value_type = T;
    using pointer = T*;
    using const_pointer = const T*;
    using reference = T&;
    using const_reference = const T&;
    using size_type = std::size_t;
    using difference_type = std::ptrdiff_t;
    
    template<typename U>
    struct rebind {
        using other = CustomZoneAllocator<U>;
    };
    
    CustomZoneAllocator() = default;
    template<typename U>
    CustomZoneAllocator(const CustomZoneAllocator<U>&) {}
    
    pointer allocate(size_type n) {
        if (n == 0) return nullptr;
        void* ptr = malloc_zone_malloc(ZQTCustomMallocZone, n * sizeof(T));
        if (!ptr) {
            throw std::bad_alloc();
        }
        return static_cast<pointer>(ptr);
    }
    
    void deallocate(pointer p, size_type n) {
        if (p) {
            malloc_zone_free(ZQTCustomMallocZone, p);
        }
    }
    
    bool operator==(const CustomZoneAllocator& other) const {
        return true;
    }
    
    bool operator!=(const CustomZoneAllocator& other) const {
        return false;
    }
};

// 内存节点结构体
struct MemoryNode {
    enum class MemoryNodeType:int {
        Unknown = 0,
        Obj = 1,
        PointerTagged = 2,
        Cpp = 3,
    };
    uintptr_t address;
    size_t size;
    MemoryNodeType type;
    std::vector<uintptr_t, CustomZoneAllocator<uintptr_t>> references;
    
    MemoryNode() = default;
    
    MemoryNode(const MemoryNode& other)
        : address(other.address)
        , size(other.size)
        , type(other.type)
        , references(other.references)
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
    {}
    
    MemoryNode& operator=(MemoryNode&& other) noexcept {
        if (this != &other) {
            address = other.address;
            size = other.size;
            type = std::move(other.type);
            references = std::move(other.references);
        }
        return *this;
    }
    
private:
    bool is_from_custom_zone(void* ptr) {
        if (!ptr) return false;
        return malloc_zone_from_ptr(ptr) == ZQTCustomMallocZone;
    }
};

// 使用自定义分配器的容器类型
template<typename T>
using CustomVector = std::vector<T, CustomZoneAllocator<T>>;


//template <class _Value, class _Hash = hash<_Value>, class _Pred = equal_to<_Value>, class _Alloc = allocator<_Value> >
template<typename V>
using CustomUnorderedSet = std::unordered_set<V,std::hash<V>,std::equal_to<V>,CustomZoneAllocator<V>>;

template<typename K, typename V>
using CustomMap = std::unordered_map<
    K,
    V,
    std::hash<K>,
    std::equal_to<K>,
    CustomZoneAllocator<std::pair<const K, V>>
>;

// 自定义删除器
template<typename T>
struct CustomZoneDeleter {
    void operator()(T* ptr) const {
        if (ptr) {
            ptr->~T();
            malloc_zone_free(ZQTCustomMallocZone, ptr);
        }
    }
};

// 工厂函数
template<typename T, typename... Args>
std::unique_ptr<T, CustomZoneDeleter<T>> make_unique_custom(Args&&... args) {
    CustomZoneAllocator<T> allocator;
    T* ptr = allocator.allocate(1);
    try {
        new (ptr) T(std::forward<Args>(args)...);
    } catch (...) {
        allocator.deallocate(ptr, 1);
        throw;
    }
    return std::unique_ptr<T, CustomZoneDeleter<T>>(ptr);
}
} // namespace ZQT

#endif /* ZQTMemoryTypes_hpp */ 

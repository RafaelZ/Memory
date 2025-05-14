#ifndef ZQTMemoryTypes_hpp
#define ZQTMemoryTypes_hpp

#include <memory>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <mach/mach.h>
#include <objc/runtime.h>
#include "ZQTCustomAllocator.hpp"

namespace ZQT {

// 使用自定义分配器的容器类型
template<typename T>
using CustomVector = std::vector<T, CustomZoneAllocator<T>>;


//template <class _Value, class _Hash = hash<_Value>, class _Pred = equal_to<_Value>, class _Alloc = allocator<_Value> >
template<typename V>
using CustomUnorderedSet = std::unordered_set<V,std::hash<V>,std::equal_to<V>,CustomZoneAllocator<V>>;

// 定义使用自定义分配器的字符串
using CustomString = std::basic_string<char, std::char_traits<char>, CustomZoneAllocator<char>>;


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

namespace std {
    template <>
    struct hash<__unsafe_unretained Class> {
        std::size_t operator()(__unsafe_unretained Class cls) const noexcept {
            // Class 本身是 objc_class*，std::hash<objc_class*> 是有效的。
            return std::hash<Class>()(cls);
        }
    };

    template <>
    struct equal_to<__unsafe_unretained Class> {
        bool operator()(__unsafe_unretained Class lhs, __unsafe_unretained Class rhs) const noexcept {
            // 指针的直接比较
            return lhs == rhs;
        }
    };
} // namespace std

#endif /* ZQTMemoryTypes_hpp */ 

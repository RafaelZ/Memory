//
//  ZQTCustomAllocator.h
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/14.
//

#ifndef ZQTCustomAllocator_h
#define ZQTCustomAllocator_h

#include "ZQTCustomMallocZone.h"
#include <memory>
#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <mach/mach.h>
#include <objc/runtime.h>

namespace ZQT {
// 自定义分配器
template <typename T>
class CustomZoneAllocator {
public:
    // 标准分配器类型定义
    using value_type = T;
    using pointer = T*;
    using const_pointer = const T*;
    using reference = T&;
    using const_reference = const T&;
    using size_type = std::size_t;
    using difference_type = std::ptrdiff_t;
    
    // 支持其他类型的rebind
    template <typename U>
    struct rebind {
        using other = CustomZoneAllocator<U>;
    };
    
    CustomZoneAllocator() = default;
    template<typename U>
    CustomZoneAllocator(const CustomZoneAllocator<U>&) {}
    
    pointer allocate(size_type n) {
        if (n == 0) return nullptr;
        if (n > std::numeric_limits<size_type>::max() / sizeof(T)) {
            throw std::bad_alloc();
        }
        void* ptr = malloc_zone_malloc(ZQTCustomMallocZone, n * sizeof(T));
        if (!ptr) throw std::bad_alloc();
        return static_cast<pointer>(ptr);
    }
    
    // 内存释放：调用malloc_zone_free
    void deallocate(pointer p, size_type) noexcept {
        if (p) malloc_zone_free(ZQTCustomMallocZone, p);
    }
    
    // 构造对象：使用placement new
    //    template <typename U, typename... Args>
    //    void construct(U* p, Args&&... args) {
    //        if constexpr (std::is_same_v<U, Class>) {
    //            // 使用折叠表达式确保参数包正确展开
    //            (void)std::initializer_list<int>{
    //                (static_cast<void>(*p = std::forward<Args>(args)), 0)...
    //            };
    //            static_assert(sizeof...(Args) == 1, "Class构造函数需要且仅需要一个参数");
    //        } else {
    //            // 普通类型：使用placement new
    //            ::new((void*)p) U(std::forward<Args>(args)...);
    //        }
    //    }
    //
    //    // 析构对象：调用析构函数
    //    template <typename U>
    //    void destroy(U* p) {
    //        if constexpr (std::is_same_v<U, Class>) {
    //            // Class类型无需析构
    //            (void)p; // 避免未使用参数警告
    //        } else {
    //            // 普通类型：调用析构函数
    //            p->~U();
    //        }
    //    }
    // 比较操作符：判断是否为同一个内存zone
    bool operator==(const CustomZoneAllocator& other) const noexcept {
        return true;
    }
    
    bool operator!=(const CustomZoneAllocator& other) const noexcept {
        return false;
    }
};
}

#endif /* ZQTCustomAllocator_h */

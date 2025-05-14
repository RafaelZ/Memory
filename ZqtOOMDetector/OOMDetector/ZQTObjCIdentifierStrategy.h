#ifndef ZQTObjCIdentifierStrategy_h
#define ZQTObjCIdentifierStrategy_h

#include "ZQTObjectIdentifierStrategy.h"
#include "ZQTMemoryTypes.hpp"
#include <objc/runtime.h>
#include "ZQTCppClassIdentifier.hpp"
namespace ZQT {
// 自定义哈希函数，用于 __unsafe_unretained Class
struct UnsafeUnretainedClassHash {
    std::size_t operator()(__unsafe_unretained Class cls) const {
        // Class 本身是 objc_class*，std::hash<objc_class*> 是有效的。
        // 我们只是告诉编译器如何处理带有 __unsafe_unretained 限定符的类型。
        return std::hash<Class>()(cls);
    }
};

// 自定义等于比较函数，用于 __unsafe_unretained Class
struct UnsafeUnretainedClassEqual {
    bool operator()(__unsafe_unretained Class lhs, __unsafe_unretained Class rhs) const {
        // 指针的直接比较
        return lhs == rhs;
    }
};

class ObjCIdentifierStrategy : public ObjectIdentifierStrategy {
public:
    ObjCIdentifierStrategy();
    ~ObjCIdentifierStrategy() override = default;
    
    // 禁用拷贝
    ObjCIdentifierStrategy(const ObjCIdentifierStrategy&) = delete;
    ObjCIdentifierStrategy& operator=(const ObjCIdentifierStrategy&) = delete;
    
    // 允许移动
    ObjCIdentifierStrategy(ObjCIdentifierStrategy&& other) noexcept;
    ObjCIdentifierStrategy& operator=(ObjCIdentifierStrategy&& other) noexcept;
    
    // 实现基类接口
    MemoryNode* identifyObjectAtAddress(vm_address_t address, vm_size_t size) override;
    
    // 更新类列表
    void updateClassList();
    
private:
    void initializeClassList();
    bool isTaggedPointer(const void* ptr) const;
    Class getClassForTaggedPointer(const void* ptr) const;
    bool isValidClass(Class cls) const;
    CppClassIdentifier cppIdentifier;
    CustomVector<__unsafe_unretained Class> allClasses;
//    yyheap_std_set<Class> classSet;
//    std::unordered_set<Class> classSet;
//    std::unordered_set<
//            __unsafe_unretained Class,
//            UnsafeUnretainedClassHash,
//            UnsafeUnretainedClassEqual,
//    CustomZoneAllocator
//        > classSet;
    CustomUnorderedSet<__unsafe_unretained Class> classSet;
};

} // namespace ZQT

#endif /* ZQTObjCIdentifierStrategy_h */ 
 

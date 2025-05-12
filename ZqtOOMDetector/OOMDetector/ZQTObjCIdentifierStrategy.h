#ifndef ZQTObjCIdentifierStrategy_h
#define ZQTObjCIdentifierStrategy_h

#include "ZQTObjectIdentifierStrategy.h"
#include "ZQTMemoryTypes.hpp"
#include <objc/runtime.h>

namespace ZQT {

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
    
private:
    void initializeClassList();
    bool isTaggedPointer(const void* ptr) const;
    Class getClassForTaggedPointer(const void* ptr) const;
    bool isValidClass(Class cls) const;
    
    CustomVector<Class> allClasses;
    CustomUnorderedSet<Class> classSet;
};

} // namespace ZQT

#endif /* ZQTObjCIdentifierStrategy_h */ 

#ifndef ZQTObjectIdentifierStrategy_h
#define ZQTObjectIdentifierStrategy_h

#include "MemoryNode.h"
#include <objc/runtime.h>

namespace ZQT {

class ObjectIdentifierStrategy {
public:
    virtual ~ObjectIdentifierStrategy() = default;
    virtual MemoryNode* identifyObjectAtAddress(vm_address_t address, vm_size_t size) = 0;
};

} // namespace ZQT

#endif /* ZQTObjectIdentifierStrategy_h */ 

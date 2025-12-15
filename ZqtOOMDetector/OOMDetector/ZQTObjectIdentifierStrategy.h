#ifndef ZQTObjectIdentifierStrategy_h
#define ZQTObjectIdentifierStrategy_h

#include "MemoryNode.h"
#include <objc/runtime.h>

namespace ZQT {

class ObjectIdentifierStrategy {
public:
    // MemoryNode 结构体现在从 "MemoryNode.h" 引入
    // // 用于存储内存节点信息的结构
    // struct MemoryNode {
    //     vm_address_t address = 0;
    //     vm_size_t size = 0; // 这个size由策略决定，通常是实例大小
    //     char name[128] = {0}; // 类名或其他标识
    //     char GKI[256] = {0}; // Global Key Identifier for the object type
    //     bool is_cpp = false;
    //     // 可以添加更多字段，如 retained/released 状态等
    // };
    
    virtual ~ObjectIdentifierStrategy() = default;
    
    // 纯虚函数，子类必须实现
    // allocatedSizeHint 参数是调用者（如HeapWalker）通过 malloc_size 等方式获取到的内存块分配大小
    // 策略返回的 MemoryNode->size 应该是它认为的对象实例大小
    virtual MemoryNode* identifyObjectAtAddress(vm_address_t address, vm_size_t allocatedSizeHint) = 0;
};

} // namespace ZQT

#endif /* ZQTObjectIdentifierStrategy_h */ 

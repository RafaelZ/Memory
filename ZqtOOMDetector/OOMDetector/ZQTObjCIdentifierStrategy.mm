 #include "ZQTObjCIdentifierStrategy.h"
#include <objc/runtime.h>
#include "ZQTCustomMallocZone.h"

// ARM64 架构的 Tagged Pointer 标记
#define OBJC_TAG_MASK (1ULL << 63)
#define OBJC_TAG_INDEX_SHIFT 60
#define OBJC_TAG_INDEX_MASK (0x7ULL << OBJC_TAG_INDEX_SHIFT)

namespace ZQT {

ObjCIdentifierStrategy::ObjCIdentifierStrategy() {
    initializeClassList();
}

ObjCIdentifierStrategy::ObjCIdentifierStrategy(ObjCIdentifierStrategy&& other) noexcept
    : allClasses(std::move(other.allClasses))
    , classSet(std::move(other.classSet))
{}

ObjCIdentifierStrategy& ObjCIdentifierStrategy::operator=(ObjCIdentifierStrategy&& other) noexcept {
    if (this != &other) {
        allClasses = std::move(other.allClasses);
        classSet = std::move(other.classSet);
    }
    return *this;
}

void ObjCIdentifierStrategy::initializeClassList() {
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    if (classes) {
        allClasses.reserve(count);
        for (unsigned int i = 0; i < count; i++) {
            allClasses.push_back(classes[i]);
            classSet.insert(classes[i]);
        }
        free(classes);
    }
}

bool ObjCIdentifierStrategy::isTaggedPointer(const void* ptr) const {
    return ((uintptr_t)ptr & OBJC_TAG_MASK) == OBJC_TAG_MASK;
}

Class ObjCIdentifierStrategy::getClassForTaggedPointer(const void* ptr) const {
    if (!isTaggedPointer(ptr)) {
        return nil;
    }
    
    uintptr_t value = (uintptr_t)ptr;
    unsigned tagIndex = (value & OBJC_TAG_INDEX_MASK) >> OBJC_TAG_INDEX_SHIFT;
    
    // 这里需要根据实际运行时行为来映射 tag 到具体的类
    // 由于这是启发式的，我们只处理一些常见的类型
    switch (tagIndex) {
        case 0: // NSNumber
            return objc_getClass("NSNumber");
        case 1: // NSString
            return objc_getClass("NSTaggedPointerString");
        default:
            return nil;
    }
}

bool ObjCIdentifierStrategy::isValidClass(Class cls) const {
    if (!cls) {
        return false;
    }
    
    return classSet.find(cls) != classSet.end();
}

MemoryNode* ObjCIdentifierStrategy::identifyObjectAtAddress(vm_address_t address, vm_size_t size) {
    void *ptr = (void *)address;
    
    // 检查是否是 Tagged Pointer
    if (isTaggedPointer(ptr)) {
        Class cls = getClassForTaggedPointer(ptr);
        if (cls) {
            auto node = make_unique_custom<MemoryNode>();
            node->address = address;
            node->size = size;
            node->type = MemoryNode::MemoryNodeType::PointerTagged;
//            node->name = NSStringFromClass(cls);
//            node->metadata = cls;
            return node.release();
        }
        return nullptr;
    }
    
    // 尝试获取对象的类
    id obj = (__bridge id)ptr;
    Class cls = object_getClass(obj);
    
    if (isValidClass(cls)) {
        auto node = make_unique_custom<MemoryNode>();
        node->address = address;
        node->size = size;
        node->type = MemoryNode::MemoryNodeType::Obj;
//        node->name = NSStringFromClass(cls);
//        node->metadata = cls;
        return node.release();
    }
    
    return nullptr;
}

} // namespace ZQT

#include "ZQTObjCIdentifierStrategy.h"
#include <objc/runtime.h>
#include "ZQTCustomMallocZone.h"
#include "ZQTVMStatistics.hpp"
// ARM64 架构的 Tagged Pointer 标记
#define OBJC_TAG_MASK (1ULL << 63)
#define OBJC_TAG_INDEX_SHIFT 60
#define OBJC_TAG_INDEX_MASK (0x7ULL << OBJC_TAG_INDEX_SHIFT)

#define k_enum_pure_block 1

#ifdef __arm64__
extern uint64_t objc_debug_isa_class_mask WEAK_IMPORT_ATTRIBUTE;
#endif

namespace ZQT {

typedef struct objc_structure_mock {
    Class isa;
} objc_structure_mock;

static ZQTObjcTag getTaggedPointerType(const void *ptr) {
    unsigned tagIndex = ((uintptr_t)ptr & OBJC_TAG_INDEX_MASK) >> OBJC_TAG_INDEX_SHIFT;
    return (ZQTObjcTag)tagIndex;
}

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

void ObjCIdentifierStrategy::updateClassList() {
    unsigned int count;
    allClasses.clear();
    classSet.clear();
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
    objc_structure_mock *rawMemoryObject = (objc_structure_mock *)address;
    void *ptr = (void *)((uint64_t)rawMemoryObject->isa);
    Class objectClass = NULL;
#ifdef __arm64__
    // http://www.sealiesoftware.com/blog/archive/2013/09/24/objc_explain_Non-pointer_isa.html
    objectClass = (__bridge Class)((void *)((uint64_t)rawMemoryObject->isa & objc_debug_isa_class_mask));
#else
    objectClass = rawMemoryObject->isa;
#endif
    auto node = make_unique_custom<MemoryNode>();
    node->address = address;
    node->size = size;

    if (isTaggedPointer(ptr)) {
        node->type = MemoryNode::MemoryNodeType::PointerTagged;
        node->name = zqt_objc_tag_to_string(getTaggedPointerType(ptr));
    } else {
        if (isValidClass(objectClass)) {
            const char * className = class_getName(objectClass);
            if (strcmp(className, "__NSCFType") == 0) {
                node->type = MemoryNode::MemoryNodeType::CFObj;
                CFTypeID cftypeid = CFGetTypeID((CFTypeRef)rawMemoryObject);
                try {
                    CFStringRef cfClassName = CFCopyTypeIDDescription(cftypeid);
                    node->name = (char *)cfClassName;
                } catch (...) {
                    node->name = "__NSCFUnknowType";
                    printf("catch exception");
                }
            } else {
                node->type = MemoryNode::MemoryNodeType::Obj;
            }
            node->objectClass = objectClass;
            
        }
//        else if (isCppClass) {
//          //TODO: 判断C++类型
//        }
        else {
            if (k_enum_pure_block) {
                node->type = MemoryNode::MemoryNodeType::Malloc;
                node->name = "malloc";
            }
        }
    }
    
    return node.release();
}

} // namespace ZQT

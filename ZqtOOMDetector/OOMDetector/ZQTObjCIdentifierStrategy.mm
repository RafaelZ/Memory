#include "ZQTObjCIdentifierStrategy.h"
#include <objc/runtime.h>
#include "ZQTCustomMallocZone.h"
#include "ZQTVMStatistics.hpp"
#include <set>
// ARM64 架构的 Tagged Pointer 标记
#define OBJC_TAG_MASK (1ULL << 63)
#define OBJC_TAG_INDEX_SHIFT 60
#define OBJC_TAG_INDEX_MASK (0x7ULL << OBJC_TAG_INDEX_SHIFT)

#define k_enum_pure_block 1

#ifdef __arm64__
extern uint64_t objc_debug_isa_class_mask WEAK_IMPORT_ATTRIBUTE;
#endif

namespace ZQT {

static std::set<std::string> excludeClassName = {
    //    "RBSAssertionIdentifier",
    //    "__NSCFString",
    //    "__NSCFData",
    //    "__NSCFType",
    "OS_xpc_connection",
    "__NSXPCInterfaceProxy__UIKeyboardArbitration",
    "RBSAssertionIdentifier",
    "RBSInheritance",
};

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
             Class classi = classes[i];
            if (classi) {
                const char *namei = class_getName(classi);
                std::string namestr = std::string(namei);
                if (excludeClassName.find(namestr) != excludeClassName.end()) {
                    continue;
                }

                allClasses.push_back(classi);
                classSet.insert(classi);
            }
        }
        free(classes);
    }
    cppIdentifier.scanForCppClasses();
}

void ObjCIdentifierStrategy::updateClassList() {
    unsigned int count;
    allClasses.clear();
    classSet.clear();
    Class *classes = objc_copyClassList(&count);
    if (classes) {
//        allClasses.reserve(count);
        for (unsigned int i = 0; i < count; i++) {
            if (classes[i]) {
//                allClasses.push_back(classes[i]);
                classSet.insert(classes[i]);
            }
        }
        free(classes);
    }
    printf("打印 classSet size:%ld",classSet.size());
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

MemoryNode* ObjCIdentifierStrategy::identifyObjectAtAddress(vm_address_t address, vm_size_t allocatedSizeHint) {
    // 优先检查 Tagged Pointer
    if (isTaggedPointer((const void*)address)) {
        Class cls = getClassForTaggedPointer((const void*)address);
        if (cls) {
            auto node = ZQT::make_unique_custom<MemoryNode>();
            node->address = address;
            node->size = sizeof(void*); // Tagged Pointer 大小固定为指针大小
            strlcpy(node->name, class_getName(cls), sizeof(node->name));
            // GKI 可以考虑用类名，或者更复杂的唯一标识
            snprintf(node->GKI, sizeof(node->GKI), "TaggedPointer:%s", node->name);
            return node.release();
        }
        return nullptr; // 无法识别的 Tagged Pointer
    }

    // 尝试读取 isa 指针
    if (address == 0 || !ZQT::Utils::isReadableAddress(address, sizeof(Class))) {
        return nullptr;
    }
    Class isa = *reinterpret_cast<Class *>(address);
    Class cls = ZQT::Utils::getClassFromIsa(isa, false /* allowSwift */); // 假设有一个工具函数处理 isa

    if (cls && isValidClass(cls)) {
        auto node = ZQT::make_unique_custom<MemoryNode>();
        node->address = address;
        node->size = class_getInstanceSize(cls); // 设置为Objective-C对象的实例大小
        strlcpy(node->name, class_getName(cls), sizeof(node->name));
        snprintf(node->GKI, sizeof(node->GKI), "ObjC:%s", node->name);
        node->is_cpp = false;
        return node.release();
    } else {
        // 如果不是有效的 Objective-C 对象，尝试 C++ 对象识别
        CustomString cppClassName;
        if (cppIdentifier.isInstanceOfKnownCppClass(reinterpret_cast<const void*>(address), cppClassName)) {
            auto node = ZQT::make_unique_custom<MemoryNode>();
            node->address = address;
            // 对于C++对象，其实例大小无法通过ZQTCppClassIdentifier直接获取。
            // allocatedSizeHint 在这里可能更有用，但策略本身不应该依赖它来决定实例大小。
            // HeapWalker将使用allocatedSizeHint来跳跃。
            // 如果确实需要估算C++对象大小，可能需要更复杂的启发式或假设。
            // 目前，如果无法从类型信息中得到，可以暂时设为0或一个标记值。
            // 或者，我们可以假设如果allocatedSizeHint有效，那么它就是对象的大小，但这不总是准确。
            // 为了让HeapWalker正确跳过，这里暂时不设置size，或者设置一个基于类型的估算值（如果可能）。
            // 更好的做法是让HeapWalker直接使用malloc_size。
            // 这里我们返回一个节点，但其size字段对于C++对象可能不太准确或为0.
            node->size = 0; //  C++ 对象大小未知，由 HeapWalker 根据 allocatedSizeHint 处理跳跃
            if (!cppClassName.empty()) {
                strlcpy(node->name, cppClassName.c_str(), sizeof(node->name));
            } else {
                strlcpy(node->name, "UnknownCppClass", sizeof(node->name));
            }
            snprintf(node->GKI, sizeof(node->GKI), "Cpp:%s", node->name);
            node->is_cpp = true;
            return node.release();
        }
    }
    
    return nullptr;
}

} // namespace ZQT

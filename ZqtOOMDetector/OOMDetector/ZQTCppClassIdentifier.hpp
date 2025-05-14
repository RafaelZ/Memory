//
//  ZQTCppClassIdentifier.hpp
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/14.
//

#ifndef ZQTCppClassIdentifier_hpp
#define ZQTCppClassIdentifier_hpp

#include <cstdint> // 用于 uintptr_t
#include <mach-o/dyld.h> // 用于 _dyld_* 函数
//#include <unordered_set> // 用于 processedTypeInfoAddresses
#include "ZQTMemoryTypes.hpp"
#include "CppClassInfo.h"

// 来自 <typeinfo> 和 <cxxabi.h> 中类型的正向声明
// 如果接口并非严格需要，这样可以避免在公共头文件中包含这些较重的头文件。
// .cpp 文件将会包含它们。
//namespace __cxxabiv1 {
//class __class_type_info; // RTTI 对象的常见基类
//}
// 或者，更通用地：
// class type_info; // 来自 <typeinfo>

namespace ZQT {

class CppClassIdentifier {
public:
    CppClassIdentifier();

    // 扫描主可执行映像以查找 C++ 类信息 (RTTI, vtables)
    // 这个函数通常应该在启动时调用一次。
    void scanForCppClasses();

    // 检查给定的内存地址（假定指向一个对象实例）的 vptr 是否
    // 与已知的 C++ 类 vtable 之一匹配。
    // 如果匹配，outClassName 将被填充为解码后的类名。
    bool isInstanceOfKnownCppClass(const void* instanceAddress, CustomString& outClassName) const;

    // 返回已识别的 C++ 类列表
    const CustomVector<CppClassInfo>& getKnownCppClasses() const;

private:
    CustomVector<CppClassInfo> knownCppClasses_;   // 存储已发现的 C++ 类信息
    CustomVector<SectionRange> constSections_;     // 存储 __TEXT,__const 和 __DATA,__const 段的范围
    CustomVector<SectionRange> cstringSections_;   // 存储 __TEXT,__cstring 段的范围
    CustomVector<SectionRange> textSections_;      // 存储 __TEXT,__text 段的范围 (用于虚函数健全性检查，可选)
    CustomUnorderedSet<uintptr_t> processedTypeInfoAddresses_; // 用于避免重复处理 type_info 地址

    uintptr_t imageBaseAddress_ = 0; // 主映像的基地址
    intptr_t imageSlide_ = 0;        // 主映像的ASLR偏移量 (可以是负数)

    // 辅助函数：获取映像和段信息
    bool initializeImageInfo();
    
    // 辅助函数：检查指针是否有效且位于指定段内
    bool isValidPointerInSection(uintptr_t address, const CustomVector<SectionRange>& sections) const;
    // 辅助函数：检查指针是否指向一个C字符串（特别是mangled name）
    bool isPointerToCString(uintptr_t address) const;

    // 辅助函数：解码 C++ 名称
    CustomString demangle(const char* mangledName) const;
};

} // namespace ZQT

#endif /* ZQTCppClassIdentifier_hpp */

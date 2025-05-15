//
//  ZQTCppClassIdentifier.hpp
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/14.
//

#ifndef ZQTCppClassIdentifier_hpp
#define ZQTCppClassIdentifier_hpp

#include <cstdint>        // 用于 uintptr_t
#include <mach-o/dyld.h>  // 用于 _dyld_* 函数
#include "ZQTMemoryTypes.hpp" // 应该定义 CustomVector, CustomString, CustomUnorderedSet, SectionRange, make_unique_custom
#include "CppClassInfo.h"     // 应该定义 CppClassInfo

// 来自 <typeinfo> 和 <cxxabi.h> 中类型的正向声明
// 如果接口并非严格需要，这样可以避免在公共头文件中包含这些较重的头文件。
// .cpp 文件将会包含它们。
// namespace __cxxabiv1 {
// class __class_type_info; // RTTI 对象的常见基类
// }
// 或者，更通用地：
// class type_info; // 来自 <typeinfo>

namespace ZQT {

class CppClassIdentifier {
public:
    CppClassIdentifier();

    // 扫描加载的镜像以查找 C++ 类信息 (RTTI, vtables)。
    // 这个函数通常应该在启动时调用一次。
    void scanForCppClasses();

    // 检查给定的内存地址（假定指向一个对象实例）的 vptr 是否
    // 与已知的 C++ 类 vtable 之一匹配。
    // 如果匹配，outClassName 将被填充为解码后的类名。
    bool isInstanceOfKnownCppClass(const void* instanceAddress, CustomString& outClassName) const;

    // 返回已识别的 C++ 类列表。
    const CustomVector<CppClassInfo>& getKnownCppClasses() const;

private:
    CustomVector<CppClassInfo> knownCppClasses_;          // 存储已发现的 C++ 类信息
    CustomVector<SectionRange> appConstSections_;         // 存储 应用及非系统动态库的 __TEXT,__const 和 __DATA_CONST,__const 等段的范围
    CustomVector<SectionRange> appCStringSections_;       // 存储 应用及非系统动态库的 __TEXT,__cstring 段的范围
    CustomVector<SectionRange> appTextSections_;          // 存储 应用及非系统动态库的 __TEXT,__text 段的范围 (可选, 用于虚函数健全性检查)
    CustomVector<SectionRange> systemRttiVTableSections_; // 存储 系统C++运行时库(例如 libc++)中已知包含RTTI vtable的常量段

    CustomUnorderedSet<uintptr_t> processedTypeInfoAddresses_; // 用于避免重复处理 type_info 地址

    // 辅助函数：获取镜像和段信息。
    // 成功返回 true。
    bool initializeImageInfo();
    
    // 辅助函数：检查指针是否有效且位于指定段集合内。
    bool isValidPointerInSection(uintptr_t address, const CustomVector<SectionRange>& sections) const;
    // 辅助函数：检查指针是否指向一个C字符串 (特指 mangled name)。
    // 会检查 stringSections (通常是 __cstring) 和 constSectionsToAlsoCheck (通常是 __const)
    bool isPointerToCString(uintptr_t address, const CustomVector<SectionRange>& stringSections, const CustomVector<SectionRange>& constSectionsToAlsoCheck) const;

    // 辅助函数：解码 C++ 名称。
    CustomString demangle(const char* mangledName) const;

    // 运行时检查：查看一个示例 RTTI vtable 是否落入收集到的系统段中。
    // 用于调试 initializeImageInfo。
    void verifySystemRttiVTableSections() const;
};

} // namespace ZQT

#endif /* ZQTCppClassIdentifier_hpp */

//
//  ZQTCppClassIdentifier.cpp
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/14.
//

#include "ZQTCppClassIdentifier.hpp"
#include <iostream>          // 用于日志/调试，可以移除
#include <mach-o/loader.h>   // 用于 Mach-O 结构定义 (SEG_TEXT, SECT_TEXT 等宏定义于此)
#include <dlfcn.h>           // 用于 dladdr (获取映像信息的替代方法，此处主程序未使用)
#include <cxxabi.h>          // 用于 abi::__cxa_demangle
#include <typeinfo>          // 用于 std::type_info 和相关的 RTTI 结构
#include <cstring>           // 用于 strncmp, strlen, strnlen
#include <unordered_set>     // 用于 processedTypeInfoAddresses (确保在.h中也包含如果它被用作私有成员类型)


// Itanium C++ ABI RTTI type info 结构 (为我们的目的简化)
// 这些通常是 <cxxabi.h> 或编译器内部的一部分。
// 我们对派生自 std::type_info 的类感兴趣，例如：
// namespace __cxxabiv1 {
// class __class_type_info : public std::type_info { ... };
// class __si_class_type_info : public __class_type_info { public: const __class_type_info *__base_type; ... };
// class __vmi_class_type_info : public __class_type_info { ... };
// }
// 为了我们的目的，我们将依赖 `name()` 方法 (或者更确切地说是内部的 `_M_name` 字段)
// 以及 type_info 对象本身的 vptr。

// std::type_info 或派生 RTTI 对象 (如 abi::__si_class_type_info) 的典型布局：
// struct RTTIObjectLayout {
//     void* vptr_for_rtti_type; // 指向 std::type_info 或派生类 vtable 的指针
//     const char* name_ptr;     // 指向 mangled name 字符串的指针
//     // ... 其他派生类型的字段，如 __si_class_type_info 的 base_type
// };


namespace ZQT {

CppClassIdentifier::CppClassIdentifier() {
    // 构造函数可以选择性地调用 initializeImageInfo 和 scanForCppClasses，
    // 或者它们可以由用户手动调用。
    // 为简单起见，我们要求手动调用 scanForCppClasses。
}

bool CppClassIdentifier::initializeImageInfo() {
    if (imageBaseAddress_ != 0) return true; // 已经初始化过了

    // 获取主可执行文件的头部 (映像索引为0)
    const mach_header* header = _dyld_get_image_header(0);
    if (!header) {
        // std::cerr << "CppClassIdentifier: 未能获取主映像头部。" << std::endl;
        return false;
    }

    // 确保是64位头部，因为iOS是64位的
    if (header->magic != MH_MAGIC_64 && header->magic != MH_CIGAM_64) {
        // std::cerr << "CppClassIdentifier: 不是64位 Mach-O 头部。" << std::endl;
        return false;
    }
    const mach_header_64* header64 = (const mach_header_64*)header;

    imageBaseAddress_ = (uintptr_t)header64;
    imageSlide_ = _dyld_get_image_vmaddr_slide(0);

    uintptr_t current_cmd_address = imageBaseAddress_ + sizeof(mach_header_64);

    // 定义常量字符串用于比较，以避免宏未定义的问题
    const std::string SECT_CONST_STR = "__const";
    const std::string SECT_CSTRING_STR = "__cstring";
    const std::string SECT_TEXT_STR = "__text";
    // SEG_TEXT 和 SEG_DATA 宏通常是可用的，如果它们也出问题，可以类似地替换
    // const std::string SEG_TEXT_STR = "__TEXT";
    // const std::string SEG_DATA_STR = "__DATA";


    for (uint32_t i = 0; i < header64->ncmds; ++i) {
        const load_command* lc = (const load_command*)current_cmd_address;

        if (lc->cmd == LC_SEGMENT_64) {
            const segment_command_64* seg_cmd = (const segment_command_64*)lc;
            // std::cout << "Segment: " << seg_cmd->segname << std::endl; // 段名

            uintptr_t section_ptr = (uintptr_t)seg_cmd + sizeof(segment_command_64);
            for (uint32_t j = 0; j < seg_cmd->nsects; ++j) {
                const section_64* sect = (const section_64*)section_ptr;
                uintptr_t section_start_addr = sect->addr + imageSlide_; // 加上ASLR偏移
                uintptr_t section_end_addr = section_start_addr + sect->size;

                std::string segName(seg_cmd->segname, strnlen(seg_cmd->segname, 16));
                std::string sectName(sect->sectname, strnlen(sect->sectname, 16));
                
                // std::cout << "  Section: " << segName << "," << sectName
                //           << " Addr: 0x" << std::hex << section_start_addr
                //           << " Size: 0x" << sect->size << std::dec << std::endl; // Section信息

                // 使用字符串字面量进行比较，而不是依赖可能未定义的宏
                if ((segName == SEG_TEXT && sectName == SECT_CONST_STR) || // TEXT段中的常量
                    (segName == SEG_DATA && sectName == SECT_CONST_STR)) { // DATA段中的常量 (例如 __DATA_CONST)
                    auto section = make_unique_custom<SectionRange>(section_start_addr, section_end_addr, segName.c_str(), sectName.c_str());
                    constSections_.push_back(*section);
                } else if (segName == SEG_TEXT && sectName == SECT_CSTRING_STR) { // C字符串
                    auto section = make_unique_custom<SectionRange>(section_start_addr, section_end_addr, segName.c_str(), sectName.c_str());
                    cstringSections_.push_back(*section);
                } else if (segName == SEG_TEXT && sectName == SECT_TEXT_STR) { // 代码段
                    auto section = make_unique_custom<SectionRange>(section_start_addr, section_end_addr, segName.c_str(), sectName.c_str());
                    textSections_.push_back(*section);
                }
                section_ptr += sizeof(section_64);
            }
        }
        current_cmd_address += lc->cmdsize;
    }
    return !constSections_.empty(); // 如果至少找到一个常量段，则认为初始化成功
}

bool CppClassIdentifier::isValidPointerInSection(uintptr_t address, const CustomVector<SectionRange>& sections) const {
    if (address == 0) return false; // 空指针无效
    for (const auto& range : sections) {
        if (range.contains(address)) {
            return true;
        }
    }
    return false;
}

bool CppClassIdentifier::isPointerToCString(uintptr_t address) const {
    // 检查指针是否位于已知的C字符串区或常量区
    if (!isValidPointerInSection(address, cstringSections_) && !isValidPointerInSection(address, constSections_)) {
         // 有时字符串字面量也可能在 __TEXT,__const 中
        return false;
    }
    
    const char* cstr = (const char*)address;
    // 检查 C++ mangled name 的 _Z 前缀
    if (strncmp(cstr, "_Z", 2) != 0) {
        // 这可能是C类型的type_info (例如 `typeid(int).name()`)，它没有_Z前缀。
        // 或者可能是其他字符串。对于C++类，我们期望是mangled name。
        // 然而，内置类型或非类类型的type_info是存在的。
        // 我们主要对用户定义的、会被mangled的C++类感兴趣。
        // 目前允许非_Z名称，如果它们不是C++ mangled name，demangle会失败。
    }

    // 检查合理的字符串长度，避免读取过多未知内存
    // 这是一个简单的检查；真正鲁棒的检查更复杂。
    size_t len = 0;
    uintptr_t current_char_addr = address;
    while (len < 1024) { // 合理的mangled name最大长度
        // 确保我们仍在已知的字符串或常量段内读取
        if (!isValidPointerInSection(current_char_addr, cstringSections_) && !isValidPointerInSection(current_char_addr, constSections_)) {
            return false; // 字符串超出了已知段范围
        }
        if (*(const char*)current_char_addr == '\0') return true; // 找到空终止符
        current_char_addr++;
        len++;
    }
    return false; // 在合理长度内未找到空终止符或超出了边界
}


CustomString CppClassIdentifier::demangle(const char* mangledName) const {
    if (!mangledName) return "";
    int status = 0;
    // 使用abi::__cxa_demangle进行解码
    char* demangled_c_str = abi::__cxa_demangle(mangledName, nullptr, nullptr, &status);
    if (status == 0 && demangled_c_str) {
        CustomString demangled_name(demangled_c_str);
        free(demangled_c_str); // 释放 __cxa_demangle 分配的内存
        return demangled_name;
    }
    return ""; // 如果解码失败，返回空字符串或mangledName
}

void CppClassIdentifier::scanForCppClasses() {
    if (!initializeImageInfo()) {
        // std::cerr << "CppClassIdentifier: 未能初始化映像信息。无法扫描。" << std::endl;
        return;
    }

    knownCppClasses_.clear();
    // processedTypeInfoAddresses_ 在.h中声明了，这里不需要重复声明
    processedTypeInfoAddresses_.clear(); // 确保每次扫描都是全新的

    // 遍历 __TEXT,__const 和 __DATA,__const 段
    // 这些段通常包含 RTTI (type_info 对象) 和 vtable。
    // vtable 的结构通常是：
    //   vtable[-2]: offset_to_top
    //   vtable[-1]: type_info* (指向该类的 type_info 对象)
    //   vtable[0]:  ptr to first virtual function
    //   vtable[1]:  ptr to second virtual function
    //   ...
    // 我们将扫描这些段中看起来像 `type_info*` 的指针。
    for (const auto& section : constSections_) {
        // 以指针大小为步长遍历段内地址
        // 包含 type_info 指针的 vtable 槽应该是指针字节对齐的。
        for (uintptr_t current_addr = section.start;
             current_addr < section.end && current_addr <= section.end - sizeof(uintptr_t); // 防止current_addr越界以及后续*(uintptr_t*)current_addr越界
             current_addr += sizeof(uintptr_t)) {
            
            // `current_addr` 是一个潜在的 `vtable[-1]` 的位置，它存储了 `type_info*`。
            uintptr_t potential_type_info_ptr_value = 0;
            // 安全读取指针值
            if (current_addr + sizeof(uintptr_t) <= section.end) { // 确保不会读取越界
                 potential_type_info_ptr_value = *(uintptr_t*)current_addr;
            } else {
                continue; // 无法安全读取，跳过
            }


            // 验证这个值是否是指向 type_info 对象的指针。
            // 1. type_info 对象本身应该位于一个常量段中。
            if (!isValidPointerInSection(potential_type_info_ptr_value, constSections_)) {
                continue;
            }

            // 2. type_info 对象 (位于 `potential_type_info_ptr_value`) 的第一个成员应该是其 vptr，
            //    第二个成员应该是指向其 mangled name 的指针 (参考 RTTIObjectLayout)。
            //    令 `addr_ti = potential_type_info_ptr_value`。
            uintptr_t addr_ti = potential_type_info_ptr_value;

            // 检查是否已经处理过这个 type_info 地址
            if (processedTypeInfoAddresses_.count(addr_ti)) {
                continue;
            }

            // type_info 对象内部 vptr 的地址：
            uintptr_t vptr_in_ti_obj_addr = addr_ti;
            // type_info 对象内部 name_ptr 的地址：
            uintptr_t name_ptr_in_ti_obj_addr = addr_ti + sizeof(void*);

            // 确保读取 vptr 和 name_ptr 不会越界
            bool can_read_vptr_in_ti = false;
            for(const auto& s : constSections_) { // type_info 对象应该在常量段内
                if(s.contains(vptr_in_ti_obj_addr) && vptr_in_ti_obj_addr + sizeof(void*) <= s.end) {
                    can_read_vptr_in_ti = true;
                    break;
                }
            }
            bool can_read_name_ptr_in_ti = false;
            for(const auto& s : constSections_) {
                 if(s.contains(name_ptr_in_ti_obj_addr) && name_ptr_in_ti_obj_addr + sizeof(void*) <= s.end) {
                    can_read_name_ptr_in_ti = true;
                    break;
                }
            }

            if (!can_read_vptr_in_ti || !can_read_name_ptr_in_ti) {
                continue;
            }
            
            uintptr_t vptr_value_in_ti = *(uintptr_t*)vptr_in_ti_obj_addr; // type_info 对象的 vptr 指向的值 (即 type_info 的 vtable 地址)
            const char* mangled_name_ptr = *(const char**)name_ptr_in_ti_obj_addr; // type_info 对象中的 name_ptr 指向的值 (即 mangled name 字符串地址)

            // 进一步验证：
            // - type_info 对象的 vptr 指向的 vtable (vptr_value_in_ti) 也应在常量段
            // - type_info 对象中的 name_ptr (mangled_name_ptr) 指向的字符串应在 cstring 或 const 段
            if (!isValidPointerInSection(vptr_value_in_ti, constSections_) ||
                !isPointerToCString((uintptr_t)mangled_name_ptr)) {
                continue;
            }
            
            // 尝试解码名称
            CustomString demangled_name_str = demangle(mangled_name_ptr);

            if (!demangled_name_str.empty()) {
                // 如果解码成功，我们很可能找到了一个 C++ type_info 对象。
                // 地址 `current_addr` 是存储这个 `type_info_ptr_value` 的地方。
                // 这意味着 `current_addr` 对应于 `vtable[-1]`。
                // 所以，第一个虚函数的地址是 `current_addr + sizeof(void*)`。
                uintptr_t vtable_first_func_addr = current_addr + sizeof(void*);

                // 健全性检查：第一个虚函数应该指向 __TEXT,__text 段中的代码
                // 需要确保读取 vtable_first_func_addr 处的值是安全的
                bool can_read_vtable_first_func_target = false;
                for(const auto& s : constSections_) { // vtable 本身在常量段
                    if(s.contains(vtable_first_func_addr) && vtable_first_func_addr + sizeof(void*) <= s.end) {
                        can_read_vtable_first_func_target = true;
                        break;
                    }
                }

                if (can_read_vtable_first_func_target) {
                    uintptr_t first_func_target_addr = *(uintptr_t*)vtable_first_func_addr;
                    if (!isValidPointerInSection(first_func_target_addr, textSections_)) {
                        // 这个检查可能过于严格或依赖ABI。
                        // 例如，第一个条目可能是其他东西或纯虚函数。
                        // 但这是一个常见的启发式方法。
                        // std::cout << "VTable 第一个函数对于 " << demangled_name_str << " @ 0x" << std::hex << vtable_first_func_addr
                        //           << " (值为 0x" << first_func_target_addr << ") 不在 __TEXT,__text 段。跳过。" << std::dec << std::endl;
                        // continue; // 暂时不跳过，因为纯虚函数的vtable条目可能不指向text段
                    }
                } else {
                    // 无法安全读取第一个虚函数的地址，可能vtable结构不符合预期
                    // std::cout << "无法安全读取 " << demangled_name_str << " 的 vtable 第一个函数目标地址 @ 0x" << std::hex << vtable_first_func_addr << std::dec << std::endl;
                    // continue;
                }
                
                // std::cout << "找到 C++ 类: " << demangled_name_str
                //           << " (RTTI @ 0x" << std::hex << addr_ti
                //           << ", VTable 第一个函数 @ 0x" << vtable_first_func_addr
                //           << std::dec << ")" << std::endl;

                auto classInfo = make_unique_custom<CppClassInfo>(addr_ti, vtable_first_func_addr, mangled_name_ptr, demangled_name_str.c_str());
                knownCppClasses_.push_back(*classInfo);
                processedTypeInfoAddresses_.insert(addr_ti);
            }
        }
    }
     // std::cout << "扫描完成。找到 " << knownCppClasses_.size() << " 个潜在的 C++ 类。" << std::endl;
}


bool CppClassIdentifier::isInstanceOfKnownCppClass(const void* instanceAddress, CustomString& outClassName) const {
    if (!instanceAddress) {
        return false;
    }

    // 多态 C++ 对象实例的第一个指针是 vptr。
    // 这个 vptr 指向 vtable，具体来说是 vtable 中第一个虚函数的地址。
    // 需要确保读取 instanceAddress 是安全的。这通常由调用者保证，
    // 但在工具中，可能需要额外的检查（例如，地址是否可读）。
    // 此处假设 instanceAddress 是一个有效的、至少包含一个指针大小的可读内存。
    uintptr_t instance_vptr_value = *(uintptr_t*)instanceAddress;

    for (const auto& class_info : knownCppClasses_) {
        if (instance_vptr_value == class_info.vtableFirstFuncAddress) {
            outClassName = class_info.demangledName;
            return true;
        }
    }

    return false;
}

const CustomVector<CppClassInfo>& CppClassIdentifier::getKnownCppClasses() const {
    return knownCppClasses_;
}

} // namespace ZQT

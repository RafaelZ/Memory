//
//  ZQTCppClassIdentifier.cpp
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/14.
//

#include "ZQTCppClassIdentifier.hpp"
#include <iostream>          // 用于 std::cout, std::cerr (可以替换为自定义日志)
#include <mach-o/loader.h>   // 用于 Mach-O 结构定义
#include <dlfcn.h>           // 用于 dladdr
#include <cxxabi.h>          // 用于 abi::__cxa_demangle
#include <typeinfo>          // 用于 std::type_info 和相关的 RTTI 结构 (在 verifySystemRttiVTableSections 中使用)
#include <cstring>           // 用于 strncmp, strlen, strnlen, strstr

// 将 SEGMENT 和 SECTION 名称定义为 const char* 或 std::string 以进行稳健比较
// 标准段名 (Segment Names)
const char* SEG_TEXT_STR_DEF = "__TEXT";
const char* SEG_DATA_STR_DEF = "__DATA";
const char* SEG_DATA_CONST_STR_DEF = "__DATA_CONST"; // 常量数据常用段名

const char* SEG_AUTH_CONST_STR_DEF = "__AUTH_CONST";

// 标准节名 (Section Names)
const char* SECT_CONST_STR_DEF = "__const";
const char* SECT_CSTRING_STR_DEF = "__cstring";
const char* SECT_TEXT_STR_DEF = "__text";

//#define ZQT_LOG
#ifdef ZQT_LOG
#define ZQTOUT std::cout
#else
struct NullBuffer : public std::streambuf {
    int overflow(int c) override { return c; }
};

struct NullStream : public std::ostream {
    NullStream() : std::ostream(new NullBuffer()) {}
    ~NullStream() override { delete rdbuf(); }
};

static NullStream nullStream;
#define ZQTOUT nullStream
#endif

namespace ZQT {

CppClassIdentifier::CppClassIdentifier() {
    // 构造函数可以有选择地调用 initializeImageInfo 和 scanForCppClasses，
    // 或者它们可以由用户手动调用。
    // 为简单起见，我们要求手动调用 scanForCppClasses。
}

bool CppClassIdentifier::initializeImageInfo() {
    appConstSections_.clear();      // 清空应用常量段列表
    appCStringSections_.clear();    // 清空应用C字符串段列表
    appTextSections_.clear();       // 清空应用代码段列表
    systemRttiVTableSections_.clear(); // 清空系统RTTI vtable段列表
    
    uint32_t imageCount = _dyld_image_count();
    ZQTOUT << "[信息] 动态加载的镜像总数: " << imageCount << std::endl;
    
    bool foundAnySegmentsForApp = false; // 标记是否为应用找到了任何相关段

    for (uint32_t index = 0; index < imageCount; ++index) {
        const char* imageName = _dyld_get_image_name(index);
        const mach_header* header = _dyld_get_image_header(index);

        if (!header || !imageName) {
            continue;
        }

        // 我们主要关心arm64镜像
        // 如果需要扫描其他架构，请调整此逻辑。
        if (header->magic != MH_MAGIC_64 && header->magic != MH_CIGAM_64) {
            // ZQTOUT << "[调试] 跳过非64位镜像: " << imageName << std::endl;
            continue;
        }

        // 简单判断是否可能是 C++ 运行时库 (例如 libc++.dylib)
        // 这个判断需要根据目标环境进行调整以保证稳健性。
        bool isLikelyCppRuntime = (strstr(imageName, "libc++") != nullptr);
        // 更稳健的方法: 检查 LC_LOAD_DYLIB 条目，匹配已知的C++运行时库名称。


        const mach_header_64* header64 = (const mach_header_64*)header;
        intptr_t imageSlide = _dyld_get_image_vmaddr_slide(index); // 使用局部变量更清晰

        if (isLikelyCppRuntime) {
             ZQTOUT << "[初始化信息] 识别到潜在的C++运行时: " << imageName << " (slide: 0x" << std::hex << imageSlide << std::dec << ")" << std::endl;
        }

        uintptr_t current_cmd_address = (uintptr_t)header64 + sizeof(mach_header_64);
        for (uint32_t i = 0; i < header64->ncmds; ++i) {
            const load_command* lc = (const load_command*)current_cmd_address;

            if (lc->cmd == LC_SEGMENT_64) {
                const segment_command_64* seg_cmd = (const segment_command_64*)lc;
                std::string segName(seg_cmd->segname, strnlen(seg_cmd->segname, 16));
                
                uintptr_t section_ptr = (uintptr_t)seg_cmd + sizeof(segment_command_64);
                for (uint32_t j = 0; j < seg_cmd->nsects; ++j) {
                    const section_64* sect = (const section_64*)section_ptr;
                    std::string sectName(sect->sectname, strnlen(sect->sectname, 16));
                    
                    uintptr_t section_start_addr = sect->addr + imageSlide;
                    uintptr_t section_end_addr = section_start_addr + sect->size;
                    
                    if (isLikelyCppRuntime) {
                        // 临时诊断：添加所有只读段
                        if ((segName == SEG_AUTH_CONST_STR_DEF && sectName == SECT_CONST_STR_DEF) ||
                            (segName == SEG_DATA_CONST_STR_DEF && sectName == SECT_CONST_STR_DEF) ||
                            (segName == SEG_TEXT_STR_DEF && sectName == SECT_CONST_STR_DEF)/* 如果知道其他候选段名，可添加 */) { // 是只读段且有大小
                            auto sectionRange = make_unique_custom<SectionRange>(section_start_addr, section_end_addr, seg_cmd->segname, sect->sectname);
                            systemRttiVTableSections_.push_back(*sectionRange);
                            ZQTOUT << "[INIT_INFO_VERBOSE_SYS] Image: " << imageName << " Added to systemRttiVTableSections (ALL READ-ONLY): "
                                      << segName << "," << sectName << " Addr: 0x" << std::hex << section_start_addr
                                      << " Size: 0x" << sect->size << std::dec << std::endl;
                        }

                    } else if (header->filetype == MH_EXECUTE){
                        // 对于应用和其他动态库，填充主要的扫描列表
                        if ((segName == SEG_TEXT_STR_DEF && sectName == SECT_CONST_STR_DEF) ||
                            (segName == SEG_DATA_STR_DEF && sectName == SECT_CONST_STR_DEF) || // 较早的系统可能使用 __DATA,__const
                            (segName == SEG_DATA_CONST_STR_DEF && sectName == SECT_CONST_STR_DEF)) {
                            auto sectionRange = make_unique_custom<SectionRange>(section_start_addr, section_end_addr, seg_cmd->segname, sect->sectname);
                            appConstSections_.push_back(*sectionRange);
                            foundAnySegmentsForApp = true; // 标记为主应用或其直接依赖找到了常量段
                        } else if (segName == SEG_TEXT_STR_DEF && sectName == SECT_CSTRING_STR_DEF) {
                            auto sectionRange = make_unique_custom<SectionRange>(section_start_addr, section_end_addr, seg_cmd->segname, sect->sectname);
                            appCStringSections_.push_back(*sectionRange);
                        } else if (segName == SEG_TEXT_STR_DEF && sectName == SECT_TEXT_STR_DEF) {
                            auto sectionRange = make_unique_custom<SectionRange>(section_start_addr, section_end_addr, seg_cmd->segname, sect->sectname);
                            appTextSections_.push_back(*sectionRange);
                        }
                    }
                    section_ptr += sizeof(section_64);
                }
            }
            current_cmd_address += lc->cmdsize;
        }
    }

    ZQTOUT << "[信息] 应用常量段数量: " << appConstSections_.size() << std::endl;
    ZQTOUT << "[信息] 应用C字符串段数量: " << appCStringSections_.size() << std::endl;
    ZQTOUT << "[信息] 应用代码段数量: " << appTextSections_.size() << std::endl;
    ZQTOUT << "[信息] 系统RTTI vtable候选段数量: " << systemRttiVTableSections_.size() << std::endl;

    // 运行时验证 systemRttiVTableSections_ 的收集情况 (用于调试)
//     verifySystemRttiVTableSections();

    return foundAnySegmentsForApp || !systemRttiVTableSections_.empty(); // 如果为应用找到了段或为系统库找到了RTTI vtable段，则认为初始化有意义
}

// 用于调试 initializeImageInfo 是否正确收集了系统RTTI vtable段
void CppClassIdentifier::verifySystemRttiVTableSections() const {
    if (systemRttiVTableSections_.empty()) {
        ZQTOUT << "[系统段验证] 未收集到任何系统RTTI vtable候选段。" << std::endl;
        return;
    }

    const std::type_info& ti_sample = typeid(int); // 使用一个简单的已知类型
    // 我们需要的是 type_info 对象的 vptr, 它指向 std::type_info (或其派生类) 的 vtable。
    void* p_rtti_vtable_sample = (void*)(*(uintptr_t*)(&ti_sample)); // 获取 vptr 的值

    ZQTOUT << "[系统段验证] typeid(int) 的运行时vptr (指向RTTI vtable): 0x"
              << std::hex << (uintptr_t)p_rtti_vtable_sample << std::dec << std::endl;

    bool found_in_system_sections = false;
    for (const auto& range : systemRttiVTableSections_) {
        if (range.contains((uintptr_t)p_rtti_vtable_sample)) {
            found_in_system_sections = true;
            ZQTOUT << "[系统段验证]   成功: 示例RTTI vtable指针在以下系统段中找到: 段名="
                      << range.segmentName << ", 节名="
                      << range.sectionName
                      << " 范围=[0x" << std::hex << range.start << ", 0x" << range.end << "]"
                      << std::dec << std::endl;
            break;
        }
    }
    if (!found_in_system_sections) {
        ZQTOUT << "[系统段验证]   错误: 示例RTTI vtable指针 未在任何已记录的 systemRttiVTableSections_ 中找到。" << std::endl;
        ZQTOUT << "[系统段验证]   已记录的 systemRttiVTableSections_ 列表:" << std::endl;
        for (const auto& range : systemRttiVTableSections_) {
             ZQTOUT << "    段名=" << range.segmentName << ", 节名="
                       << range.sectionName
                       << " 范围=[0x" << std::hex << range.start << ", 0x" << range.end << "]"
                       << std::dec << std::endl;
        }
    }
}


bool CppClassIdentifier::isValidPointerInSection(uintptr_t address, const CustomVector<SectionRange>& sections) const {
    if (address == 0) return false; // 空指针无效
    for (const auto& range : sections) {
        if (range.contains(address)) { // contains 应该实现为 address >= range.start && address < range.end
            return true;
        }
    }
    return false;
}

// 检查指针是否指向C字符串，主要检查应用的C字符串段和常量段
bool CppClassIdentifier::isPointerToCString(uintptr_t address, const CustomVector<SectionRange>& stringSections, const CustomVector<SectionRange>& constSectionsToAlsoCheck) const {
    if (address == 0) return false; // 空指针无效

    bool in_known_section = false; // 标记地址是否在已知区域
    // 首先检查是否在指定的字符串段中
    for (const auto& range : stringSections) {
        if (range.contains(address)) {
            in_known_section = true;
            break;
        }
    }
    // 如果不在字符串段，再检查是否在指定的常量段中 (mangled name有时在__const)
    if (!in_known_section) {
        for (const auto& range : constSectionsToAlsoCheck) {
            if (range.contains(address)) {
                in_known_section = true;
                break;
            }
        }
    }
    if (!in_known_section) return false; // 地址不在任何目标段中
    
    // (可选) 检查 _Z 前缀，但可能过于严格，因为非类类型的 type_info->name() 可能没有
    // const char* cstr = (const char*)address;
    // if (strncmp(cstr, "_Z", 2) != 0 && strncmp(cstr, "__Z", 3) !=0 ) { // Clang 可能用 __Z
    //     return false;
    // }

    // 在段边界内检查合理的字符串长度和空终止符
    size_t len = 0;
    uintptr_t current_char_addr = address;
    const size_t MAX_MANGLED_NAME_LEN = 1024; // mangled name 的最大合理长度

    while (len < MAX_MANGLED_NAME_LEN) {
        // 确保我们仍在有效的段内读取字符
        bool still_in_valid_char_read_section = false;
        for (const auto& range : stringSections) { if (range.contains(current_char_addr)) { still_in_valid_char_read_section = true; break; } }
        if (!still_in_valid_char_read_section) {
            for (const auto& range : constSectionsToAlsoCheck) { if (range.contains(current_char_addr)) { still_in_valid_char_read_section = true; break; } }
        }
        if (!still_in_valid_char_read_section) return false; // 字符串读取超出了已知段边界

        if (*(const char*)current_char_addr == '\0') return true; // 找到空终止符
        
        current_char_addr++;
        len++;
    }
    return false; // 在合理长度内未找到空终止符或超出了边界
}


CustomString CppClassIdentifier::demangle(const char* mangledName) const {
    if (!mangledName) return "";
    int status = 0;
    // 使用 abi::__cxa_demangle 进行解码
    char* demangled_c_str = abi::__cxa_demangle(mangledName, nullptr, nullptr, &status);
    if (status == 0 && demangled_c_str) {
        CustomString demangled_name(demangled_c_str);
        free(demangled_c_str); // 释放 __cxa_demangle 分配的内存
        return demangled_name;
    }
    return ""; // 如果解码失败，返回空字符串 (或者返回mangledName本身)
}

void CppClassIdentifier::scanForCppClasses() {
    ZQTOUT << "[信息] 开始执行 CppClassIdentifier::scanForCppClasses()" << std::endl;
    if (!initializeImageInfo()) {
        // initializeImageInfo 内部现在会打印自己的错误信息（如果它认为初始化失败）
        std::cerr << "[错误] CppClassIdentifier: 因镜像信息初始化问题退出扫描。" << std::endl;
        return;
    }

    knownCppClasses_.clear();
    processedTypeInfoAddresses_.clear();

    if (appConstSections_.empty()) {
        ZQTOUT << "[警告] 未找到可扫描的应用常量段。退出 scanForCppClasses。" << std::endl;
        return;
    }
    ZQTOUT << "[信息] 正在扫描 " << appConstSections_.size() << " 个应用常量段。" << std::endl;

    // 主扫描循环遍历 appConstSections_
    for (const auto& section : appConstSections_) {
        // 以指针大小为步长遍历段内地址
        for (uintptr_t current_addr = section.start;
             current_addr < section.end && current_addr <= section.end - sizeof(uintptr_t); // 防止越界
             current_addr += sizeof(uintptr_t)) {
            
            uintptr_t potential_type_info_ptr_value = *(uintptr_t*)current_addr; // current_addr处的值，可能是指向type_info的指针
            if (potential_type_info_ptr_value == 0) continue; // 跳过空指针

            // 步骤 1: potential_type_info_ptr_value (vtable[-1]槽中指向 type_info 的候选指针)
            // 应该指向一个实际的 type_info 对象，这个 type_info 对象本身也应该在应用的常量段中。
            if (!isValidPointerInSection(potential_type_info_ptr_value, appConstSections_)) {
                continue;
            }

            uintptr_t addr_ti = potential_type_info_ptr_value; // 这是候选RTTI对象的地址
            if (processedTypeInfoAddresses_.count(addr_ti)) { // 避免重复处理
                continue;
            }

            // 步骤 2: 验证位于 addr_ti 的 RTTI 对象的结构
            // 它应该包含一个 vptr (指向RTTI自身的vtable) 和一个 name_ptr。
            uintptr_t vptr_in_ti_obj_addr = addr_ti;                         // RTTI对象的vptr字段的地址
            uintptr_t name_ptr_in_ti_obj_addr = addr_ti + sizeof(void*); // RTTI对象的name_ptr字段的地址 (Itanium ABI)

            // 确保能安全读取RTTI对象内部的vptr字段和name_ptr字段
            bool can_read_rtti_vptr_field = false;
            uintptr_t containing_section_end_for_vptr = 0; // 用于存储包含vptr字段的节的结束地址
            for (const auto& s : appConstSections_) { // RTTI对象本身在应用的常量段内
                if (s.contains(vptr_in_ti_obj_addr)) {
                    containing_section_end_for_vptr = s.end;
                    // 检查整个vptr字段是否都在这个节内
                    if (vptr_in_ti_obj_addr + sizeof(void*) <= containing_section_end_for_vptr) {
                        can_read_rtti_vptr_field = true;
                    }
                    break;
                }
            }
            
            if (!can_read_rtti_vptr_field) {
                continue;
            }

            bool can_read_rtti_name_ptr_field = false;
            uintptr_t containing_section_end_for_name_ptr = 0; // 用于存储包含name_ptr字段的节的结束地址
            for (const auto& s : appConstSections_) { // RTTI对象本身在应用的常量段内
                if (s.contains(name_ptr_in_ti_obj_addr)) {
                    containing_section_end_for_name_ptr = s.end;
                    // 检查整个name_ptr字段是否都在这个节内
                    if (name_ptr_in_ti_obj_addr + sizeof(void*) <= containing_section_end_for_name_ptr) {
                        can_read_rtti_name_ptr_field = true;
                    }
                    break;
                }
            }
            if (!can_read_rtti_name_ptr_field) {
                continue;
            }
                        
            uintptr_t vptr_value_in_ti = *(uintptr_t*)vptr_in_ti_obj_addr;       // RTTI对象自身的vptr (指向RTTI vtable, 很可能在系统库中)
            const char* mangled_name_ptr_value = *(const char**)name_ptr_in_ti_obj_addr; // RTTI对象的name_ptr (指向mangled name字符串)

            // 步骤 3: RTTI对象的vptr (vptr_value_in_ti) 必须指向一个有效的RTTI vtable。
            // 这个vtable很可能在系统库中。
            bool is_rtti_vtable_location_valid = false;
            if (isValidPointerInSection(vptr_value_in_ti, systemRttiVTableSections_)) { // 检查系统库RTTI vtable段
                is_rtti_vtable_location_valid = true;
            } else if (isValidPointerInSection(vptr_value_in_ti, appConstSections_)) {
                // 也检查应用的常量段 (对于标准RTTI vtable不太可能，但作为后备检查)
                is_rtti_vtable_location_valid = true;
            }
            if (!is_rtti_vtable_location_valid) {
                continue;
            }
            
            // 步骤 4: RTTI对象的name_ptr必须指向一个有效的C字符串 (mangled name)。
            // 这个字符串通常在应用的cstring或const段中。
            if (!isPointerToCString((uintptr_t)mangled_name_ptr_value, appCStringSections_, appConstSections_)) {
                continue;
            }
            
            CustomString demangled_name_str = demangle(mangled_name_ptr_value);
            if (demangled_name_str.empty()) { // 如果解码失败或为空
                continue;
            }

            // 如果所有检查都通过了，我们很可能找到了一个有效的RTTI设置。
            // current_addr 是 vtable[-1] 槽 (包含 type_info*)。
            // 所以，class_vtable_first_func_slot_addr 是该类实例的 vtable[0] (第一个虚函数)。
            uintptr_t class_vtable_first_func_slot_addr = current_addr + sizeof(void*);

            // 健全性检查：class_vtable_first_func_slot_addr (即vtable[0]的地址) 应该在应用的常量段中
            // (因为它是类vtable的一部分)。
            // 其内容 (实际的函数指针) 应该在代码段中。
            if (!isValidPointerInSection(class_vtable_first_func_slot_addr, appConstSections_)) {
                 // 如果这个地址不在应用的常量段，说明vtable结构与预期不符 (如果current_addr是vtable[-1]的话)
                 continue;
            }
            // (可选检查) 检查 *(uintptr_t*)class_vtable_first_func_slot_addr 是否在 appTextSections_ 中。
            // 这个检查可能过于严格，因为纯虚函数、桩函数等原因。
            // 目前，我们假设如果进行到这里，它就是一个候选类。

            ZQTOUT << "[成功] 找到C++类: \"" << demangled_name_str.c_str() << "\""
                      << "\"" << mangled_name_ptr_value << "\""
                      << " (RTTI @ 0x" << std::hex << addr_ti // type_info 对象的地址
                      << ", Class VTable[0] @ 0x" << class_vtable_first_func_slot_addr // vtable中第一个虚函数条目的地址
                      << std::dec << ")" << std::endl;

            // 创建并存储类信息
            auto classInfo = make_unique_custom<CppClassInfo>(addr_ti, class_vtable_first_func_slot_addr, mangled_name_ptr_value, demangled_name_str.c_str());
            knownCppClasses_.push_back(*classInfo);
            processedTypeInfoAddresses_.insert(addr_ti); // 标记这个RTTI对象已处理
        }
    }
    ZQTOUT << "[信息] 扫描完成。找到 " << knownCppClasses_.size() << " 个C++类。" << std::endl;
}


bool CppClassIdentifier::isInstanceOfKnownCppClass(const void* instanceAddress, CustomString& outClassName) const {
    if (!instanceAddress) {
        return false;
    }
    // 此处假设 instanceAddress 是有效的、可读的，并且指向一个带有vptr的对象。
    uintptr_t instance_vptr_value = *(uintptr_t*)instanceAddress; // 对象实例的vptr指向vtable[0]

    for (const auto& class_info : knownCppClasses_) {
        // class_info.vtableFirstFuncAddress 存储的是 vtable[0] 的地址
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

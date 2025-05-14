//
//  CppClassInfo.h
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/14.
//

#ifndef CppClassInfo_h
#define CppClassInfo_h
#include <objc/runtime.h>
#include "ZQTCustomAllocator.hpp"
#include "ZQTMemoryTypes.hpp"
#include <mach/mach.h>

namespace ZQT {
// 用于存储已识别 C++ 类的 RTTI 和 vtable 信息的结构体
struct CppClassInfo {
    uintptr_t typeInfoAddress;        // type_info 对象的地址
    uintptr_t vtableFirstFuncAddress; // vtable 中第一个虚函数的地址
    CustomString mangledName;          // C++ ABI 编码后的名称
    CustomString demangledName;        // C++ ABI 解码后的可读名称

    CppClassInfo() = default;

    CppClassInfo(uintptr_t tiAddr, uintptr_t vtableAddr, const char* mName, const char* dName)
        : typeInfoAddress(tiAddr), vtableFirstFuncAddress(vtableAddr),
          mangledName(mName, CustomZoneAllocator<char>()), demangledName(dName, CustomZoneAllocator<char>()) {}

    CppClassInfo(const CppClassInfo& other)
        : typeInfoAddress(other.typeInfoAddress)
        , vtableFirstFuncAddress(other.vtableFirstFuncAddress)
        , mangledName(other.mangledName, CustomZoneAllocator<char>())
        , demangledName(other.demangledName, CustomZoneAllocator<char>()) {}

    CppClassInfo& operator=(const CppClassInfo& other) {
        if (this != &other) {
            typeInfoAddress = other.typeInfoAddress;
            vtableFirstFuncAddress = other.vtableFirstFuncAddress;
            mangledName = other.mangledName;
            demangledName = other.demangledName;
        }
        return *this;
    }

    CppClassInfo(CppClassInfo&& other) noexcept
        : typeInfoAddress(other.typeInfoAddress)
        , vtableFirstFuncAddress(other.vtableFirstFuncAddress)
        , mangledName(std::move(other.mangledName))
        , demangledName(std::move(other.demangledName)) {}

    CppClassInfo& operator=(CppClassInfo&& other) noexcept {
        if (this != &other) {
            typeInfoAddress = other.typeInfoAddress;
            vtableFirstFuncAddress = other.vtableFirstFuncAddress;
            mangledName = std::move(other.mangledName);
            demangledName = std::move(other.demangledName);
        }
        return *this;
    }
};

// 用于存储相关内存段信息的结构体
struct SectionRange {
    uintptr_t start;         // 段起始地址
    uintptr_t end;           // 段结束地址
    CustomString segmentName; // Segment 名称 (例如 __TEXT, __DATA)
    CustomString sectionName; // Section 名称 (例如 __const, __cstring)

    SectionRange() = default;

    SectionRange(uintptr_t s, uintptr_t e, const char* seg, const char* sect)
        : start(s), end(e), segmentName(seg, CustomZoneAllocator<char>()), sectionName(sect, CustomZoneAllocator<char>()) {}

    SectionRange(const SectionRange& other)
        : start(other.start)
        , end(other.end)
        , segmentName(other.segmentName, CustomZoneAllocator<char>())
        , sectionName(other.sectionName, CustomZoneAllocator<char>()) {}

    SectionRange& operator=(const SectionRange& other) {
        if (this != &other) {
            start = other.start;
            end = other.end;
            segmentName = other.segmentName;
            sectionName = other.sectionName;
        }
        return *this;
    }

    SectionRange(SectionRange&& other) noexcept
        : start(other.start)
        , end(other.end)
        , segmentName(std::move(other.segmentName))
        , sectionName(std::move(other.sectionName)) {}

    SectionRange& operator=(SectionRange&& other) noexcept {
        if (this != &other) {
            start = other.start;
            end = other.end;
            segmentName = std::move(other.segmentName);
            sectionName = std::move(other.sectionName);
        }
        return *this;
    }

    // 检查地址是否在此段范围内
    bool contains(uintptr_t address) const {
        return address >= start && address < end;
    }
};

}
#endif /* CppClassInfo_h */

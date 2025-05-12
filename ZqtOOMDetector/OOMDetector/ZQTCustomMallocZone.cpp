#include "ZQTCustomMallocZone.h"

const char *ZQTCustomMallocZoneName = "ZQTCustomMallocZone";
malloc_zone_t *ZQTCustomMallocZone = nullptr;
CFAllocatorRef ZQT_CFCustomAllocator = nullptr;

static void *__ZQTAllocatorCustomAllocate(CFIndex size, CFOptionFlags hint, void *info) {
    return malloc_zone_malloc(ZQTCustomMallocZone, size);
}

static void *__ZQTAllocatorCustomReallocate(void *ptr, CFIndex newsize, CFOptionFlags hint, void *info) {
    return malloc_zone_realloc(ZQTCustomMallocZone, ptr, newsize);
}

static void __ZQTAllocatorCustomDeallocate(void *ptr, void *info) {
    malloc_zone_free(ZQTCustomMallocZone, ptr);
}

void ZQTCreateCustomMallocZone(void) {
    if (ZQTCustomMallocZone == nullptr) {
        // 增加初始大小，减少重新分配的次数
        ZQTCustomMallocZone = malloc_create_zone(1024*1024, MALLOC_PTR_IN_USE_RANGE_TYPE);
        malloc_set_zone_name(ZQTCustomMallocZone, ZQTCustomMallocZoneName);
        
        printf("[ZQTOOMDetector][zone] create zone:%zx\n", (uintptr_t)ZQTCustomMallocZone);
        
        CFAllocatorContext context = {
            0,
            nullptr,
            nullptr,
            nullptr,
            nullptr,
            __ZQTAllocatorCustomAllocate,
            __ZQTAllocatorCustomReallocate,
            __ZQTAllocatorCustomDeallocate,
            nullptr
        };
        ZQT_CFCustomAllocator = CFAllocatorCreate(kCFAllocatorSystemDefault, &context);
    }
}

void ZQTDestroyCustomMallocZone(void) {
    if (ZQT_CFCustomAllocator) {
        CFRelease(ZQT_CFCustomAllocator);
    }
    if (ZQTCustomMallocZone) {
        malloc_destroy_zone(ZQTCustomMallocZone);
    }
    
    ZQTCustomMallocZone = nullptr;
    ZQT_CFCustomAllocator = nullptr;
    printf("[ZQTOOMDetector][zone] destroy zone\n");
} 

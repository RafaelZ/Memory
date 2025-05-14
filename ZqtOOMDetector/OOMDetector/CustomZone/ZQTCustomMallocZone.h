#ifndef ZQTCustomMallocZone_h
#define ZQTCustomMallocZone_h

#include <malloc/malloc.h>
#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

extern const char *ZQTCustomMallocZoneName;
extern malloc_zone_t *ZQTCustomMallocZone;
extern CFAllocatorRef ZQT_CFCustomAllocator;

void ZQTCreateCustomMallocZone(void);
void ZQTDestroyCustomMallocZone(void);

#ifdef __cplusplus
}
#endif

#endif /* ZQTCustomMallocZone_h */ 

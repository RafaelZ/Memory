//
//  ZQTVMStatistics.hpp
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/12.
//

#ifndef ZQTVMStatistics_hpp
#define ZQTVMStatistics_hpp

#include <stdio.h>

typedef enum {
    ZQT_OBJC_TAG_NSAtom            = 0,
    ZQT_OBJC_TAG_1                 = 1,
    ZQT_OBJC_TAG_NSString          = 2,
    ZQT_OBJC_TAG_NSNumber          = 3,
    ZQT_OBJC_TAG_NSIndexPath       = 4,
    ZQT_OBJC_TAG_NSManagedObjectID = 5,
    ZQT_OBJC_TAG_NSDate            = 6,
    ZQT_OBJC_TAG_7                 = 7
} ZQTObjcTag;

const char * vm_region_usertag_name(unsigned int user_tag);
bool vm_region_is_malloc_usertag(unsigned int user_tag);
const char * zqt_objc_tag_to_string(ZQTObjcTag tag);

#endif /* ZQTVMStatistics_hpp */

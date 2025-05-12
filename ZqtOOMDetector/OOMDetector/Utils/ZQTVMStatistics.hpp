//
//  ZQTVMStatistics.hpp
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/12.
//

#ifndef ZQTVMStatistics_hpp
#define ZQTVMStatistics_hpp

#include <stdio.h>
const char * vm_region_usertag_name(unsigned int user_tag);
bool vm_region_is_malloc_usertag(unsigned int user_tag);

#endif /* ZQTVMStatistics_hpp */

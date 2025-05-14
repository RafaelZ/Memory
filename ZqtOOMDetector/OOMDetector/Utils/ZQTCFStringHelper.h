//
//  CFStringHelper.h
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/14.
//

#ifndef ZQTCFStringHelper_h
#define ZQTCFStringHelper_h

#include <string>
#include <CoreFoundation/CoreFoundation.h>

std::string ZQT_CFStringToStdString(CFStringRef cfString) {
    if (!cfString) return "";
    
    CFIndex length = CFStringGetLength(cfString);
    CFIndex maxSize = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8);
    
    std::string result;
    result.resize(maxSize); // 预分配足够空间
    
    if (CFStringGetCString(cfString, &result[0], maxSize, kCFStringEncodingUTF8)) {
        // 调整为实际长度
        result.resize(strlen(result.c_str()));
        return result;
    }
    return "";
}

#endif /* CFStringHelper_h */

#ifndef ZQTOOMDetector_h
#define ZQTOOMDetector_h

#import <Foundation/Foundation.h>
#import "ZQTOOMDetectorTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZQTOOMDetector : NSObject

@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber *, ZQTMemoryNode *> *nodes;
@property (nonatomic, strong, readonly) NSMutableArray<ZQTReferenceEdge *> *edges;

+ (instancetype)sharedInstance;

- (void)startAnalysis;
- (void)stopAnalysis;
- (void)clear;

@end

NS_ASSUME_NONNULL_END

#endif /* ZQTOOMDetector_h */ 
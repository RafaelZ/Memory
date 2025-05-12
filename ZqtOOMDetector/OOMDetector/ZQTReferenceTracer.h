#ifndef ZQTReferenceTracer_h
#define ZQTReferenceTracer_h

#import <Foundation/Foundation.h>
#import "ZQTOOMDetectorTypes.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZQTReferenceTracer : NSObject

//@property (nonatomic, strong, readonly) NSMutableDictionary<NSNumber *, ZQTMemoryNode *> *nodes;
@property (nonatomic, strong, readonly) NSMutableArray<ZQTReferenceEdge *> *edges;

- (void)analyzeReferences;
- (void)clear;

- (void)setNodes:(NSMutableDictionary<NSNumber *,ZQTMemoryNode *> * _Nonnull)nodes;

@end

NS_ASSUME_NONNULL_END

#endif /* ZQTReferenceTracer_h */ 

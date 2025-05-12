#ifndef ZQTOOMDetectorTypes_h
#define ZQTOOMDetectorTypes_h

#import <Foundation/Foundation.h>
#import <mach/mach.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZQTObjectType) {
    ZQTObjectTypeObjectiveC,
    ZQTObjectTypeSwift,
    ZQTObjectTypeCPP,
    ZQTObjectTypeCGRasterData,
    ZQTObjectTypeUnknown
};

typedef NS_ENUM(NSInteger, ZQTReferenceStrength) {
    ZQTReferenceStrengthStrong,
    ZQTReferenceStrengthWeak,
    ZQTReferenceStrengthUnowned,
    ZQTReferenceStrengthUnknown
};

@interface ZQTMemoryNode : NSObject

@property (nonatomic, assign) vm_address_t address;
@property (nonatomic, assign) vm_size_t size;
@property (nonatomic, assign) ZQTObjectType type;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) id metadata;

+ (instancetype)nodeWithAddress:(vm_address_t)address
                          size:(vm_size_t)size
                          type:(ZQTObjectType)type
                          name:(NSString *)name
                      metadata:(id)metadata;

@end

@interface ZQTReferenceEdge : NSObject

@property (nonatomic, strong) ZQTMemoryNode *source;
@property (nonatomic, strong) ZQTMemoryNode *target;
@property (nonatomic, copy) NSString *referenceName;
@property (nonatomic, assign) ptrdiff_t offset;
@property (nonatomic, assign) ZQTReferenceStrength strength;

+ (instancetype)edgeWithSource:(ZQTMemoryNode *)source
                        target:(ZQTMemoryNode *)target
                referenceName:(NSString *)referenceName
                       offset:(ptrdiff_t)offset
                     strength:(ZQTReferenceStrength)strength;

@end

NS_ASSUME_NONNULL_END

#endif /* ZQTOOMDetectorTypes_h */ 
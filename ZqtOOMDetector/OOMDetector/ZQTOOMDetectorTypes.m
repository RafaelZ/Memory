#import "ZQTOOMDetectorTypes.h"

@implementation ZQTMemoryNode

+ (instancetype)nodeWithAddress:(vm_address_t)address
                          size:(vm_size_t)size
                          type:(ZQTObjectType)type
                          name:(NSString *)name
                      metadata:(id)metadata {
    ZQTMemoryNode *node = [[ZQTMemoryNode allocWithZone:nil] init];
    node.address = address;
    node.size = size;
    node.type = type;
    node.name = name;
    node.metadata = metadata;
    return node;
}

@end

@implementation ZQTReferenceEdge

+ (instancetype)edgeWithSource:(ZQTMemoryNode *)source
                        target:(ZQTMemoryNode *)target
                referenceName:(NSString *)referenceName
                       offset:(ptrdiff_t)offset
                     strength:(ZQTReferenceStrength)strength {
    ZQTReferenceEdge *edge = [[ZQTReferenceEdge alloc] init];
    edge.source = source;
    edge.target = target;
    edge.referenceName = referenceName;
    edge.offset = offset;
    edge.strength = strength;
    return edge;
}

@end 

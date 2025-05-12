#import "ZQTReferenceTracer.h"
#import <objc/runtime.h>

@interface ZQTReferenceTracer ()

@property (nonatomic, strong) NSMutableDictionary<NSNumber *, ZQTMemoryNode *> *nodes;
@property (nonatomic, strong) NSMutableArray<ZQTReferenceEdge *> *edges;

@end

@implementation ZQTReferenceTracer

- (instancetype)init {
    self = [super init];
    if (self) {
        _nodes = [NSMutableDictionary dictionary];
        _edges = [NSMutableArray array];
    }
    return self;
}

- (void)analyzeReferences {
    [self clear];
    
    // 遍历所有节点
    for (ZQTMemoryNode *node in self.nodes.allValues) {
        if (node.type == ZQTObjectTypeObjectiveC) {
            [self analyzeObjCObject:node];
        }
        // 其他类型的对象分析将在后续实现
    }
}

- (void)analyzeObjCObject:(ZQTMemoryNode *)node {
    Class cls = node.metadata;
    if (!cls) {
        return;
    }
    
    // 获取所有 ivar
    unsigned int count;
    Ivar *ivars = class_copyIvarList(cls, &count);
    if (!ivars) {
        return;
    }
    
    // 获取 ivar 布局
    const uint8_t *strongLayout = class_getIvarLayout(cls);
    const uint8_t *weakLayout = class_getWeakIvarLayout(cls);
    
    // 解析布局
    NSIndexSet *strongIndexes = [self parseIvarLayout:strongLayout];
    NSIndexSet *weakIndexes = [self parseIvarLayout:weakLayout];
    
    // 遍历 ivar
    for (unsigned int i = 0; i < count; i++) {
        Ivar ivar = ivars[i];
        const char *type = ivar_getTypeEncoding(ivar);
        
        // 只处理对象类型的 ivar
        if (type[0] == '@') {
            ptrdiff_t offset = ivar_getOffset(ivar);
            void *ivarPtr = (void *)((uintptr_t)node.address + offset);
            id value = object_getIvar((__bridge id)(void *)node.address, ivar);
            
            if (value) {
                vm_address_t targetAddress = (vm_address_t)value;
                ZQTMemoryNode *targetNode = self.nodes[@(targetAddress)];
                
                if (targetNode) {
                    ZQTReferenceStrength strength;
                    if ([strongIndexes containsIndex:i]) {
                        strength = ZQTReferenceStrengthStrong;
                    } else if ([weakIndexes containsIndex:i]) {
                        strength = ZQTReferenceStrengthWeak;
                    } else {
                        strength = ZQTReferenceStrengthUnknown;
                    }
                    
                    ZQTReferenceEdge *edge = [ZQTReferenceEdge edgeWithSource:node
                                                                      target:targetNode
                                                              referenceName:@(ivar_getName(ivar))
                                                                     offset:offset
                                                                   strength:strength];
                    [self.edges addObject:edge];
                }
            }
        }
    }
    
    free(ivars);
}

- (NSIndexSet *)parseIvarLayout:(const uint8_t *)layout {
    if (!layout) {
        return [NSIndexSet indexSet];
    }
    
    NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
    NSUInteger index = 0;
    
    while (*layout != '\0') {
        unsigned char byte = *layout++;
        unsigned char skip = (byte >> 4) & 0x0F;
        unsigned char count = byte & 0x0F;
        
        index += skip;
        
        for (unsigned char i = 0; i < count; i++) {
            [indexes addIndex:index++];
        }
    }
    
    return indexes;
}

- (void)clear {
    [_nodes removeAllObjects];
    [_edges removeAllObjects];
}

@end 

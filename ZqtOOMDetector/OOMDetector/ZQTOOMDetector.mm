#import "ZQTOOMDetector.h"
#import "ZQTHeapWalker.h"
#import "ZQTReferenceTracer.h"
#import "ZQTObjCIdentifierStrategy.h"
#import "ZQTCustomMallocZone.h"
#import "ZQTVMRegionWalker.h"

@interface ZQTOOMDetector ()

@property (nonatomic, strong) NSMutableDictionary<NSNumber *, ZQTMemoryNode *> *nodes;
@property (nonatomic, strong) NSMutableArray<ZQTReferenceEdge *> *edges;
@property (nonatomic, strong) ZQTReferenceTracer *referenceTracer;
@property (nonatomic, assign) BOOL isAnalyzing;

@end

@implementation ZQTOOMDetector
{
    ZQT::HeapWalker *_heapWalker;
    ZQT::VMRegionWalker *_vmRegionWalker;
    ZQT::ObjCIdentifierStrategy *_objCIdentifier;
}

+ (instancetype)sharedInstance {
    static ZQTOOMDetector *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ZQTOOMDetector alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _nodes = [[NSMutableDictionary alloc] init];
        _edges = [[NSMutableArray alloc] init];
        _heapWalker = new ZQT::HeapWalker();
        _vmRegionWalker = new ZQT::VMRegionWalker();
        _objCIdentifier = new ZQT::ObjCIdentifierStrategy();
        _referenceTracer = [[ZQTReferenceTracer alloc] init];
        _isAnalyzing = NO;
    }
    return self;
}

- (void)dealloc {
    [self stopAnalysis];
    if (_heapWalker) {
        delete _heapWalker;
        _heapWalker = nullptr;
    }
    if (_vmRegionWalker) {
        delete _vmRegionWalker;
        _vmRegionWalker = nullptr;
    }
    if (_objCIdentifier) {
        delete _objCIdentifier;
        _objCIdentifier = nullptr;
    }
}

- (void)startAnalysis {
    if (_isAnalyzing) {
        return;
    }
    
    _isAnalyzing = YES;
    [self clear];
    
    // 确保使用自定义 malloc zone
    ZQTCreateCustomMallocZone();
    
    // 1. 扫描 VM Regions
    if (_vmRegionWalker) {
        _vmRegionWalker->startWalkingFromTask(mach_task_self());
    }
    
    // 2. 扫描堆内存
    if (_heapWalker) {
        _heapWalker->scanHeap();
    }
    
    // 3. 识别对象类型
    const auto& walkerNodes = _heapWalker->getNodes();
//    for (const auto& [address, node] : walkerNodes) {
//        if (_objCIdentifier) {
//            MemoryNode *identifiedNode = _objCIdentifier->identifyObjectAtAddress(address, node.size);
//            if (identifiedNode) {
//                [self.nodes setObject:identifiedNode forKey:@(address)];
//            }
//        }
//    }
    
    // 4. 分析引用关系
    [self.referenceTracer setNodes:self.nodes];
    [self.referenceTracer analyzeReferences];
    self.edges = self.referenceTracer.edges;
}

- (void)stopAnalysis {
    if (!_isAnalyzing) {
        return;
    }
    
    _isAnalyzing = NO;
    [self clear];
    ZQTDestroyCustomMallocZone();
}

- (void)clear {
    [_nodes removeAllObjects];
    [_edges removeAllObjects];
    if (_heapWalker) {
        _heapWalker->clear();
    }
    if (_vmRegionWalker) {
        _vmRegionWalker->clear();
    }
    [self.referenceTracer clear];
}

@end 

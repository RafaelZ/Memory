//
//  ZQTTestObject.m
//  ZqtOOMDetectorTests
//
//  Created by 张千通 on 2025/5/12.
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import "FLEXObjcInternal.h"
@interface ZQTTestObject : XCTestCase

@end

@implementation ZQTTestObject

- (void)setUp {
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

typedef struct objc_structure_mock {
    Class isa;
} objc_structure_mock;

NSString *stringA = nil;
- (void)testExample {
    [self updateRegisteredClasses];
    [self checkTpString];
    stringA = [NSString stringWithFormat:@"1%@",@"a"];
    NSLog(@"stringA %@ %p %p %@",stringA,stringA,&stringA,NSStringFromClass([stringA class]));
    uintptr_t address = (uintptr_t)&stringA;
    bool result = [self innerCheckAddress:address];
    NSLog(@"result %d",result);
//    vm_address_t *addr = (vm_address_t *)stringA;
//    objc_structure_mock *rawMemoryObject = (__bridge objc_structure_mock *)addr;
//    Class *objectClass = (__bridge Class)\((void *)((uint64_t)rawMemoryObject->isa & objc_debug_isa_class_mask));
//    Class taggerPStr = [stringA class];
//    //TODO: 判断tagged Pointer是否能通过这种方式获得class

//    NSLog(@"%p %llu %",taggerPStr,objc_debug_isa_class_mask);
}

static CFMutableSetRef registeredClasses;

- (void)updateRegisteredClasses {
    if (!registeredClasses) {
        registeredClasses = CFSetCreateMutable(NULL, 0, NULL);
    } else {
        CFSetRemoveAllValues(registeredClasses);
    }
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned int i = 0; i < count; i++) {
        CFSetAddValue(registeredClasses, (__bridge const void *)(classes[i]));
    }
    free(classes);
}

- (void)checkTpString
{
    Class cls = objc_getClass("NSTaggedPointerString");
    const void * ptr = (__bridge const void *)(cls);
    NSLog(@"NSTaggedPointerString class ptr %p",ptr);
    BOOL result = CFSetContainsValue(registeredClasses, ptr);
    XCTAssertTrue(result,"失败");
    
}
- (bool)innerCheckAddress:(uint64_t)address
{
    objc_structure_mock *rawMemoryObject = (objc_structure_mock *)address;
    
    extern uint64_t objc_debug_isa_class_mask WEAK_IMPORT_ATTRIBUTE;
    Class objectClass = (__bridge Class)((void *)((uint64_t)rawMemoryObject->isa & objc_debug_isa_class_mask));
    bool result = CFSetContainsValue(registeredClasses, (__bridge const void *)(objectClass));
    if (!result) {
        result = flex_isTaggedPointer((void *)((uint64_t)rawMemoryObject->isa));
        XCTAssertTrue(result,"tttt");
    }
    return result;
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
    }];
}

@end

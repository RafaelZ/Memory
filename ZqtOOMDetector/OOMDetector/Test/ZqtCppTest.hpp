//
//  ZqtCppTest.hpp
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/14.
//

#ifndef ZqtCppTest_hpp
#define ZqtCppTest_hpp

#include <stdio.h>
#include <iostream>

class Human {
public:
    int age;
    int sex;

    void sayHello();
};

class BasePeple {
public:

    BasePeple(int i) :baseI(i){};

    int getI(){ return baseI; }

    static void countI();

    virtual ~BasePeple();

    virtual void basePrint(void);

private:

    int baseI;

    static int baseS;
};

class Male : public BasePeple {
public:
    Male(int i): BasePeple(i){

    };
    void sayHello();
    
    // 重写父类虚函数
    virtual void basePrint(void) override;
};

// 新增一个继承类，增加更多的虚函数测试
class Female : public BasePeple {
public:
    Female(int i): BasePeple(i), femaleName("Unknown") {}
    Female(int i, const char* name): BasePeple(i), femaleName(name) {}
    
    virtual ~Female();
    
    virtual void basePrint(void) override;
    virtual void introduce();
    
private:
    const char* femaleName;
};

void CreateAndUseTestClasses();
#endif /* ZqtCppTest_hpp */

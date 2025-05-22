//
//  ZqtCppTest.cpp
//  ZqtOOMDetector
//
//  Created by 张千通 on 2025/5/14.
//

#include "ZqtCppTest.hpp"
#include <iostream>

// 静态成员变量定义
int BasePeple::baseS = 0;

// Human类方法实现
void Human::sayHello() {
    std::cout << "Hello, I am a human of age " << age << std::endl;
}

// Base类方法实现
BasePeple::~BasePeple() {
    std::cout << "Base destructor called" << std::endl;
}

void BasePeple::countI() {
    baseS++;
    std::cout << "Static count: " << baseS << std::endl;
}

void BasePeple::basePrint(void) {
    std::cout << "Base::basePrint() - baseI = " << baseI << std::endl;
}

// Male类方法实现
void Male::sayHello() {
    std::cout << "Hello, I am a male with Base value " << getI() << std::endl;
}

void Male::basePrint(void) {
    std::cout << "Male::basePrint() - I = " << getI() << std::endl;
}

// Female类方法实现
Female::~Female() {
    std::cout << "Female destructor called" << std::endl;
}

void Female::basePrint(void) {
    std::cout << "Female::basePrint() - I = " << getI() << std::endl;
}

void Female::introduce() {
    std::cout << "I am a female named " << femaleName << std::endl;
}

// 用于测试的帮助函数
void CreateAndUseTestClasses() {
    // 创建各类实例以确保RTTI信息生成
    Human human;
    human.age = 30;
    human.sex = 1;
    human.sayHello();
    
    BasePeple* base = new BasePeple(100);
    base->basePrint();
    
    Male* male = new Male(200);
    male->sayHello();
    male->basePrint();
    
    Female* female = new Female(300, "Alice");
    female->basePrint();
    female->introduce();
    
    // 使用typeid强制生成RTTI信息
    std::cout << "使用typeid获取类型信息:" << std::endl;
    std::cout << "Human类型: " << typeid(human).name() << std::endl;
    std::cout << "Base类型: " << typeid(*base).name() << std::endl;
    std::cout << "Male类型: " << typeid(*male).name() << std::endl;
    std::cout << "Female类型: " << typeid(*female).name() << std::endl;
    
    // 多态测试
    BasePeple* polymorphic_base = male;
    std::cout << "多态Base实际类型: " << typeid(*polymorphic_base).name() << std::endl;
    polymorphic_base->basePrint();
    
    // 释放内存
    delete base;
    delete male;
    delete female;
}

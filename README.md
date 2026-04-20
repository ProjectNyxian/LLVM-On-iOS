# LLVM-On-iOS
LLVM distribution for apple mobile devices without any complications. Originally made closed source for Nyxian, but published for the people to use instead, since ProjectNyxian made many useful modifications.
## Building

> [!WARNING]
> This can take very long, We recommend that you use a 8 core CPU and 16GB RAM at minumum!

```bash
git clone https://github.com/NyxianProject/LLVM-On-iOS.git
cd LLVM-On-iOS
make all
```

## Included
- [x] LLVM.xcframework
    - [x] Assembler
    - [x] Clang (C,C++,ObjC,ObjC++ Compiler/AST API's)
    - [x] LLD (Linker for object files)
- [x] CoreCompiler.framework
    - [x] Easy to use ARC compatible abstraction over LLVM
    - [x] Incremental typechecking possible
    - [x] Compiling C language files to object files
    - [x] Linking Object files to MachO possible
    - [ ] C language file indexing
    - [ ] Easy clang invocation in-process (still needs CCKDriver invocation and manual CCKJob execution using CCKCompiler/CCKLinker)
    - [ ] Easy linker invocation in-process

## Todo
- create a swift package for swift projects (kinda needs the following Todo aswell).
- compile swift compiler for iOS (specifically needed is the frontend of swift, the part that converts swift code into LLVM IR, because LLVM IR can be compiled down to machine code without any problem...)
- compile libffi for iOS (required for certain JIT operations)

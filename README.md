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
    - Assembler
    - Clang (C,C++,ObjC,ObjC++ Compiler/AST API's)
    - LLD (Linker for object files)

## Todo
- create a .framework
- create a swift package for swift projects (kinda needs the following Todo aswell).
- create a API for swift projects to interact with this better
- compile swift compiler for iOS (specifically needed is the frontend of swift, the part that converts swift code into LLVM IR, because LLVM IR can be compiled down to machine code without any problem...)
- compile liblldb for iOS (would be nice for debugging, but we decided to write our own debugger in nyxian, as liblldb has some things that make us fearfull)
- compile libffi for iOS (required for certain JIT operations)

# LLVM-On-iOS
LLVM 21.x and Swift 6.x distribution for apple mobile devices without any complications. Originally made closed source for Nyxian, but published for the people to use instead, since ProjectNyxian made many useful modifications.
## Building

> [!WARNING]
> This can take very long, We recommend that you use a 8 core CPU and 16GB RAM at minumum!

```bash
git clone https://github.com/NyxianProject/LLVM-On-iOS.git
cd LLVM-On-iOS
make all
```

## Included
- [x] CoreCompiler.framework
    - [x] Easy to use ARC compatible abstraction over LLVM (CoreCompiler)
    - [x] Incremental typechecking (CCKASTUnit)
    - [x] Compiling C language files to object files (CCKCompiler)
    - [x] Linking Object files to MachO (CCKLinker)
    - [ ] C language file indexing
    - [x] Easy clang invocation in-process (CCKProgramCompiler)
    - [x] Easy linker invocation in-process (CCKProgramCompiler)
    - [x] Swift compiler (CCKSwiftCompiler)
    - [ ] Swift incremental typecheckin
    - [ ] Easy to use multilanguage driver (C languages and Swift, produces all jobs)

## Todo
- create a swift package for swift projects (kinda needs the following Todo aswell).
- compile libffi for iOS (required for certain JIT operations)

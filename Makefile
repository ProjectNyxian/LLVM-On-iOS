# Quick configurations
ROOT := $(PWD)
OS_VER := 14.0
LLVM_ARCH := AArch64
APPLE_ARCH := arm64
TARGET_TRIPLE := $(APPLE_ARCH)-apple-ios$(OS_VER)
LLVM_TAG := swift-6.3-RELEASE

# Cmake configurations
LLVM_CMAKE_FLAGS := -G "Ninja" \
					-DCMAKE_BUILD_TYPE=Release \
					-DLLVM_ENABLE_PROJECTS="clang;lld" \
					-DLLVM_TARGETS_TO_BUILD="$(LLVM_ARCH)" \
					-DLLVM_TARGET_ARCH="$(LLVM_ARCH)" \
					-DLLVM_DEFAULT_TARGET_TRIPLE="$(TARGET_TRIPLE)" \
					-DBUILD_SHARED_LIBS=OFF \
					-DLLVM_ENABLE_ZLIB=OFF \
					-DLLVM_ENABLE_ZSTD=OFF \
					-DLLVM_ENABLE_THREADS=ON \
					-DLLVM_ENABLE_UNWIND_TABLES=OFF \
					-DLLVM_ENABLE_EH=OFF \
					-DLLVM_ENABLE_RTTI=ON \
					-DLLVM_ENABLE_TERMINFO=OFF \
					-DCMAKE_INSTALL_PREFIX="$(ROOT)/LLVM-iphoneos" \
					-DCMAKE_TOOLCHAIN_FILE=../llvm/cmake/platforms/iOS.cmake \
					-DLLVM_ENABLE_LIBXML2=OFF \
					-DCLANG_ENABLE_STATIC_ANALYZER=OFF \
					-DCLANG_ENABLE_ARCMT=OFF \
					-DCLANG_TABLEGEN_TARGETS="$(LLVM_ARCH)" \
					-DCMAKE_C_FLAGS="-target $(TARGET_TRIPLE)" \
					-DCMAKE_CXX_FLAGS="-target $(TARGET_TRIPLE)" \
					-DCMAKE_OSX_ARCHITECTURES="$(APPLE_ARCH)" \
					-DLLVM_FORCE_VC_REPOSITORY=https://github.com/ProjectNyxian/LLVM-On-iOS \
					-DLLVM_BUILD_UTILS=OFF \
					-DLLVM_INCLUDE_UTILS=OFF \
					-DLLVM_BUILD_BENCHMARKS=OFF \
					-DLLVM_INCLUDE_BENCHMARKS=OFF \
					-DLLVM_BUILD_TOOLS=OFF \
					-DCLANG_BUILD_TOOLS=OFF \
					-DLLVM_INCLUDE_TESTS=OFF \
					-DLLVM_BUILD_TESTS=OFF

# Helper function
define log_info
	@echo "\033[32m\033[1m[*] \033[0m\033[32m$(1)\033[0m"
endef

# Main Target
all: CoreCompiler.framework/CoreCompiler

# Fetch
llvm-project:
	$(call log_info,downloading llvm ($(LLVM_TAG)))
	git clone --depth 1 --branch $(LLVM_TAG) --single-branch https://github.com/swiftlang/llvm-project.git
	$(call log_info,bypassing lld darwin incompatibility ($(LLVM_TAG)))
	perl -i -0pe 's|(// Swift LLVM fork downstream change start\n)(.*?)(// Swift LLVM fork downstream change end\n)|$$1/* NYXIAN: apple lies, lld works fine for MachO\n$$2*/\n$$3|s' \
	llvm-project/lld/MachO/InputFiles.cpp

# Configure
llvm-project/build/build.ninja:
	$(call log_info,preparing llvm ($(LLVM_TAG)))
	mkdir llvm-project/build
	$(call log_info,configuring llvm ($(LLVM_TAG)))
	cd llvm-project/build; \
	    cmake $(LLVM_CMAKE_FLAGS) ../llvm
	$(call log_info,patching configuration of llvm)
	sed -i.bak 's/^HAVE_FFI_CALL:INTERNAL=/HAVE_FFI_CALL:INTERNAL=1/g' llvm-project/build/CMakeCache.txt

# Build
LLVM-iphoneos: llvm-project llvm-project/build/build.ninja
	$(call log_info,building llvm ($(LLVM_TAG)))
	cmake --build llvm-project/build --target install

# Bundle
LLVM-iphoneos/llvm.a: LLVM-iphoneos
	$(call log_info,combining LLVM libraries into llvm.a)
	libtool -static -o LLVM-iphoneos/llvm.a LLVM-iphoneos/lib/*.a

LLVM.xcframework: LLVM-iphoneos/llvm.a
	$(call log_info,creating LLVM framework out of llvm ($(LLVM_TAG)))
	xcodebuild -create-xcframework \
		-library "LLVM-iphoneos/llvm.a" \
	 	-headers "LLVM-iphoneos/include" \
	 	-output LLVM.xcframework

CoreCompiler.framework/CoreCompiler: SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
CoreCompiler.framework/CoreCompiler: INC := -ISource -ILLVM.xcframework/ios-arm64/Headers
CoreCompiler.framework/CoreCompiler: LLVM.xcframework
	$(call log_info,building CoreCompiler framework)
	-rm *.o
	clang -c -target $(TARGET_TRIPLE) -isysroot $(SDK) $(INC) Source/CoreCompiler/*.c
	clang -c -fobjc-arc -ObjC -target $(TARGET_TRIPLE) -isysroot $(SDK) $(INC) Source/CoreCompiler/*.m
	clang++ -c -Wno-elaborated-enum-base -std=c++17 -target $(TARGET_TRIPLE) -isysroot $(SDK) $(INC) Source/CoreCompiler/*.cpp
	clang++ -fobjc-arc -fno-rtti -fvisibility=hidden -fvisibility-inlines-hidden -ffunction-sections -fdata-sections -Wl,-dead_strip -flto=full -Os -fno-exceptions -Wl,-x -Wl,-S -Wl,-dead_strip_dylibs -ObjC -target $(TARGET_TRIPLE) -isysroot $(SDK) *.o LLVM.xcframework/ios-arm64/llvm.a  -framework CoreFoundation -o CoreCompiler.framework/CoreCompiler -shared -fPIC -install_name @rpath/CoreCompiler.framework/CoreCompiler
	-rm *.o
	-rm -rf CoreCompiler.framework/Headers
	mkdir -p CoreCompiler.framework/Headers
	cp Source/CoreCompiler/*.h CoreCompiler.framework/Headers/

# Cleanup
clean-artifacts:
	- rm CoreCompiler.framework/CoreCompiler
	- rm CoreCompiler.framework/Headers/*
	- rm -rf LLVM.xcframework

clean: clean-artifacts
	$(call log_info,cleaning up)
	find . -mindepth 1 -maxdepth 1 \
		! -name Makefile \
		! -name LICENSE \
		! -name README.md \
		! -name .git \
		! -name .gitignore \
		! -name .github \
		! -name CoreCompiler.framework \
		! -name Source \
		-exec rm -rf {} +

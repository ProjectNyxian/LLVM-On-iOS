# Quick configurations
ROOT := $(PWD)
OS_VER := 14.0
LLVM_ARCH := AArch64
APPLE_ARCH := arm64

# Cmake configurations
LLVM_CMAKE_FLAGS := -G "Ninja" \
					-DLLVM_ENABLE_PROJECTS="clang;lld" \
					-DLLVM_TARGETS_TO_BUILD="$(LLVM_ARCH)" \
					-DLLVM_TARGET_ARCH="$(LLVM_ARCH)" \
					-DLLVM_DEFAULT_TARGET_TRIPLE="$(APPLE_ARCH)-apple-ios" \
					-DLLVM_BUILD_TOOLS=OFF \
					-DCLANG_BUILD_TOOLS=OFF \
					-DBUILD_SHARED_LIBS=OFF \
					-DLLVM_ENABLE_ZLIB=OFF \
					-DLLVM_ENABLE_ZSTD=OFF \
					-DLLVM_ENABLE_THREADS=ON \
					-DLLVM_ENABLE_UNWIND_TABLES=OFF \
					-DLLVM_ENABLE_EH=OFF \
					-DLLVM_ENABLE_RTTI=ON \
					-DLLVM_ENABLE_TERMINFO=OFF \
					-DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_INSTALL_PREFIX="$(ROOT)/LLVM-iphoneos" \
					-DCMAKE_TOOLCHAIN_FILE=../llvm/cmake/platforms/iOS.cmake \
					-DLLVM_ENABLE_LIBXML2=OFF \
					-DCLANG_ENABLE_STATIC_ANALYZER=OFF \
					-DCLANG_ENABLE_ARCMT=OFF \
					-DCLANG_TABLEGEN_TARGETS="$(LLVM_ARCH)" \
					-DCMAKE_C_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_CXX_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_OSX_ARCHITECTURES="$(APPLE_ARCH)" \
					-DLLVM_FORCE_VC_REPOSITORY=https://github.com/ProjectNyxian/LLVM-On-iOS

# Helper functions
define log_info
	@echo "\033[32m\033[1m[*] \033[0m\033[32m$(1)\033[0m"
endef

# Main Targets
all: stable

stable: LLVM_VER := 19.1.7
stable: LLVM.xcframework Clang.xcframework clean

latest: LLVM_VER := 21.1.8
latest: LLVM.xcframework Clang.xcframework clean

bleeding-edge: LLVM_VER := 21.1.0-rc3
bleeding-edge: LLVM.xcframework Clang.xcframework clean

# Actual Makefile
llvm-project-$(LLVM_VER).src.tar.xz:
	$(call log_info,downloading llvm ($(LLVM_VER)))
	curl -OL https://github.com/llvm/llvm-project/releases/download/llvmorg-$(LLVM_VER)/llvm-project-$(LLVM_VER).src.tar.xz

llvm-project-$(LLVM_VER).src: llvm-project-$(LLVM_VER).src.tar.xz
	$(call log_info,extracting llvm ($(LLVM_VER)))
	tar xzf llvm-project-$(LLVM_VER).src.tar.xz

llvm-project-$(LLVM_VER).src/build:
	$(call log_info,preparing llvm ($(LLVM_VER)))
	mkdir llvm-project-$(LLVM_VER).src/build
	$(call log_info,configuring llvm ($(LLVM_VER)))
	cd llvm-project-$(LLVM_VER).src/build; \
	    cmake $(LLVM_CMAKE_FLAGS) ../llvm
	$(call log_info,patching configuration of llvm ($(LLVM_VER)))
	sed -i.bak 's/^HAVE_FFI_CALL:INTERNAL=/HAVE_FFI_CALL:INTERNAL=1/g' llvm-project-$(LLVM_VER).src/build/CMakeCache.txt

LLVM-iphoneos: llvm-project-$(LLVM_VER).src llvm-project-$(LLVM_VER).src/build
	$(call log_info,building llvm ($(LLVM_VER)))
	cd llvm-project-$(LLVM_VER).src/build; \
		cmake --build . --target install

LLVM-iphoneos/llvm.a: LLVM-iphoneos
	$(call log_info,combining LLVM libraries into llvm.a)
	libtool -static -o LLVM-iphoneos/llvm.a \
		LLVM-iphoneos/lib/libLLVM*.a \
		LLVM-iphoneos/lib/libclang*.a \
		LLVM-iphoneos/lib/liblld*.a \

LLVM.xcframework: LLVM-iphoneos/llvm.a
	$(call log_info,creating LLVM framework out of llvm ($(LLVM_VER)))
	mkdir llvm-headers
	cp -r LLVM-iphoneos/include/* llvm-headers/
	rm -rf llvm-headers/clang-c
	xcodebuild -create-xcframework \
		-library "LLVM-iphoneos/llvm.a" \
	 	-headers "llvm-headers" \
	 	-output LLVM.xcframework
	rm -rf llvm-headers

Clang.xcframework: LLVM-iphoneos
	$(call log_info,creating Clang framework out of llvm ($(LLVM_VER)))
	mkdir clang-headers
	cp -r LLVM-iphoneos/include/clang-c clang-headers/
	xcodebuild -create-xcframework \
		-library "LLVM-iphoneos/lib/libclang.dylib" \
		-headers "clang-headers" \
		-output Clang.xcframework
	rm -rf clang-headers

clean:
	$(call log_info,cleaning up)
	rm -rf llvm*
	rm -rf LLVM-iphoneos
	rm -rf Release-iphoneos
	rm -rf *headers

clean-all: clean
	rm -rf *.xcframework

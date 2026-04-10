# Quick configurations
ROOT := $(PWD)
OS_VER := 14.0
LLVM_VER := 19.1.7
LLVM_ARCH := AArch64
APPLE_ARCH := arm64

# Cmake configurations
LLVM_CMAKE_FLAGS := -G "Ninja" \
					-DCMAKE_BUILD_TYPE=Release \
					-DLLVM_ENABLE_PROJECTS="clang;lld" \
					-DLLVM_TARGETS_TO_BUILD="$(LLVM_ARCH)" \
					-DLLVM_TARGET_ARCH="$(LLVM_ARCH)" \
					-DLLVM_DEFAULT_TARGET_TRIPLE="$(APPLE_ARCH)-apple-ios" \
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
					-DCMAKE_C_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_CXX_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
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
all: LLVM.xcframework

# Fetch
llvm-project-$(LLVM_VER).src.tar.xz:
	$(call log_info,downloading llvm ($(LLVM_VER)))
	curl -OL https://github.com/llvm/llvm-project/releases/download/llvmorg-$(LLVM_VER)/llvm-project-$(LLVM_VER).src.tar.xz

# Extract
llvm-project-$(LLVM_VER).src: llvm-project-$(LLVM_VER).src.tar.xz
	$(call log_info,extracting llvm ($(LLVM_VER)))
	tar xzf llvm-project-$(LLVM_VER).src.tar.xz

# Configure
llvm-project-$(LLVM_VER).src/build/build.ninja:
	$(call log_info,preparing llvm ($(LLVM_VER)))
	mkdir llvm-project-$(LLVM_VER).src/build
	$(call log_info,configuring llvm ($(LLVM_VER)))
	cd llvm-project-$(LLVM_VER).src/build; \
	    cmake $(LLVM_CMAKE_FLAGS) ../llvm
	$(call log_info,patching configuration of llvm ($(LLVM_VER)))
	sed -i.bak 's/^HAVE_FFI_CALL:INTERNAL=/HAVE_FFI_CALL:INTERNAL=1/g' llvm-project-$(LLVM_VER).src/build/CMakeCache.txt

# Build
LLVM-iphoneos: llvm-project-$(LLVM_VER).src llvm-project-$(LLVM_VER).src/build/build.ninja
	$(call log_info,building llvm ($(LLVM_VER)))
	cmake --build llvm-project-$(LLVM_VER).src/build --target install

# Bundle
LLVM-iphoneos/llvm.a: LLVM-iphoneos
	$(call log_info,combining LLVM libraries into llvm.a)
	libtool -static -o LLVM-iphoneos/llvm.a LLVM-iphoneos/lib/*.a

LLVM.xcframework: LLVM-iphoneos/llvm.a
	$(call log_info,creating LLVM framework out of llvm ($(LLVM_VER)))
	xcodebuild -create-xcframework \
		-library "LLVM-iphoneos/llvm.a" \
	 	-headers "LLVM-iphoneos/include" \
	 	-output LLVM.xcframework

# Cleanup
clean:
	$(call log_info,cleaning up)
	rm -rf llvm*
	rm -rf LLVM-iphoneos
	rm -rf Release-iphoneos
	rm -rf *headers
	rm -rf *.xcframework

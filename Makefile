# Quick configurations
ROOT := $(PWD)
OS_VER := 13.0
LLVM_TAG := swift-6.3-RELEASE
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
all: LLVM.xcframework Clang.xcframework

# Fetch
$(LLVM_TAG).zip:
	$(call log_info,downloading llvm ($(LLVM_TAG)))
	wget https://github.com/swiftlang/llvm-project/archive/refs/tags/$(LLVM_TAG).zip

# Extract
llvm-project-$(LLVM_TAG): $(LLVM_TAG).zip
	$(call log_info,extracting llvm ($(LLVM_TAG)))
	unzip $(LLVM_TAG).zip

# Configure
llvm-project-$(LLVM_TAG)/build/build.ninja:
	$(call log_info,preparing llvm ($(LLVM_TAG)))
	mkdir  llvm-project-$(LLVM_TAG)/build
	$(call log_info,configuring llvm ($(LLVM_TAG)))
	cd llvm-project-$(LLVM_TAG)/build; \
	    cmake $(LLVM_CMAKE_FLAGS) ../llvm
	$(call log_info,patching configuration of llvm ($(LLVM_TAG)))
	sed -i.bak 's/^HAVE_FFI_CALL:INTERNAL=/HAVE_FFI_CALL:INTERNAL=1/g'  llvm-project-$(LLVM_TAG)/build/CMakeCache.txt

# Build
LLVM-iphoneos: llvm-project-$(LLVM_TAG) llvm-project-$(LLVM_TAG)/build/build.ninja
	$(call log_info,building llvm ($(LLVM_TAG)))
	cmake --build llvm-project-$(LLVM_TAG)/build --target install

# Bundle
LLVM-iphoneos/llvm.a: LLVM-iphoneos
	$(call log_info,combining LLVM libraries into llvm.a)
	libtool -static -o LLVM-iphoneos/llvm.a LLVM-iphoneos/lib/*.a

LLVM.xcframework: LLVM-iphoneos/llvm.a
	$(call log_info,creating LLVM framework out of llvm ($(LLVM_TAG)))
	mkdir llvm-headers
	cp -r LLVM-iphoneos/include/* llvm-headers/
	rm -rf llvm-headers/clang-c
	xcodebuild -create-xcframework \
		-library "LLVM-iphoneos/llvm.a" \
	 	-headers "llvm-headers" \
	 	-output LLVM.xcframework
	rm -rf llvm-headers

Clang.xcframework: LLVM-iphoneos
	$(call log_info,creating Clang framework out of llvm ($(LLVM_TAG)))
	mkdir clang-headers
	cp -r LLVM-iphoneos/include/clang-c clang-headers/
	xcodebuild -create-xcframework \
		-library "LLVM-iphoneos/lib/libclang.dylib" \
		-headers "clang-headers" \
		-output Clang.xcframework
	rm -rf clang-headers

# Cleanup
clean:
	$(call log_info,cleaning up)
	rm -rf llvm*
	rm -rf LLVM-iphoneos
	rm -rf Release-iphoneos
	rm -rf *headers
	rm -rf *.xcframework
	rm -rf swift*

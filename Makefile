# Makefile

ROOT := $(PWD)
LLVM_VER := 19.1.6
LLVM_CMAKE_FLAGS := -G "Ninja" \
					-DLLVM_ENABLE_PROJECTS="clang;lld" \
					-DLLVM_TARGETS_TO_BUILD="AArch64" \
					-DLLVM_TARGET_ARCH="AArch64" \
					-DLLVM_DEFAULT_TARGET_TRIPLE="arm64-apple-ios" \
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
					-DLLVM_ENABLE_FFI=ON \
					-DLLVM_DISABLE_ASSEMBLY_FILES=ON \
					-DFFI_INCLUDE_DIR="$(ROOT)/LIBFFI-iphoneos/include/ffi" \
					-DFFI_LIBRARY_DIR="$(ROOT)/LIBFFI-iphoneos" \
					-DCMAKE_BUILD_TYPE=MinSizeRel \
					-DCMAKE_INSTALL_PREFIX="$(ROOT)/LLVM-iphoneos" \
					-DCMAKE_TOOLCHAIN_FILE=../llvm/cmake/platforms/iOS.cmake \
					-DLLVM_ENABLE_LIBXML2=OFF \
					-DCLANG_ENABLE_STATIC_ANALYZER=OFF \
					-DCLANG_ENABLE_ARCMT=OFF \
					-DCLANG_TABLEGEN_TARGETS="AArch64" \
					-DLLVM_BUILD_LLVM_DYLIB=ON \
					-DLLVM_LINK_LLVM_DYLIB=ON \
					-DLLVM_TARGET_ARCH="arm64" \
					-DCMAKE_C_FLAGS="-target arm64-apple-ios14.0" \
					-DCMAKE_CXX_FLAGS="-target arm64-apple-ios14.0" \
					-DCMAKE_OSX_ARCHITECTURES=arm64

define log_info
	@echo "\033[32m\033[1m[*] \033[0m\033[32m$(1)\033[0m"
endef

all: LLVM.xcframework

libffi:
	$(call log_info,extracting libffi)
	tar xzf libffi.tar

LIBFFI-iphoneos: libffi
LIBFFI-iphoneos:
	$(call log_info,fixing libffi python script permissions)
	chmod +x libffi/generate-darwin-source-and-headers.py
	$(call log_info,building libffi)
	cd libffi; \
		./generate-darwin-source-and-headers.py --only-ios; \
		xcodebuild -scheme libffi-iOS -sdk iphoneos -configuration Release SYMROOT="$(PWD)"
	mv Release-iphoneos LIBFFI-iphoneos

llvm-project-$(LLVM_VER).src.tar.xz:
	$(call log_info,downloading llvm ($(LLVM_VER)))
	curl -OL https://github.com/llvm/llvm-project/releases/download/llvmorg-$(LLVM_VER)/llvm-project-$(LLVM_VER).src.tar.xz

llvm-project-$(LLVM_VER).src: llvm-project-$(LLVM_VER).src.tar.xz
	$(call log_info,extracting llvm ($(LLVM_VER)))
	tar xzf llvm-project-$(LLVM_VER).src.tar.xz

LLVM-iphoneos: LIBFFI-iphoneos llvm-project-$(LLVM_VER).src
	$(call log_info,preparing llvm ($(LLVM_VER)))
	rm -rf llvm-project-$(LLVM_VER).src/build
	mkdir llvm-project-$(LLVM_VER).src/build
	$(call log_info,configuring llvm ($(LLVM_VER)))
	cd llvm-project-$(LLVM_VER).src/build; \
		cmake $(LLVM_CMAKE_FLAGS) ../llvm
	$(call log_info,patching configuration of llvm ($(LLVM_VER)))
	sed -i.bak 's/^HAVE_FFI_CALL:INTERNAL=/HAVE_FFI_CALL:INTERNAL=1/g' llvm-project-$(LLVM_VER).src/build/CMakeCache.txt
	$(call log_info,building llvm ($(LLVM_VER)))
	cd llvm-project-$(LLVM_VER).src/build; \
		cmake --build . --target install

LLVM-iphoneos/llvm.a: LLVM-iphoneos
	$(call log_info,combining LLVM libraries into llvm.a)
	libtool -static -o LLVM-iphoneos/llvm.a \
		LLVM-iphoneos/lib/libLLVM*.a \
		LLVM-iphoneos/lib/libclang*.a \
		LLVM-iphoneos/lib/liblld*.a

LLVM.xcframework: LLVM-iphoneos/llvm.a
	 $(call log_info,creating framework out of llvm ($(LLVM_VER)))
	 tar -cJf libclang.tar.xz LLVM-iphoneos/lib/clang/
	 xcodebuild -create-xcframework \
	 	 -library "LLVM-iphoneos/llvm.a" \
	 	 -headers "LLVM-iphoneos/include" \
	 	 -output LLVM.xcframework

clean:
	$(call log_info,cleaning up)
	rm -rf libffi
	rm -rf libffi-iphoneos
	rm -rf llvm*
	rm -rf LLVM-iphoneos
	rm -rf Release-iphoneos
	rm -rf LIBFFI-iphoneos
	rm -rf libclang*

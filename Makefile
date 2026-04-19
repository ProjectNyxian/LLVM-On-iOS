# Quick configurations
ROOT := $(PWD)
OS_VER := 14.0
LLVM_ARCH := AArch64
APPLE_ARCH := arm64
SWIFT_SCHEME := swift-6.3.1-RELEASE
SWIFT_SUB_SCHEME := release/6.3.1

# Shared toolchain file (LLVM ships one, we reuse it for cmark and Swift too)
TOOLCHAIN_FILE := $(ROOT)/llvm-project/llvm/cmake/platforms/iOS.cmake

# LLVM + Clang + LLD
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
					-DCMAKE_TOOLCHAIN_FILE="$(TOOLCHAIN_FILE)" \
					-DLLVM_ENABLE_LIBXML2=OFF \
					-DCLANG_ENABLE_STATIC_ANALYZER=OFF \
					-DCLANG_ENABLE_ARCMT=OFF \
					-DCLANG_TABLEGEN_TARGETS="$(LLVM_ARCH)" \
					-DCMAKE_C_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_CXX_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_OSX_ARCHITECTURES="$(APPLE_ARCH)" \
					-DLLVM_FORCE_VC_REPOSITORY=https://github.com/swiftlang/llvm-project \
					-DLLVM_BUILD_UTILS=OFF \
					-DLLVM_INCLUDE_UTILS=OFF \
					-DLLVM_BUILD_BENCHMARKS=OFF \
					-DLLVM_INCLUDE_BENCHMARKS=OFF \
					-DLLVM_BUILD_TOOLS=OFF \
					-DCLANG_BUILD_TOOLS=ON \
					-DLLVM_INCLUDE_TESTS=OFF \
					-DLLVM_BUILD_TESTS=OFF

# cmark (needed by Swift's doc comment parser)
CMARK_CMAKE_FLAGS := -G "Ninja" \
					-DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_TOOLCHAIN_FILE="$(TOOLCHAIN_FILE)" \
					-DCMAKE_C_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_CXX_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_OSX_ARCHITECTURES="$(APPLE_ARCH)" \
					-DBUILD_TESTING=OFF \
					-DCMARK-GFM_STATIC=ON \
					-DCMARK-GFM_SHARED=OFF \
					-DCMARK-GFM_TESTS=OFF \
					-DCMAKE_INSTALL_PREFIX="$(ROOT)/cmark-iphoneos"

# Swift frontend libraries (no stdlib, no overlay, no SwiftCompilerSources)
SWIFT_CMAKE_FLAGS := -G "Ninja" \
					-DCMAKE_BUILD_TYPE=Release \
					-DCMAKE_TOOLCHAIN_FILE="$(TOOLCHAIN_FILE)" \
					-DCMAKE_OSX_ARCHITECTURES="$(APPLE_ARCH)" \
					-DCMAKE_C_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_CXX_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DBUILD_SHARED_LIBS=OFF \
					-DLLVM_DIR=$(ROOT)/LLVM-iphoneos/lib/cmake/llvm \
					-DClang_DIR=$(ROOT)/LLVM-iphoneos/lib/cmake/clang \
					-DLLD_DIR=$(ROOT)/LLVM-iphoneos/lib/cmake/lld \
					-DSWIFT_PATH_TO_CMARK_SOURCE=$(ROOT)/cmark \
					-DSWIFT_PATH_TO_CMARK_BUILD=$(ROOT)/cmark/build \
					-DSWIFT_BUILD_STDLIB=NO \
					-DSWIFT_BUILD_DYNAMIC_STDLIB=NO \
					-DSWIFT_BUILD_STATIC_STDLIB=NO \
					-DSWIFT_BUILD_SDK_OVERLAY=NO \
					-DSWIFT_BUILD_DYNAMIC_SDK_OVERLAY=NO \
					-DSWIFT_BUILD_STATIC_SDK_OVERLAY=NO \
					-DSWIFT_BUILD_REMOTE_MIRROR=NO \
					-DSWIFT_BUILD_SOURCEKIT=NO \
					-DSWIFT_BUILD_PERF_TESTSUITE=NO \
					-DSWIFT_BUILD_EXTERNAL_GENERIC_METADATA_BUILDER=NO \
					-DSWIFT_BUILD_RUNTIME_WITH_HOST_COMPILER=NO \
					-DSWIFT_INCLUDE_TOOLS=YES \
					-DSWIFT_INCLUDE_TESTS=NO \
					-DSWIFT_INCLUDE_DOCS=NO \
					-DSWIFT_INCLUDE_APINOTES=NO \
					-DBOOTSTRAPPING_MODE=HOSTTOOLS \
					-DCMAKE_Swift_COMPILER=$(shell xcrun -f swiftc) \
					-DSWIFT_NATIVE_SWIFT_TOOLS_PATH=$(shell dirname $(shell xcrun -f swiftc)) \
					-DSWIFT_HOST_VARIANT=iphoneos \
					-DSWIFT_HOST_VARIANT_SDK=IOS \
					-DSWIFT_HOST_VARIANT_ARCH=arm64 \
					-DSWIFT_PRIMARY_VARIANT_SDK=IOS \
					-DSWIFT_PRIMARY_VARIANT_ARCH=arm64 \
					-DSWIFT_SDKS="IOS" \
					-DLLVM_ENABLE_LIBXML2=OFF \
					-DLLVM_ENABLE_ZLIB=OFF \
					-DLLVM_ENABLE_ZSTD=OFF \
					-DLLVM_ENABLE_THREADS=ON \
					-DLLVM_ENABLE_UNWIND_TABLES=OFF \
					-DLLVM_ENABLE_EH=OFF \
					-DLLVM_ENABLE_RTTI=ON \
					-DLLVM_ENABLE_TERMINFO=OFF \
					-DCMAKE_INSTALL_PREFIX="$(ROOT)/Swift-iphoneos" \
					-DLLVM_DIR=$(ROOT)/llvm-project/build/lib/cmake/llvm \
					-DClang_DIR=$(ROOT)/llvm-project/build/lib/cmake/clang \
					-DLLD_DIR=$(ROOT)/llvm-project/build/lib/cmake/lld \
					-DLLVM_MAIN_SRC_DIR=$(ROOT)/llvm-project/llvm \
					-DLLVM_BUILD_MAIN_SRC_DIR=$(ROOT)/llvm-project/llvm \
					-DLLVM_BUILD_LIBRARY_DIR=$(ROOT)/llvm-project/build/lib \
					-DLLVM_LIBRARY_DIR=$(ROOT)/llvm-project/build/lib \
					-DLLVM_INCLUDE_DIR=$(ROOT)/llvm-project/build/include \
					-DLLVM_TOOLS_BINARY_DIR=$(ROOT)/llvm-project/build/bin \
					-DLLVM_BUILD_BINARY_DIR=$(ROOT)/llvm-project/build \
					-DSWIFT_NATIVE_LLVM_TOOLS_PATH=$(ROOT)/llvm-project/build/NATIVE/bin \
					-DSWIFT_NATIVE_CLANG_TOOLS_PATH=$(ROOT)/llvm-project/build/NATIVE/bin \
					-DLLVM_NATIVE_BUILD=$(ROOT)/llvm-project/build/NATIVE \
					-DCMAKE_Swift_FLAGS="-target $(APPLE_ARCH)-apple-ios$(OS_VER)" \
					-DCMAKE_SYSTEM_NAME=iOS \
					-DSWIFT_ENABLE_DISPATCH=NO \
					-DSWIFT_INCLUDE_DEPENDENCY_SCAN=NO \
					-DSWIFT_PATH_TO_SWIFT_SYNTAX_SOURCE=$(ROOT)/swift-syntax \
					-DSWIFT_BUILD_SWIFT_SYNTAX=ON \
					-DSWIFT_PATH_TO_STRING_PROCESSING_SOURCE=$(ROOT)/swift-experimental-string-processing

# Helper function
define log_info
	@echo "\033[32m\033[1m[*] \033[0m\033[32m$(1)\033[0m"
endef

# Main Target
all: LLVM.xcframework

# Fetching fuck ass Swift
.checkout-stamp:
	$(call log_info,cloning swift ($(SWIFT_SCHEME)))
	[ -d swift ] || git clone -b $(SWIFT_SCHEME) https://github.com/swiftlang/swift
	$(call log_info,disabling update-checkout 1800s timeout)
	sed -i.bak 's/timeout=1800/timeout=None/g' swift/utils/update_checkout/update_checkout/parallel_runner.py
	rm -f swift/utils/update_checkout/update_checkout/parallel_runner.py.bak
	cd swift && git -c user.email=build@local -c user.name=build commit -am "disable update-checkout timeout" || true
	$(call log_info,fetching matching llvm-project and cmark via update-checkout)
	./swift/utils/update-checkout --clone --scheme $(SWIFT_SUB_SCHEME) --skip-repository swift
	$(call log_info,pinning swift forcefully to $(SWIFT_SCHEME) ~~)
	cd swift && git fetch --tags && git checkout $(SWIFT_SCHEME)
	if [ -d swift-cmark ]; then mv swift-cmark cmark; fi
	$(call log_info,neutering swiftlang lld MachO refusal)
	perl -i -0pe 's|(// Swift LLVM fork downstream change start\n)(.*?)(// Swift LLVM fork downstream change end\n)|$$1/* NYXIAN: apple lies, lld works fine for MachO\n$$2*/\n$$3|s' \
	    llvm-project/lld/MachO/Driver.cpp
	touch $@

# Building apples mess
llvm-project/build/build.ninja: .checkout-stamp
	$(call log_info,preparing llvm)
	mkdir -p llvm-project/build
	$(call log_info,configuring llvm)
	cd llvm-project/build; \
	    cmake $(LLVM_CMAKE_FLAGS) ../llvm
	$(call log_info,patching configuration of llvm)
	sed -i.bak 's/^HAVE_FFI_CALL:INTERNAL=/HAVE_FFI_CALL:INTERNAL=1/g' llvm-project/build/CMakeCache.txt

LLVM-iphoneos: llvm-project/build/build.ninja
	$(call log_info,building llvm)
	cmake --build llvm-project/build --target install

# Another one of apples mess
cmark/build/build.ninja: .checkout-stamp LLVM-iphoneos
	$(call log_info,preparing cmark)
	mkdir -p cmark/build
	$(call log_info,configuring cmark)
	cd cmark/build; \
	    cmake $(CMARK_CMAKE_FLAGS) ..

cmark-iphoneos: cmark/build/build.ninja
	$(call log_info,building cmark)
	cmake --build cmark/build --target install

# Building the messiest project apple has ever created since they exist
swift/build/build.ninja: .checkout-stamp LLVM-iphoneos cmark-iphoneos
	$(call log_info,preparing swift)
	mkdir -p swift/build
	$(call log_info,configuring swift)
	cd swift/build; \
	    cmake $(SWIFT_CMAKE_FLAGS) ..

Swift-iphoneos: swift/build/build.ninja
	$(call log_info,building swift frontend libraries)
	cmake --build swift/build
	rm -rf Swift-iphoneos
	mkdir -p Swift-iphoneos/lib Swift-iphoneos/include
	cp swift/build/lib/*.a Swift-iphoneos/lib/
	$(call log_info,copying swift headers)
	cp -r swift/include/* Swift-iphoneos/include/
	for src in swift/include swift/build/include swift/stdlib/public/SwiftShims; do \
		cd $(ROOT)/$$src && find . \( -name "*.h" -o -name "*.inc" -o -name "*.def" \) -exec sh -c 'mkdir -p "$(ROOT)/Swift-iphoneos/include/$$(dirname {})" && cp "{}" "$(ROOT)/Swift-iphoneos/include/{}"' \; ; \
	done

# Bundling the messiest shit on planet earth
combined-headers: LLVM-iphoneos Swift-iphoneos
	$(call log_info,merging headers)
	mkdir -p combined-headers
	cp -R LLVM-iphoneos/include/. combined-headers/
	cp -R Swift-iphoneos/include/. combined-headers/

combined.a: LLVM-iphoneos cmark-iphoneos Swift-iphoneos
	$(call log_info,combining LLVM + cmark + Swift static libraries into combined.a)
	libtool -static -o combined.a \
	    LLVM-iphoneos/lib/*.a \
	    cmark-iphoneos/lib/*.a \
	    Swift-iphoneos/lib/*.a

LLVM.xcframework: combined.a combined-headers
	$(call log_info,creating LLVM.xcframework)
	xcodebuild -create-xcframework \
		-library "combined.a" \
		-headers "combined-headers" \
		-output LLVM.xcframework

# The best feeling is to have to delete all of
# Apples waste once your done /s
# Brain damage guranteed!
clean:
	$(call log_info,cleaning up)
	rm -rf llvm-project swift cmark
	rm -rf LLVM-iphoneos cmark-iphoneos Swift-iphoneos
	rm -rf combined.a combined-headers
	rm -rf *.xcframework
	rm -f .checkout-stamp
	rm -rf swift* cmake icu libxml2 ninja wasi-libc yams brotli curl indexstore-db llbuild sourcekit-lsp wasmkit zlib

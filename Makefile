# Quick configurations
ROOT := $(PWD)
OS_VER := 14.0
LLVM_ARCH := AArch64
APPLE_ARCH := arm64
TARGET_TRIPLE := $(APPLE_ARCH)-apple-ios$(OS_VER)
BUILD_DIR := build
SWIFT_BRANCH_SCHEME ?= release/6.3
SWIFT_PROJECT ?= ./SwiftProject
override SWIFT_PROJECT := $(abspath $(patsubst ~%,$(HOME)%,$(SWIFT_PROJECT)))
SWIFT_REPO_DIR := $(SWIFT_PROJECT)/swift
LLVM_REPO_DIR := $(SWIFT_PROJECT)/llvm-project
LLD_INPUT_FILES := $(LLVM_REPO_DIR)/lld/MachO/InputFiles.cpp
SWIFT_BUILD_ROOT := $(SWIFT_PROJECT)/build/LLVMClangSwift_iphoneos
SWIFT_LLVM_BUILD_DIR := $(SWIFT_BUILD_ROOT)/llvm-iphoneos-arm64
SWIFT_TOOLCHAIN_ZIP := SwiftToolchain.zip
SWIFT_TOOLCHAIN_ROOT := $(SWIFT_BUILD_ROOT)/swift-iphoneos-arm64
CMARK_IPHONEOS_DIR := $(SWIFT_BUILD_ROOT)/cmark-iphoneos-arm64
SWIFT_STATIC_LIBS := $(wildcard $(SWIFT_TOOLCHAIN_ROOT)/lib/libswift*.a) \
					 $(wildcard $(SWIFT_TOOLCHAIN_ROOT)/lib/lib_CompilerRegexParser.a)
CLANG_STATIC_LIBS := $(wildcard $(SWIFT_LLVM_BUILD_DIR)/lib/libclang*.a)
LLD_STATIC_LIBS := $(wildcard $(SWIFT_LLVM_BUILD_DIR)/lib/liblld*.a)
LLVM_STATIC_LIBS := $(wildcard $(SWIFT_LLVM_BUILD_DIR)/lib/libLLVM*.a)
CMARK_STATIC_LIBS := \
					 $(CMARK_IPHONEOS_DIR)/src/libcmark-gfm.a \
					 $(CMARK_IPHONEOS_DIR)/extensions/libcmark-gfm-extensions.a
SWIFT_HOST_COMPILER_DYLIBS := $(wildcard $(SWIFT_TOOLCHAIN_ROOT)/lib/swift/host/compiler/lib_Compiler*.dylib)
SWIFT_LINK_PATHS := -L$(SWIFT_TOOLCHAIN_ROOT)/lib \
					-L$(SWIFT_TOOLCHAIN_ROOT)/lib/swift/iphoneos \
					-L$(SWIFT_TOOLCHAIN_ROOT)/lib/swift/iphoneos/$(APPLE_ARCH) \
					-L$(SWIFT_TOOLCHAIN_ROOT)/lib/swift/host/compiler

# Helper function
define log_info
	@echo "\033[32m\033[1m[*] \033[0m\033[32m$(1)\033[0m"
endef

.PHONY: swift-project
swift-project:
	@set -e; \
	if [ ! -d "$(SWIFT_REPO_DIR)/.git" ]; then \
		echo "\033[32m\033[1m[*] \033[0m\033[32mpreparing Swift project\033[0m"; \
		mkdir -p "$(SWIFT_PROJECT)"; \
		git clone https://github.com/swiftlang/swift.git "$(SWIFT_REPO_DIR)"; \
	else \
		echo "\033[32m\033[1m[*] \033[0m\033[32mSwift project already exists\033[0m"; \
	fi; \
	if [ -d "$(LLVM_REPO_DIR)/.git" ]; then \
		git -C "$(LLVM_REPO_DIR)" checkout -- lld/MachO/InputFiles.cpp; \
	fi; \
	cd "$(SWIFT_REPO_DIR)" && utils/update-checkout --clone --scheme "$(SWIFT_BRANCH_SCHEME)" --source-root "$(SWIFT_PROJECT)"; \
	if [ -f "$(LLD_INPUT_FILES)" ]; then \
		perl -0pi -e 's|\n  // Swift LLVM fork downstream change start\n.*?\n  // Swift LLVM fork downstream change end\n||s' "$(LLD_INPUT_FILES)"; \
	fi

# Main Target
all: CoreCompiler.framework/CoreCompiler

CoreCompiler.framework/CoreCompiler: SDK := $(shell xcrun --sdk iphoneos --show-sdk-path)
CoreCompiler.framework/CoreCompiler: INC := -ISource \
	-I$(SWIFT_LLVM_BUILD_DIR)/include \
	-I$(SWIFT_LLVM_BUILD_DIR)/tools/clang/include \
	-I$(SWIFT_LLVM_BUILD_DIR)/tools/lld/include \
	-I$(LLVM_REPO_DIR)/llvm/include \
	-I$(LLVM_REPO_DIR)/clang/include \
	-I$(LLVM_REPO_DIR)/lld/include \
	-I$(SWIFT_TOOLCHAIN_ROOT)/include \
	-I$(SWIFT_REPO_DIR)/include
CoreCompiler.framework/CoreCompiler: | swift-project
	$(call log_info,building CoreCompiler framework)
	mkdir -p $(BUILD_DIR)
	-rm $(BUILD_DIR)/*.o
	for source in Source/CoreCompiler/*.c; do \
		clang -c -target $(TARGET_TRIPLE) -isysroot $(SDK) $(INC) "$$source" -o "$(BUILD_DIR)/$$(basename "$${source%.c}").c.o"; \
	done
	for source in Source/CoreCompiler/*.m; do \
		clang -c -fobjc-arc -ObjC -target $(TARGET_TRIPLE) -isysroot $(SDK) $(INC) "$$source" -o "$(BUILD_DIR)/$$(basename "$${source%.m}").m.o"; \
	done
	for source in Source/CoreCompiler/*.cpp; do \
		clang++ -c -std=c++17 -fno-rtti -target $(TARGET_TRIPLE) -isysroot $(SDK) $(INC) "$$source" -o "$(BUILD_DIR)/$$(basename "$${source%.cpp}").cpp.o"; \
	done
	clang++ -fobjc-arc -ObjC -target $(TARGET_TRIPLE) -isysroot $(SDK) $(SWIFT_LINK_PATHS) $(BUILD_DIR)/*.o $(CLANG_STATIC_LIBS) $(LLD_STATIC_LIBS) $(SWIFT_STATIC_LIBS) $(CMARK_STATIC_LIBS) $(LLVM_STATIC_LIBS) $(SWIFT_HOST_COMPILER_DYLIBS) -framework CoreFoundation -framework Foundation -lz -lxml2 -lswiftCore -o CoreCompiler.framework/CoreCompiler -shared -fPIC -install_name @rpath/CoreCompiler.framework/CoreCompiler
	-rm $(BUILD_DIR)/*.o
	-rm -rf CoreCompiler.framework/Headers
	mkdir -p CoreCompiler.framework/Headers
	cp Source/CoreCompiler/*.h CoreCompiler.framework/Headers/
	cp $(SWIFT_HOST_COMPILER_DYLIBS) CoreCompiler.framework/
	-install_name_tool -add_rpath @loader_path CoreCompiler.framework/CoreCompiler
	for dylib in CoreCompiler.framework/lib_Compiler*.dylib; do \
		install_name_tool -add_rpath @loader_path "$$dylib" || true; \
	done

# Cleanup
clean-artifacts:
	- rm -rf $(BUILD_DIR)
	- rm CoreCompiler.framework/CoreCompiler
	- rm CoreCompiler.framework/Headers/*
	- rm CoreCompiler.framework/lib_Compiler*.dylib
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

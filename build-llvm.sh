# Build LLVM XCFramework
#
# We assume that all required build tools (CMake, ninja, etc.) are either installed and accessible in $PATH.

# Assume that this script is source'd at this repo root
export REPO_ROOT=`pwd`

### Setup the environment variable $targetBasePlatform and $targetArch from the platform-architecture string
### Argument: the platform-architecture string, must be one of the following
###
###                 iphoneos iphonesimulator iphonesimulator-arm64 maccatalyst maccatalyst-arm64
###
### The base platform would be one of iphoneos iphonesimulator maccatalyst and the architecture
### would be either arm64 or x86_64.
setup_variables() {
    local targetPlatformArch=$1

    case $targetPlatformArch in
        "iphoneos")
            targetArch="arm64"
            targetBasePlatform="iphoneos";;

        "iphonesimulator")
            targetArch="x86_64"
            targetBasePlatform="iphonesimulator";;

        "iphonesimulator-arm64")
            targetArch="arm64"
            targetBasePlatform="iphonesimulator";;

        "maccatalyst")
            targetArch="x86_64"
            targetBasePlatform="maccatalyst";;

        "maccatalyst-arm64")
            targetArch="arm64"
            targetBasePlatform="maccatalyst";;

        *)
            echo "Unknown or missing platform!"
            exit 1;;
    esac
}

### Build libffi for a given platform
### Argument: the platform-architecture
build_libffi() {
    local targetPlatformArch=$1
    setup_variables $targetPlatformArch

    echo "Build libffi for $targetPlatformArch"

    cd $REPO_ROOT
    # local libffiReleaseSrcArchiveUrl=https://github.com/libffi/libffi/archive/refs/tags/v3.5.2.tar.gz
    # local libffiReleaseUrl=https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz
    # test -d libffi || git clone https://github.com/libffi/libffi.git
    # curl -L -o libffi.tar.gz $libffiReleaseSrcArchive
    #curl -L -o libffi.tar.gz $libffiReleaseUrl
    tar xzf libffi.tar
    cd libffi

    # Imitate libffi continuous integration .ci/build.sh script
    # Note that we do not need to run autogen if we are using the 'release' $libffiReleaseUrl as libffi dev already
    # runs it to generate configure script.
    # It is only needed when using the source archive $libffiReleaseSrcArchiveUrl (zipped repo at certain commit)
    # or when we build on the source repo.
    # ./autogen.sh

    # Getting the new and better python script
    cp $REPO_ROOT/fix.py generate-darwin-source-and-headers.py
    chmod +x generate-darwin-source-and-headers.py

    # Fixup execution permitives
    # chmod +x generate-darwin-source-and-headers.py

    # Do generate!
    ./generate-darwin-source-and-headers.py --only-ios

    case $targetPlatformArch in
        "iphoneos")
            xcodeSdkArgs=(-sdk $targetBasePlatform);;

        "iphonesimulator"|"iphonesimulator-arm64")
            xcodeSdkArgs=(-sdk $targetBasePlatform -arch $targetArch);;

        "maccatalyst"|"maccatalyst-arm64")
            xcodeSdkArgs=(-arch $targetArch);; # Do not set SDK

        *)
            echo "Unknown or missing platform!"
            exit 1;;
    esac

    # xcodebuild -list
    # Note that we need to run xcodebuild twice
    # The first run generates necessary headers whereas the second run actually compiles the library
    local libffiBuildDir=$REPO_ROOT/libffi
    for r in {1..2}; do
        xcodebuild -scheme libffi-iOS "${xcodeSdkArgs[@]}" -configuration Release SYMROOT="$libffiBuildDir" # >/dev/null 2>/dev/null
    done

    local libffiInstallDir=$libffiBuildDir/Release-$targetBasePlatform
    lipo -info $libffiInstallDir/libffi.a
    mv $libffiInstallDir $REPO_ROOT/libffi-$targetPlatformArch
}

get_llvm_src() {
    #git clone --single-branch --branch release/14.x https://github.com/llvm/llvm-project.git

    curl -OL https://github.com/llvm/llvm-project/releases/download/llvmorg-19.1.6/llvm-project-19.1.6.src.tar.xz
    tar xzf llvm-project-19.1.6.src.tar.xz
    mv llvm-project-19.1.6.src llvm-project
}

### Prepare the LLVM built for usage in Xcode
### Argument: the platform-architecture
prepare_llvm() {
    local targetPlatformArch=$1
    local libffiInstallDir=$REPO_ROOT/libffi-$targetPlatformArch

    echo "Prepare LLVM for $targetPlatformArch"
    cd $REPO_ROOT/LLVM-$targetPlatformArch

    # Copy libffi
    cp -r $libffiInstallDir/include/ffi ./include/
    cp $libffiInstallDir/libffi.a ./lib/

    # Combine all *.a into a single llvm.a for ease of use
    libtool -static -o llvm.a lib/*.a

    # This is to check if we find platform 1 (macOS desktop) in the mixed with platform 6 (macCatalyst).
    # This reveals that the assembly file blake3_sse41_x86-64_unix.S is not compiled for macCatalyst!
    # Looking at BLAKE3 https://github.com/llvm/clangir/blob/main/llvm/lib/Support/BLAKE3/CMakeLists.txt
    # reveals that we want to configure LLVM with LLVM_DISABLE_ASSEMBLY_FILES.
    otool -l llvm.a

    # Remove unnecessary lib files if packaging
    rm -rf lib/*.a
}

### Build LLVM for a given iOS platform
### Argument: the platform-architecture
### Assumptions:
###  * LLVM is checked out inside this repo
###  * libffi is built at libffi-[platform]
build_llvm() {
    local targetPlatformArch=$1
    local llvmProjectSrcDir=$REPO_ROOT/llvm-project
    local llvmInstallDir=$REPO_ROOT/LLVM-$targetPlatformArch
    local libffiInstallDir=$REPO_ROOT/libffi-$targetPlatformArch

    setup_variables $targetPlatformArch

    echo "Build llvm for $targetPlatformArch"

    cd $REPO_ROOT
    test -d llvm-project || get_llvm_src
    cd llvm-project
    rm -rf build
    mkdir build
    cd build

    # https://opensource.com/article/18/5/you-dont-know-bash-intro-bash-arrays
    # ;lld;libcxx;libcxxabi
    local llvmCmakeArgs=(
        # Main flags
        -G "Ninja"
        -DLLVM_ENABLE_PROJECTS="clang;lld"
        -DFFI_INCLUDE_DIR="$libffiInstallDir/include/ffi"
        -DFFI_LIBRARY_DIR="$libffiInstallDir"
        -DCMAKE_BUILD_TYPE=MinSizeRel
        -DCMAKE_INSTALL_PREFIX="$llvmInstallDir"
        -DCMAKE_TOOLCHAIN_FILE=../llvm/cmake/platforms/iOS.cmake
        -DLLVM_ENABLE_LIBXML2=OFF
        -DCLANG_ENABLE_STATIC_ANALYZER=OFF
        -DCLANG_ENABLE_ARCMT=OFF
        -DCLANG_TABLEGEN_TARGETS="AArch64"

        # Attempt to strip down support of other operating systems
        -DLLVM_INCLUDE_COFF=OFF
        -DLLVM_INCLUDE_ELF=OFF
        -DLLVM_INCLUDE_WASM=OFF

        # LLVM Related flags
        -DLLVM_ENABLE_RUNTIMES="libcxx;libcxxabi"
        -DLLVM_BUILD_32_BITS=OFF                            # iOS killed armv7 in iOS 11+
        -DLLVM_BUILD_BENCHMARKS=OFF                         # We dont need any benchmarks
        -DLLVM_BUILD_DOCS=OFF                               # We dont need any documentations
        -DLLVM_BUILD_EXAMPLES=OFF                           # We dont need any examples
        -DLLVM_BUILD_INSTRUMENTED_COVERAGE=OFF              # We dont need that either
        -DLLVM_BUILD_LLVM_DYLIB=OFF                         # For now off (might need that later tho)
        -DLLVM_BUILD_TESTS=OFF                              # We dont need any tests
        -DLLVM_BUILD_TOOLS=OFF                              # We dont need any tools, we utilise LLVM in nyxian customly
        -DLLVM_CCACHE_BUILD=OFF                             # Execution on iOS is prohibited
        -DLLVM_CREATE_XCODE_TOOLCHAIN=OFF                   # We dont need any executables, nyxian is compact
        -DLLVM_DEFAULT_TARGET_TRIPLE="arm64-apple-ios"      # Nyxian runs on iOS so I guess iOS??
        -DLLVM_DOXYGEN_SVG=OFF                              # We dont need that shit
        -DLLVM_ENABLE_ASSERTIONS=OFF                        # Dont need assertions
        -DLLVM_ENABLE_BINDINGS=OFF                          # We only need a compiler and linker
        -DLLVM_ENABLE_DIA_SDK=OFF                           # Fuck off microsoft
        -DLLVM_ENABLE_DOXYGEN=OFF                           # Nyxian aint for script kiddos
        -DLLVM_ENABLE_DOXYGEN_QT_HELP=OFF                   # Didnt you listen what I said
        -DLLVM_ENABLE_EH=ON                                 # We need to be reported about exceptions
        -DLLVM_ENABLE_EXPENSIVE_CHECKS=OFF                  # Do you know how much memory this costs?!
        -DLLVM_ENABLE_FFI=ON                                # Needed for the C++ lovers (Dont wanna know these people, they scare me)
        -DLLVM_ENABLE_HTTPLIB=OFF                           # Useless for nyxian
        -DLLVM_ENABLE_IDE=ON                                # YEAH LLVM pls
        -DLLVM_ENABLE_LIBCXX=OFF                            # Useless for nyxian
        -DLLVM_ENABLE_LIBPFM=OFF                            # Is linux only
        -DLLVM_ENABLE_LLD=ON                                # Useless, but i dont care
        -DLLVM_ENABLE_LLVM_LIBC=OFF                         # Useless for nyxian
        -DLLVM_ENABLE_LTO=Thin                              # Is smaller
        -DLLVM_ENABLE_MODULES=OFF                           # fuck off
        -DLLVM_ENABLE_PEDANTIC=ON                           # Everything needs to be correct still
        -DLLVM_ENABLE_PIC=ON                                # Apple is a fan of that
        -DLLVM_ENABLE_PROJECTS="clang;lld"                  # As I said, I need a compiler and a linker
        -DLLVM_ENABLE_RTTI=OFF                              # Might need that but later
        -DLLVM_ENABLE_RUNTIMES="libc;libcxx;libcxxabi"      # All we need
        -DLLVM_ENABLE_SPHINX=OFF                            # Are we in egypt??
        -DLLVM_ENABLE_THREADS=ON                            # We need thread-safe multithreaded building
        -DLLVM_ENABLE_UNWIND_TABLES=ON                      # We need to make sure everything works correctly
        -DLLVM_ENABLE_WARNINGS=ON                           # Warn me
        -DLLVM_ENABLE_WERROR=OFF                            # Dont do that shit
        -DLLVM_ENABLE_Z3_SOLVER=OFF                         # Not needed
        -DLLVM_ENABLE_ZLIB=OFF                              # Not needed
        -DLLVM_ENABLE_ZSTD=OFF                              # Not needed
        -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=""             # Not needed
        -DLLVM_EXTERNAL_PROJECTS=""                         # Not needed neither
        -DLLVM_EXTERNALIZE_DEBUGINFO=OFF                    # FOR DEBUG SUPPORT LATER
        -DLLVM_ENABLE_EXPORTED_SYMBOLS_IN_EXECUTABLES=OFF   # We dont need that but for the point before this one
        -DLLVM_FORCE_USE_OLD_TOOLCHAIN=OFF                  # Correctness on top!
        -DLLVM_INCLUDE_BENCHMARKS=OFF                       # We dont need benchmarks
        -DLLVM_INCLUDE_EXAMPLES=OFF                         # Dont need any examples
        -DLLVM_INCLUDE_TESTS=OFF                            # Not needed
        -DLLVM_INCLUDE_TOOLS=OFF                            # Not needed
        -DLLVM_INDIVIDUAL_TEST_COVERAGE=OFF                 # Not needed
        -DLLVM_INSTALL_BINUTILS_SYMLINKS=OFF                # Not needed
        -DLLVM_INSTALL_CCTOOLS_SYMLINKS=OFF                 # Not needed
        -DLLVM_INSTALL_UTILS=OFF                            # Not needed
        -DLLVM_ENABLE_RPMALLOC=OFF                          # Not needed
        -DLLVM_LINK_LLVM_DYLIB=OFF                          # Not needed for now
        -DLLVM_OPTIMIZED_TABLEGEN=ON                        # Important
        -DLLVM_TARGET_ARCH="AArch64"                        # Only iOS arm64
        -DLLVM_TARGETS_TO_BUILD="AArch64"                   # Only iOS arm64
        -DLLVM_TEMPORARILY_ALLOW_OLD_TOOLCHAIN=OFF          # Correctness on top!
        -DLLVM_UNREACHABLE_OPTIMIZE=ON                      # We need this
        -DLLVM_USE_INTEL_JITEVENTS=OFF                      # Dont need those overheating chips
        -DLLVM_USE_LINKER="lld"                             # I dont care
        -DLLVM_USE_OPROFILE=OFF                             # Dont need JIT
        -DLLVM_USE_PERF=OFF                                 # Dont need JIT
        -DLLVM_USE_RELATIVE_PATHS_IN_FILES=OFF              # Not needed
        -DLLVM_USE_RELATIVE_PATHS_IN_DEBUG_INFO=OFF         # Not needed
        -DLLVM_USE_SANITIZER=""                             # Not needed
        -DLLVM_USE_SPLIT_DWARF=OFF                          # Not needed
    )

    case $targetPlatformArch in
        "iphoneos")
            llvmCmakeArgs+=(-DLLVM_TARGET_ARCH=$targetArch \
                   -DCMAKE_C_FLAGS="-target $targetArch-apple-ios14.1" \
                   -DCMAKE_CXX_FLAGS="-target $targetArch-apple-ios14.1");;

        "iphonesimulator"|"iphonesimulator-arm64")
            llvmCmakeArgs+=(-DCMAKE_OSX_SYSROOT=$(xcodebuild -version -sdk iphonesimulator Path));;

        "maccatalyst"|"maccatalyst-arm64")
            llvmCmakeArgs+=(-DCMAKE_OSX_SYSROOT=$(xcodebuild -version -sdk macosx Path) \
                -DCMAKE_C_FLAGS="-target $targetArch-apple-ios14.1-macabi" \
                -DCMAKE_CXX_FLAGS="-target $targetArch-apple-ios14.1-macabi");;

        *)
            echo "Unknown or missing platform!"
            exit 1;;
    esac

    llvmCmakeArgs+=(-DCMAKE_OSX_ARCHITECTURES=$targetArch)

    # https://www.shell-tips.com/bash/arrays/
    # https://www.lukeshu.com/blog/bash-arrays.html
    printf 'CMake Argument: %s\n' "${llvmCmakeArgs[@]}"

    # Generate configuration for building for iOS Target (on MacOS Host)
    # Note: AArch64 = arm64
    # Note: We have to use include/ffi subdir for libffi as the main header ffi.h
    # includes <ffi_arm64.h> and not <ffi/ffi_arm64.h>. So if we only use
    # $DOWNLOADS/libffi/Release-iphoneos/include for FFI_INCLUDE_DIR
    # the platform-specific header would not be found!
    cmake "${llvmCmakeArgs[@]}" ../llvm || exit -1 # >/dev/null 2>/dev/null

    # When building for real iOS device, we need to open `build_ios/CMakeCache.txt` at this point, search for and FORCIBLY change the value of **HAVE_FFI_CALL** to **1**.
    # For some reason, CMake did not manage to determine that `ffi_call` was available even though it really is the case.
    # Without this, the execution engine is not built with libffi at all.
    sed -i.bak 's/^HAVE_FFI_CALL:INTERNAL=/HAVE_FFI_CALL:INTERNAL=1/g' CMakeCache.txt

    # Build and install
    cmake --build . --target install # >/dev/null 2>/dev/null

    prepare_llvm $targetPlatformArch
}

# Input: List of (base) platforms to be included in the XCFramework
# Argument: the list of platform-architectures to include in the framework
create_xcframework() {
    local xcframeworkSupportedPlatforms=("$@")

    # Construct xcodebuild arguments
    local xcodebuildCreateXCFArgs=()
    for p in "${xcframeworkSupportedPlatforms[@]}"; do
        xcodebuildCreateXCFArgs+=(-library LLVM-$p/llvm.a -headers LLVM-$p/include)

        cd $REPO_ROOT
        test -f libclang.tar.xz || echo "Create clang support headers archive" && tar -cJf libclang.tar.xz LLVM-$p/lib/clang/
    done

    echo "Create XC framework with arguments ${xcodebuildCreateXCFArgs[@]}"
    cd $REPO_ROOT
    xcodebuild -create-xcframework "${xcodebuildCreateXCFArgs[@]}" -output LLVM.xcframework
}

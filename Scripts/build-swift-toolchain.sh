#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SWIFT_SOURCE_DIR="${SWIFT_SOURCE_DIR:-${ROOT}/swift-source}"
SWIFT_BRANCH="${SWIFT_BRANCH:-swift-6.3-RELEASE}"
SWIFT_INSTALL_DIR="${SWIFT_INSTALL_DIR:-${ROOT}/SwiftToolchain-iphoneos}"
SWIFT_WORKSPACE_DIR="${SWIFT_WORKSPACE_DIR:-$(cd "${SWIFT_SOURCE_DIR}/.." 2>/dev/null && pwd || printf '%s' "${ROOT}")}"
SWIFT_BUILD_ROOT="${SWIFT_BUILD_ROOT:-${SWIFT_WORKSPACE_DIR}/build}"
SWIFT_BUILD_SUBDIR="${SWIFT_BUILD_SUBDIR:-LLVMClangSwift_iphoneos}"
SWIFT_PRESET_FILE="${SWIFT_PRESET_FILE:-${ROOT}/Scripts/swift-ios-toolchain-presets.ini}"
SWIFT_CROSS_PRESET="${SWIFT_CROSS_PRESET:-nyxian_iphoneos_arm64_crosscompiler}"
SWIFT_INSTALL_PREFIX="${SWIFT_INSTALL_PREFIX:-/usr}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-14.0}"
IOS_SDK_PATH="${IOS_SDK_PATH:-$(xcrun --sdk iphoneos --show-sdk-path)}"
IOS_TARGET_TRIPLE="${IOS_TARGET_TRIPLE:-arm64-apple-ios${IOS_DEPLOYMENT_TARGET}}"

log() {
    printf '\033[32m\033[1m[*]\033[0m\033[32m %s\033[0m\n' "$*"
}

die() {
    printf '\033[31m\033[1m[!]\033[0m\033[31m %s\033[0m\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 <command>

Commands:
  fetch         Clone/update swift-source using SWIFT_BRANCH.
  build         Build and install an iOS arm64 Swift compiler toolchain.
  package       Zip SwiftToolchain-iphoneos into SwiftToolchain.zip.
  install-nyxian
                Unpack SwiftToolchain.zip into ../Shared/SwiftToolchain.
  verify-host   Validate that the packaged toolchain shape exists.

Important environment:
  SWIFT_BRANCH=${SWIFT_BRANCH}
  SWIFT_SOURCE_DIR=${SWIFT_SOURCE_DIR}
  SWIFT_INSTALL_DIR=${SWIFT_INSTALL_DIR}
  SWIFT_BUILD_ROOT=${SWIFT_BUILD_ROOT}
  SWIFT_BUILD_SUBDIR=${SWIFT_BUILD_SUBDIR}
  SWIFT_PRESET_FILE=${SWIFT_PRESET_FILE}
  SWIFT_CROSS_PRESET=${SWIFT_CROSS_PRESET}
  IOS_DEPLOYMENT_TARGET=${IOS_DEPLOYMENT_TARGET}
  IOS_SDK_PATH=${IOS_SDK_PATH}
EOF
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

fetch_swift() {
    require_tool git
    if [[ ! -d "${SWIFT_SOURCE_DIR}/.git" ]]; then
        log "cloning swift ${SWIFT_BRANCH}"
        git clone --branch "${SWIFT_BRANCH}" --depth 1 https://github.com/swiftlang/swift.git "${SWIFT_SOURCE_DIR}"
    else
        log "updating existing swift checkout"
        git -C "${SWIFT_SOURCE_DIR}" fetch --depth 1 origin "${SWIFT_BRANCH}"
        git -C "${SWIFT_SOURCE_DIR}" checkout FETCH_HEAD
    fi

    log "updating Swift sibling checkouts for ${SWIFT_BRANCH}"
    "${SWIFT_SOURCE_DIR}/utils/update-checkout" --clone --tag "${SWIFT_BRANCH}"
}

# Ensures swift-source/CMakeLists.txt maps SWIFT_HOST_TRIPLE to
# CMAKE_Swift_COMPILER_TARGET before enable_language(Swift) runs. Without
# this, swiftc's compiler-probe at the iphoneos-arm64 stage is invoked
# without -target and defaults to the macOS host triple, mismatching the
# iPhoneOS sysroot and failing to load the stdlib.
patch_swift_cmake_triple() {
    require_tool python3

    local cmakelists="${SWIFT_SOURCE_DIR}/CMakeLists.txt"
    local sentinel='# nyxian: inject CMAKE_Swift_COMPILER_TARGET from SWIFT_HOST_TRIPLE'

    [[ -f "${cmakelists}" ]] || die "missing ${cmakelists}"

    if grep -qF "${sentinel}" "${cmakelists}"; then
        return 0
    fi

    log "patching swift CMakeLists.txt to map SWIFT_HOST_TRIPLE -> CMAKE_Swift_COMPILER_TARGET"

    python3 - "${cmakelists}" "${sentinel}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
sentinel = sys.argv[2]

text = path.read_text()
if sentinel in text:
    sys.exit(0)

inject = (
    f"{sentinel}\n"
    "if(DEFINED SWIFT_HOST_TRIPLE AND NOT CMAKE_Swift_COMPILER_TARGET)\n"
    "  set(CMAKE_Swift_COMPILER_TARGET \"${SWIFT_HOST_TRIPLE}\" CACHE STRING \"\")\n"
    "endif()\n\n"
)

new, count = re.subn(
    r'(^[ \t]*enable_language\(\s*Swift\b)',
    inject + r'\1',
    text,
    count=1,
    flags=re.MULTILINE,
)

if count == 0:
    sys.stderr.write("could not locate enable_language(Swift) in CMakeLists.txt\n")
    sys.exit(1)

path.write_text(new)
PY
}

build_swift() {
    require_tool cmake
    require_tool ninja
    require_tool xcrun

    [[ -x "${SWIFT_SOURCE_DIR}/utils/build-script" ]] || die "missing ${SWIFT_SOURCE_DIR}/utils/build-script; run make swift-source first"
    [[ -f "${SWIFT_PRESET_FILE}" ]] || die "missing Swift preset file at ${SWIFT_PRESET_FILE}"
    [[ -d "${IOS_SDK_PATH}" ]] || die "missing iPhoneOS SDK at ${IOS_SDK_PATH}"

    rm -rf "${SWIFT_INSTALL_DIR}"
    mkdir -p "${SWIFT_INSTALL_DIR}"

    log "building Swift toolchain for ${IOS_TARGET_TRIPLE}"
    log "this invokes Swift's build system; expect a long build"

    patch_swift_cmake_triple
    refresh_cmark_ios_cache

    (
        cd "${SWIFT_SOURCE_DIR}"
        utils/build-script --preset-file="${SWIFT_PRESET_FILE}" --preset="${SWIFT_CROSS_PRESET}"
    )

    copy_ios_install
    verify_host
}

refresh_cmark_ios_cache() {
    local cmark_build_dir="${SWIFT_BUILD_ROOT}/${SWIFT_BUILD_SUBDIR}/cmark-iphoneos-arm64"
    local cmark_cache="${cmark_build_dir}/CMakeCache.txt"

    if [[ -f "${cmark_cache}" ]] && ! grep -q '^BUILD_TESTING:BOOL=OFF$' "${cmark_cache}"; then
        log "refreshing cmark iPhoneOS CMake cache to disable test targets"
        rm -rf "${cmark_build_dir}"
    fi
}

copy_ios_install() {
    local build_dir="${SWIFT_BUILD_ROOT}/${SWIFT_BUILD_SUBDIR}"
    local install_prefix="Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr"
    local candidates=(
        "${build_dir}/intermediate-install/iphoneos-arm64/${install_prefix}"
        "${build_dir}/toolchain-macosx-arm64/${install_prefix}"
    )
    local swift_build="${build_dir}/swift-iphoneos-arm64"
    local llvm_build="${build_dir}/llvm-iphoneos-arm64"

    for candidate in "${candidates[@]}"; do
        if [[ -x "${candidate}/bin/swiftc" && -x "${candidate}/bin/swift-frontend" ]]; then
            rm -rf "${SWIFT_INSTALL_DIR}"
            mkdir -p "${SWIFT_INSTALL_DIR}"
            cp -a "${candidate}/." "${SWIFT_INSTALL_DIR}/"
            materialize_required_symlinks "${SWIFT_INSTALL_DIR}"
            log "copied iOS Swift toolchain from ${candidate}"
            return
        fi
    done

    if [[ -x "${swift_build}/bin/swiftc" && -x "${swift_build}/bin/swift-frontend" && -x "${llvm_build}/bin/clang" ]]; then
        rm -rf "${SWIFT_INSTALL_DIR}"
        mkdir -p "${SWIFT_INSTALL_DIR}/lib"

        copy_tree "${swift_build}/bin" "${SWIFT_INSTALL_DIR}/bin"
        copy_tree "${swift_build}/include" "${SWIFT_INSTALL_DIR}/include"
        copy_tree "${swift_build}/share" "${SWIFT_INSTALL_DIR}/share"
        copy_tree "${swift_build}/lib/swift" "${SWIFT_INSTALL_DIR}/lib/swift"
        copy_tree "${swift_build}/lib/cmake" "${SWIFT_INSTALL_DIR}/lib/cmake"
        copy_top_level_libs "${swift_build}/lib" "${SWIFT_INSTALL_DIR}/lib"

        copy_tree "${llvm_build}/bin" "${SWIFT_INSTALL_DIR}/bin"
        copy_tree "${llvm_build}/include" "${SWIFT_INSTALL_DIR}/include"
        copy_tree "${llvm_build}/lib/clang" "${SWIFT_INSTALL_DIR}/lib/clang"
        copy_tree "${llvm_build}/lib/cmake" "${SWIFT_INSTALL_DIR}/lib/cmake"
        copy_top_level_libs "${llvm_build}/lib" "${SWIFT_INSTALL_DIR}/lib"

        materialize_required_symlinks "${SWIFT_INSTALL_DIR}"
        log "assembled iOS Swift toolchain from ${swift_build} and ${llvm_build}"
        return
    fi

    die "could not find iOS Swift toolchain output under ${build_dir}"
}

copy_tree() {
    local source="$1"
    local destination="$2"

    if [[ -d "${source}" ]]; then
        mkdir -p "${destination}"
        cp -a "${source}/." "${destination}/"
    fi
}

copy_top_level_libs() {
    local source="$1"
    local destination="$2"

    if [[ -d "${source}" ]]; then
        find "${source}" -maxdepth 1 -type f \( -name '*.a' -o -name '*.dylib' -o -name '*.tbd' \) -exec cp -a {} "${destination}/" \;
    fi
}

materialize_required_symlinks() {
    local root="$1"
    local link_path
    local link_target
    local resolved_target
    local tmp_path
    local relative_path

    while IFS= read -r link_path; do
        link_target="$(readlink "${link_path}")"
        relative_path="${link_path#"${root}/"}"

        if [[ "${link_target}" != /* ]]; then
            case "${relative_path}" in
                bin/swift|bin/swiftc|bin/clang|bin/clang++|bin/clang-cpp)
                    ;;
                usr/bin/swift|usr/bin/swiftc|usr/bin/clang|usr/bin/clang++|usr/bin/clang-cpp)
                    ;;
                *)
                    continue
                    ;;
            esac
        fi

        if [[ "${link_target}" = /* ]]; then
            resolved_target="${link_target}"
        else
            resolved_target="$(cd "$(dirname "${link_path}")" && pwd)/${link_target}"
        fi

        [[ -e "${resolved_target}" ]] || die "symlink target does not exist: ${link_path} -> ${link_target}"
        tmp_path="${link_path}.materialized"
        rm -rf "${tmp_path}"
        cp -aL "${resolved_target}" "${tmp_path}"
        rm -f "${link_path}"
        mv "${tmp_path}" "${link_path}"
    done < <(find "${root}" -type l -print)
}

verify_host() {
    [[ -x "${SWIFT_INSTALL_DIR}/bin/swiftc" ]] || die "missing ${SWIFT_INSTALL_DIR}/bin/swiftc"
    [[ -x "${SWIFT_INSTALL_DIR}/bin/swift-frontend" ]] || die "missing ${SWIFT_INSTALL_DIR}/bin/swift-frontend"
    [[ -d "${SWIFT_INSTALL_DIR}/lib/swift" ]] || die "missing ${SWIFT_INSTALL_DIR}/lib/swift"
    log "toolchain shape is valid"
}

package_swift() {
    require_tool zip
    verify_host

    rm -rf "${ROOT}/SwiftToolchain"
    mkdir -p "${ROOT}/SwiftToolchain/usr"
    cp -a "${SWIFT_INSTALL_DIR}/." "${ROOT}/SwiftToolchain/usr/"
    materialize_required_symlinks "${ROOT}/SwiftToolchain"

    rm -f "${ROOT}/SwiftToolchain.zip"
    (
        cd "${ROOT}"
        zip -qry SwiftToolchain.zip SwiftToolchain
    )
    log "created ${ROOT}/SwiftToolchain.zip"
}

install_nyxian() {
    require_tool unzip
    [[ -f "${ROOT}/SwiftToolchain.zip" ]] || die "missing ${ROOT}/SwiftToolchain.zip; run make swift-toolchain first"

    local nyxian_shared="${NYXIAN_SHARED_DIR:-${ROOT}/../Shared}"
    [[ -d "${nyxian_shared}" ]] || die "missing Nyxian Shared directory at ${nyxian_shared}"

    rm -rf "${nyxian_shared}/SwiftToolchain"
    unzip -q "${ROOT}/SwiftToolchain.zip" -d "${nyxian_shared}"
    log "installed SwiftToolchain into ${nyxian_shared}/SwiftToolchain"
}

case "${1:-}" in
    fetch)
        fetch_swift
        ;;
    build)
        build_swift
        ;;
    package)
        package_swift
        ;;
    install-nyxian)
        install_nyxian
        ;;
    verify-host)
        verify_host
        ;;
    ""|-h|--help|help)
        usage
        ;;
    *)
        usage
        die "unknown command: $1"
        ;;
esac

#!/usr/bin/env python3
import subprocess
import os
import errno
import collections
import glob


class Platform(object):
    pass


class arm64_platform(Platform):
    arch = 'arm64'
    prefix = "#ifdef __arm64__\n\n"
    suffix = "\n\n#endif"
    src_dir = 'aarch64'
    src_files = ['sysv.S', 'ffi.c', 'internal.h']


class ios_simulator_arm64_platform(arm64_platform):
    target = 'aarch64-apple-darwin'
    directory = 'darwin_ios'
    sdk = 'iphonesimulator'
    version_min = '-miphoneos-version-min=12.0'


class ios_device_arm64_platform(arm64_platform):
    target = 'aarch64-apple-darwin'
    directory = 'darwin_ios'
    sdk = 'iphoneos'
    version_min = '-miphoneos-version-min=12.0'


def mkdir_p(path):
    try:
        os.makedirs(path)
    except OSError as exc:
        if exc.errno != errno.EEXIST:
            raise


def move_file(src_dir, dst_dir, filename, file_suffix=None, prefix='', suffix=''):
    mkdir_p(dst_dir)
    out_filename = filename

    if file_suffix:
        if filename in ['internal64.h', 'asmnames.h', 'internal.h']:
            out_filename = filename
        else:
            split_name = os.path.splitext(filename)
            out_filename = "%s_%s%s" % (split_name[0], file_suffix, split_name[1])

    with open(os.path.join(src_dir, filename)) as in_file:
        with open(os.path.join(dst_dir, out_filename), 'w') as out_file:
            if prefix:
                out_file.write(prefix)
            out_file.write(in_file.read())
            if suffix:
                out_file.write(suffix)


def list_files(src_dir, pattern=None, filelist=None):
    if pattern:
        filelist = glob.iglob(os.path.join(src_dir, pattern))
    for file in filelist:
        yield os.path.basename(file)


def copy_files(src_dir, dst_dir, pattern=None, filelist=None, file_suffix=None, prefix=None, suffix=None):
    for filename in list_files(src_dir, pattern=pattern, filelist=filelist):
        move_file(src_dir, dst_dir, filename, file_suffix=file_suffix, prefix=prefix, suffix=suffix)


def copy_src_platform_files(platform):
    src_dir = os.path.join('src', platform.src_dir)
    dst_dir = os.path.join(platform.directory, 'src', platform.src_dir)
    copy_files(src_dir, dst_dir, filelist=platform.src_files, file_suffix=platform.arch, prefix=platform.prefix, suffix=platform.suffix)


def build_target(platform, platform_headers):
    def xcrun_cmd(cmd):
        return 'xcrun -sdk %s %s' % (platform.sdk, cmd)

    tag = '%s-%s' % (platform.sdk, platform.arch)
    build_dir = 'build_%s' % tag
    mkdir_p(build_dir)
    env = dict(
        CC=xcrun_cmd('clang'),
        LD=xcrun_cmd('ld'),
        CFLAGS='%s -arch arm64' % (platform.version_min)
    )
    working_dir = os.getcwd()
    try:
        os.chdir(build_dir)
        subprocess.check_call(
            ["../configure", "--host=aarch64-apple-darwin"],
            env=env
        )
    finally:
        os.chdir(working_dir)

    for src_dir in [build_dir, os.path.join(build_dir, 'include')]:
        copy_files(
            src_dir,
            os.path.join(platform.directory, 'include'),
            pattern='*.h',
            file_suffix=platform.arch,
            prefix=platform.prefix,
            suffix=platform.suffix
        )

        for filename in list_files(src_dir, pattern='*.h'):
            platform_headers[filename].add((platform.prefix, platform.arch, platform.suffix))


def generate_source_and_headers():
    print("Generating source and headers for ARM64 iOS only...")
    
    # Copy common files
    copy_files('src', 'darwin_common/src', pattern='*.c')
    copy_files('include', 'darwin_common/include', pattern='*.h')

    # Copy platform-specific source files (ARM64 only)
    print("Copying platform source files...")
    copy_src_platform_files(ios_simulator_arm64_platform)
    copy_src_platform_files(ios_device_arm64_platform)

    platform_headers = collections.defaultdict(set)

    # Build targets (ARM64 only)
    print("Building iOS Simulator ARM64...")
    build_target(ios_simulator_arm64_platform, platform_headers)
    
    print("Building iOS Device ARM64...")
    build_target(ios_device_arm64_platform, platform_headers)

    # Generate combined headers
    print("Generating combined headers...")
    mkdir_p('darwin_common/include')
    for header_name, tag_tuples in platform_headers.items():
        basename, suffix = os.path.splitext(header_name)
        with open(os.path.join('darwin_common/include', header_name), 'w') as header:
            for tag_tuple in tag_tuples:
                header.write('%s#include <%s_%s%s>\n%s\n' % (tag_tuple[0], basename, tag_tuple[1], suffix, tag_tuple[2]))

    print("Done! Generated ARM64-only iOS libffi headers and sources.")


if __name__ == '__main__':
    generate_source_and_headers()

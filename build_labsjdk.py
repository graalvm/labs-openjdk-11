#!/usr/bin/env python3 -u
#
# ----------------------------------------------------------------------------------------------------
#
# Copyright (c) 2019, Oracle and/or its affiliates. All rights reserved.
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
#
# This code is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License version 2 only, as
# published by the Free Software Foundation.
#
# This code is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# version 2 for more details (a copy is included in the LICENSE file that
# accompanied this code).
#
# You should have received a copy of the GNU General Public License version
# 2 along with this work; if not, write to the Free Software Foundation,
# Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
#
# Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
# or visit www.oracle.com if you need additional information or have any
# questions.
#
# ----------------------------------------------------------------------------------------------------

"""
Utility for building a labsjdk-ce-11 binary from the sources in this repo.

$ ./build_labsjdk.py --clean-after-build

This script assumes all the necessary build dependencies are installed.
See: https://wiki.openjdk.java.net/display/Build/Supported+Build+Platforms
"""
from __future__ import print_function

import zipfile
import tarfile
import os
import stat
import glob
import shutil
import pipes
import time
import subprocess
import sys
import re
import platform

from os.path import join, exists, isdir, basename, abspath, dirname, getsize
from argparse import ArgumentParser
from datetime import timedelta

# Temporary imports and (re)definitions to support Python 2 and Python 3
if sys.version_info[0] < 3:
    def _decode(x):
        return x
    def _encode(x):
        return x
else:
    def _decode(x):
        return x.decode()
    def _encode(x):
        return x.encode()

def abort(code_or_message):
    raise SystemExit(code_or_message)

def timestamp():
    return time.strftime('%Y-%m-%d %H:%M:%S')

def human_fmt(num):
    for unit in ['', 'K', 'M', 'G']:
        if abs(num) < 1024.0:
            return "%3.1f%sB" % (num, unit)
        num /= 1024.0
    return "%.1fTB" % (num)

def log(msg):
    if hasattr(shutil, 'disk_usage'):
        total, _, free = shutil.disk_usage('.')
        print('{} [{} of {} free]: {}'.format(timestamp(), human_fmt(free), human_fmt(total), str(msg)))
    else:
        print('{}: {}'.format(timestamp(), str(msg)))

def log_call(args, **kwargs):
    cwd = kwargs.get('cwd')
    if cwd:
        log('(in directory {})'.format(cwd))
    log(' '.join(map(pipes.quote, args)))

def check_call(args, **kwargs):
    log_call(args, **kwargs)
    return subprocess.check_call(args, **kwargs)

def call(args, **kwargs):
    log_call(args, **kwargs)
    return subprocess.call(args, **kwargs)

def check_output(args, **kwargs):
    log_call(args, **kwargs)
    return _decode(subprocess.check_output(args, **kwargs))

def get_java_version(version_numbers_file):
    values = {}
    with open(version_numbers_file) as fp:
        for l in fp:
            line = l.strip()
            if line and not line.startswith('#'):
                key, value = [e.strip() for e in line.split('=', 1)]
                values[key] = value
    return '{}.{}.{}'.format(values['DEFAULT_VERSION_FEATURE'], values['DEFAULT_VERSION_INTERIM'], values['DEFAULT_VERSION_UPDATE'])

def create_bundle(input_bundles, bundle, jdk_debug_level, install_prefix, extract=False, clean_install_dir=False):
    """
    Creates a gzipped tar in `bundle` composed of the contents in `input_bundles`.
    The top level directory in the gzipped tar will be `install_prefix`.
    The gzipped tar is extracted in the parent directory of `bundle` if `extract` is `True`.
    """
    tmp_dir = bundle + '-' + str(os.getpid())
    rmtree(tmp_dir)
    os.makedirs(tmp_dir)
    def get_root(names, path, expected=None):
        names = [n[2:] if n.startswith('./') else n for n in names if n not in ['.', './']]
        roots = set([n.split('/', 1)[0] for n in names])
        assert len(roots) == 1, '{} contains {} roots: {}'.format(path, len(roots), roots)
        root = next(iter(roots))
        assert expected is None or root == expected, 'expected single root in {} to be {} but was {}'.format(path, expected, root)
        return root

    root_name = None
    for input_bundle in input_bundles:
        log('Extracting {}'.format(input_bundle))
        if input_bundle.endswith('.zip'):
            with zipfile.ZipFile(input_bundle) as zf:
                root_name = get_root(zf.namelist(), input_bundle, root_name)
                zf.extractall(tmp_dir)
        else:
            with tarfile.open(input_bundle, 'r:gz') as tf:
                root_name = get_root(tf.getnames(), input_bundle, root_name)
                tf.extractall(tmp_dir)
        os.remove(input_bundle)

    root_dir = join(tmp_dir, root_name)
    if jdk_debug_level == 'fastdebug':
        if 'darwin' in bundle:
            contents_dir = join(root_dir, 'Contents')
            os.makedirs(contents_dir)
            os.rename(join(root_dir, 'fastdebug'), join(contents_dir, 'Home'))
        else:
            for e in glob.glob(join(root_dir, 'fastdebug', '*')):
                os.rename(e, join(root_dir, basename(e)))
            os.rmdir(join(root_dir, 'fastdebug'))

    def on_error(err):
        raise err
    log('Archiving {}'.format(bundle))
    with tarfile.open(bundle, 'w:gz') as tf:
        for root, _, filenames in os.walk(root_dir, onerror=on_error):
            for name in filenames:
                f = join(root, name)
                # Make sure files in the image are readable by everyone
                file_mode = os.stat(f).st_mode
                mode = stat.S_IRGRP | stat.S_IROTH | file_mode
                if isdir(f) or (file_mode & stat.S_IXUSR):
                    mode = mode | stat.S_IXGRP | stat.S_IXOTH
                os.chmod(f, mode)
                arcname = install_prefix + '/' + os.path.relpath(f, root_dir)
                tf.add(name=f, arcname=arcname, recursive=False)
    rmtree(tmp_dir)
    if clean_install_dir:
        rmtree(join(dirname(bundle), install_prefix))
    if extract:
        with tarfile.open(bundle, 'r:gz') as tf:
            log('Extracting {}'.format(bundle))
            tf.extractall(dirname(bundle))

def get_os():
    p = sys.platform
    if p.startswith('darwin'):
        return 'darwin'
    if p.startswith('linux'):
        return 'linux'
    if p.startswith('sunos'):
        return 'solaris'
    if p.startswith('win32') or p.startswith('cygwin'):
        return 'windows'
    abort('Unknown operating system ' + sys.platform)

def get_arch():
    machine = platform.uname()[4]
    if machine in ['aarch64']:
        return 'aarch64'
    if machine in ['amd64', 'AMD64', 'x86_64', 'i86pc']:
        return 'amd64'
    if machine in ['sun4v', 'sun4u', 'sparc64']:
        return 'sparcv9'
    abort('unknown or unsupported architecture: os=' + get_os() + ', machine=' + machine)

def rmtree(path, ignore_errors=False):
    if not exists(path):
        return
    if get_os() == 'windows':
        # https://stackoverflow.com/questions/1889597/deleting-directory-in-python
        def on_error(func, _path, exc_info):
            os.chmod(_path, stat.S_IWRITE)
            func(_path)
    else:
        on_error = None
    log('Removing ' + path)
    shutil.rmtree(path, onerror=on_error)

def get_jvmci_version_from_tags(repo):
    tags = check_output(['git', '-C', repo, 'tag']).split()
    jvmci_re = re.compile(r'jvmci-(\d+)\.(\d+)-b(\d+)')

    tags = [t for t in tags if jvmci_re.match(t)]
    if not tags:
        return None
    tags = [jvmci_re.match(t).group(1, 2, 3) for t in tags]
    latest = sorted(tags, reverse=True)[0]
    version = '{}.{}-b{:02d}'.format(latest[0], latest[1], int(latest[2]))

    # Bump the build number in the version and add a "-dev" suffix if
    # the current working directory has modified files or if its
    # commit hash is not equal to the commit hash of the selected jvmci tag
    latest_commit = check_output(['git', '-C', repo, 'show', '--pretty=%H', '-s', 'jvmci-' + version])
    head_commit = check_output(['git', '-C', repo, 'show', '--pretty=%H', '-s'])
    is_dirty = check_output(['git', '-C', repo, 'status', '--untracked-files=no', '--porcelain']) != ''
    if is_dirty or latest_commit != head_commit:
        return '{}.{}-b{:02d}-dev'.format(latest[0], latest[1], int(latest[2]) + 1)
    return version

def main():
    env = os.environ
    parser = ArgumentParser()
    parser.add_argument('--make', action='store', help='GNU make executable', default=env.get('MAKE', 'make'), metavar='<path>')
    parser.add_argument('--boot-jdk', action='store', help='value for --boot-jdk configure option (default: $JAVA_HOME)',
                        default=env.get('JAVA_HOME'), required='JAVA_HOME' not in env, metavar='<path>')
    parser.add_argument('--clean-after-build', action='store_true', help='clean build directory after producing labsjdk binaries')
    parser.add_argument('--jdk-debug-level', action='store', help='value for --with-debug-level JDK config option', default='release', choices=['release', 'fastdebug'])
    parser.add_argument('--devkit', action='store', help='value for --with-devkit configure option', default=env.get('DEVKIT', ''), metavar='<path>')
    parser.add_argument('--jvmci-version', action='store', help='JVMCI version (e.g., 19.3-b03)', metavar='<version>')

    opts = parser.parse_args()
    build_os = get_os()
    build_arch = get_arch()

    jdk_debug_level = opts.jdk_debug_level
    jdk_src_dir = abspath(dirname(__file__))
    jvmci_version = opts.jvmci_version or get_jvmci_version_from_tags(jdk_src_dir)

    if not jvmci_version:
        abort('Could not derive JVMCI version from git tags - please specify it with --jvmci-version option')
    build_dir = join(jdk_src_dir, 'build')
    labsjdks_dir = join(build_dir, 'labsjdks')
    target_dir = join(labsjdks_dir, jdk_debug_level)

    if not exists(target_dir):
        os.makedirs(target_dir)

    version_numbers_file = join(jdk_src_dir, 'make', 'autoconf', 'version-numbers')
    java_version = get_java_version(version_numbers_file)

    tag_prefix = 'jdk-' + java_version + '+'
    build_nums = [int(line[len(tag_prefix):]) for line in check_output(['git', '-C', jdk_src_dir, 'tag']).split() if line.startswith(tag_prefix)]
    build_num = sorted(build_nums, reverse=True)[0]

    debug_qualifier = '' if jdk_debug_level == 'release' else '-debug'
    jdk_bundle_prefix = 'labsjdk-ce-{}+{}-jvmci-{}{}'.format(java_version, build_num, jvmci_version, debug_qualifier)
    install_prefix = 'labsjdk-ce-{}-jvmci-{}{}'.format(java_version, jvmci_version, debug_qualifier)
    jdk_bundle_name = jdk_bundle_prefix + '-{}-{}.tar.gz'.format(build_os, build_arch)
    jdk_bundle = join(target_dir, jdk_bundle_name)
    conf_name = build_os + '-' + build_arch + debug_qualifier

    # zlib should only be bundled on Windows
    zlib_bundling = 'bundled' if build_os == 'windows' else 'system'

    configure_options = [
        "--with-debug-level=" + jdk_debug_level,
        "--enable-aot=no", # HotSpot AOT is omitted from labsjdk
        "--with-jvm-features=graal",
        "--with-jvm-variants=server",
        "--with-conf-name=" + conf_name,
        "--with-boot-jdk=" + opts.boot_jdk,
        "--with-devkit=" + opts.devkit,
        "--with-zlib=" + zlib_bundling,
        "--with-version-build=" + str(build_num),
        "--with-version-opt=" + "jvmci-" + jvmci_version,
        "--with-version-pre="
    ]
    if build_arch != 'aarch64':
        configure_options.append("--disable-precompiled-headers")

    check_call(["sh", "configure"] + configure_options, cwd=jdk_src_dir)
    check_call([opts.make, "LOG=info", "CONF=" + conf_name, "product-bundles", "static-libs-bundles"], cwd=jdk_src_dir)

    bundles_dir = join(build_dir, conf_name, 'bundles')

    if opts.clean_after_build:
        new_bundles_dir = join(labsjdks_dir, jdk_debug_level + '-bundles')
        rmtree(new_bundles_dir)
        os.rename(bundles_dir, new_bundles_dir)
        bundles_dir = new_bundles_dir
        check_call(['du', '-sh', build_dir])
        for e in os.listdir(build_dir):
            check_call(['du', '-sh', join(build_dir, e)])
        rmtree(join(build_dir, conf_name))
        check_call(['find', build_dir])
        check_call(['rm', '-rf', join(build_dir, conf_name)])
        check_call(['du', '-sh', build_dir])
        check_call(['find', build_dir])

    # Create labsjdk bundles and image
    jdk_bundle_ext = '.zip' if 'windows' in conf_name else '.tar.gz'
    input_bundles = glob.glob(join(bundles_dir, '*_bin' + debug_qualifier + jdk_bundle_ext)) + \
                    glob.glob(join(bundles_dir, '*_bin-static-libs' + debug_qualifier + '.tar.gz'))
    input_symbols_bundles = glob.glob(join(bundles_dir, '*_bin' + debug_qualifier + '-symbols.tar.gz'))
    create_bundle(input_bundles, jdk_bundle, jdk_debug_level, install_prefix, extract=True, clean_install_dir=True)
    if input_symbols_bundles:
        symbols_bundle = jdk_bundle.replace('.tar.gz', '.symbols.tar.gz')
        create_bundle(input_symbols_bundles, symbols_bundle, jdk_debug_level, install_prefix)
    else:
        symbols_bundle = None

    if opts.clean_after_build:
        rmtree(bundles_dir)

    java_home = join(target_dir, install_prefix)
    if build_os == 'darwin':
        java_home = join(java_home, 'Contents', 'Home')
    java_exe = join(java_home, 'bin', 'java')
    if build_os == 'windows':
        java_exe += '.exe'
    check_call([java_exe, "-version"])

    log('--- Build Succeeded ---')
    log('JDK bundle: {} [{}]'.format(jdk_bundle, human_fmt(getsize(jdk_bundle))))
    if symbols_bundle:
        log('Symbols bundle: {} [{}]'.format(symbols_bundle, human_fmt(getsize(symbols_bundle))))

if __name__ == '__main__':
    start = time.time()
    try:
        main()
    finally:
        duration = time.time() - start
        log('Total build time: {}'.format(timedelta(seconds=duration)))

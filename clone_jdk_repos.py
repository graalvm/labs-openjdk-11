#
# ----------------------------------------------------------------------------------------------------
#
# Copyright (c) 2016, Oracle and/or its affiliates. All rights reserved.
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

#pylint: disable=missing-docstring
#pylint: disable=line-too-long
#pylint: disable=invalid-name

import os, subprocess, shutil, time, datetime, urllib2, pipes, sys, rfc822
from os.path import join, exists, isdir, relpath, dirname
from argparse import ArgumentParser

def timestamp():
    return time.strftime('%Y-%m-%d %H:%M:%S')

def log(msg):
    print timestamp() + ': ' + str(msg)

def check_call(args):
    log(' '.join(map(pipes.quote, args)))
    return subprocess.check_call(args)

def check_output(args):
    log(' '.join(map(pipes.quote, args)))
    return subprocess.check_output(args)

def ensure_dir_exists(path, mode=None):
    """
    Ensures all directories on 'path' exists, creating them first if necessary with os.makedirs().
    """
    if not isdir(path):
        try:
            if mode:
                os.makedirs(path, mode=mode)
            else:
                os.makedirs(path)
        except OSError as e:
            if e.errno == errno.EEXIST and isdir(path):
                # be happy if another thread already created the path
                pass
            else:
                raise e
    return path

def apply_patch_for_bug(repo, bugid, patchURL=None):
    output = check_output(['hg', '-R', repo, 'log', '-k', bugid, '--template', '{desc|short}'])
    log('Patch ' + bugid + ' query output: ' + output)
    if not output.startswith(bugid):
        # Bug not in jdk yet - apply patch
        patch = bugid + '.patch'
        if patchURL:
            log('Downloading {} to {} ...'.format(patchURL, patch))
            with open(patch, 'w') as fp:
                fp.write(urllib2.urlopen(patchURL).read())
        check_call(['hg', '-R', repo, 'import', '-f', '--no-commit', patch])
        log('Applied patch for ' + bugid)
    else:
        log('No patching required for ' + bugid)

def create_or_update_mirror(url, mirror, revision):
    if not exists(mirror):
        log('Creating {} mirror at {}'.format(url, mirror))
        if url.startswith('ssh://git'):
            check_call(['git', 'clone', url, mirror])
            check_call(['git', '-C', mirror, 'checkout', revision])
        else:
            check_call(['hg', 'clone', url, mirror])
            check_call(['hg', '--cwd', mirror, 'update', '--rev', revision])
    else:
        log('Updating {} mirror at {}'.format(url, mirror))
        if url.startswith('ssh://git'):
            check_call(['git', '-C', mirror, 'clean', '-dxf', '.'])
            check_call(['git', '-C', mirror, 'fetch', revision])
            check_call(['git', '-C', mirror, 'checkout', revision])
            # make sure any local changes are overwritten by the upstream branch
            check_call(['git', '-C', mirror, 'reset', '--hard', '@{u}'])
        else:
            check_call(['hg', '--cwd', mirror, 'pull'])
            check_call(['hg', '--cwd', mirror, 'update', '--clean', '--rev', revision])
            check_call(['hg', '--cwd', mirror, '--config', 'extensions.purge=', 'purge', '-X', 'open', '--all'])

def rename_packages(package_renamings, directory):
    for old_name, new_name in package_renamings.iteritems():
        file_moves = {}
        log('Replacing {} with {}'.format(old_name, new_name))
        for dirpath, _, filenames in os.walk(directory):
            for filename in filenames:
                if filename.endswith('.java'):
                    filepath = join(dirpath, filename)
                    old_name_as_dir = old_name.replace('.', os.sep)
                    if old_name_as_dir in filepath:
                        new_name_as_dir = new_name.replace('.', os.sep)
                        dst = filepath.replace(old_name_as_dir, new_name_as_dir)
                        file_moves[filepath] = dst
                    with open(filepath) as fp:
                        contents = fp.read()
                        new_contents = contents.replace(old_name, new_name)
                    if contents != new_contents:
                        log('  updating ' + relpath(filepath, directory))
                        with open(filepath, 'w') as fp:
                            fp.write(new_contents)

        for src, dst in file_moves.iteritems():
            dst_dir = dirname(dst)
            if not exists(dst_dir):
                os.makedirs(dst_dir)
            log('  moving {} to {}'.format(src, dst))
            shutil.move(src, dst)

if __name__ == '__main__':
    parser = ArgumentParser()
    parser.add_argument('name', help='root directory name')
    parser.add_argument('cache', help='CI cache directory')
    parser.add_argument('open_url', help='URL of the open jdk repo')
    parser.add_argument('open_revision', help='revision of the open jdk repo to update to')
    parser.add_argument('closed_url', help='URL of the closed jdk repo')
    parser.add_argument('closed_revision', help='revision of the closed jdk repo to update to')
    opts = parser.parse_args()

    # Clean up legacy mirror
    legacy_mirror = join(ensure_dir_exists(opts.cache), 'jdk-hs')
    if exists(legacy_mirror):
        log('Removing legacy mirror ' + legacy_mirror)
        shutil.rmtree(legacy_mirror)

    mirror = join(ensure_dir_exists(opts.cache), opts.name)
    create_or_update_mirror(opts.closed_url, mirror, opts.closed_revision)
    create_or_update_mirror(opts.open_url, join(mirror, 'open'), opts.open_revision)

    # Copy mirror to current directory
    toplevel = set([join(mirror, n) for n in os.listdir(mirror)])
    symlinks = []
    dst = join(os.getcwd(), opts.name)
    lastTopDirectory = None
    def updateTopDir(directory):
        global lastTopDirectory
        if lastTopDirectory:
            name, start = lastTopDirectory
            end = time.time()
            duration = datetime.timedelta(seconds=end - start)
            log('  end: ' + name + ' [' + str(duration) + ']')
        if directory:
            log('start: ' + directory)
            lastTopDirectory = (directory, time.time())

    def ignore(directory, contents):
        if directory in toplevel:
            updateTopDir(directory)
        if '.hg' in contents:
            source = join(directory, '.hg')
            link_name = join(dst, os.path.relpath(directory, mirror), '.hg')
            symlinks.append((source, link_name))
        return ['.hg']

    log('Copying ' + mirror + ' to ' + dst)
    shutil.copytree(mirror, dst, ignore=ignore)
    updateTopDir(None)
    for source, link_name in symlinks:
        log('ln -s {} {}'.format(source, link_name))
        os.symlink(source, link_name)

    #apply_patch_for_bug(opts.name + '/open', '8193056')
    #apply_patch_for_bug(opts.name + '/open', '8196295')
    #apply_patch_for_bug(opts.name + '/open', '8187490', 'http://cr.openjdk.java.net/~dnsimon/8187490/open.patch')
    #apply_patch_for_bug(opts.name + '/open', '8220746')

    # Use the date of the parent changeset in open as the build id
    with open('build_id.txt', 'w') as fp:
        if opts.open_url.startswith('ssh://git'):
            rfc822_date = check_output(['git', '-C', join(dst, 'open'), "log", "-n", "1", "-r", "HEAD", "--pretty='format:%aD'"])
        else:
            rfc822_date = check_output(['hg', '-R', join(dst, 'open'), 'parent', '--template', '{date|rfc822date}'])
        fp.write(datetime.datetime.fromtimestamp(time.mktime(rfc822.parsedate(rfc822_date))).strftime('%Y%m%d-%H%M%S'))

#!/bin/bash
#
# Copyright (c) 2020, Oracle and/or its affiliates. All rights reserved.
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

# This script assumes to be called with the following arguments:
# 1     - URL of the boot JDK in tar.gz format, ready to be downloaded with wget
# 2+    - arguments to be passed to build_labsjdk.py script
BOOT_JDK_URL="$1"

if [ $# -lt 1 ]; then
    echo 'ERROR: Expected at least 1 argument.'
    echo 'Usage: <bootJDK url> <argument to be passed to the python build script>*'
    exit 1
fi

# Shift out the first arg so we can pass the rest to the build script
shift

# Allow the script to be called from any directory
BUILD_DIRECTORY=$(dirname "$(readlink -f "$0")")
BOOT_JDK_PATH="${BUILD_DIRECTORY}/bootJDK"
LABS_JDK_PATH="${BUILD_DIRECTORY}/labsjdk-ce-11"
LABS_JDK_BUILD_PATH="${BUILD_DIRECTORY}/labsjdk-build"
COMPILATION_LOG_PATH="${BUILD_DIRECTORY}/compilation.log"
cd "${BUILD_DIRECTORY}"

if ! [ -d "${LABS_JDK_PATH}" ]; then
    echo "ERROR: The labsjdk sources must be mapped to ${LABS_JDK_PATH}."
    exit 1
fi

# Download and uncompress the boot JDK to the ${BUILD_DIRECTORY}/bootJDK path
wget "${BOOT_JDK_URL}"
TAR_FILE="${BOOT_JDK_URL##*/}"
mkdir "${BOOT_JDK_PATH}"
tar xvzf "${TAR_FILE}" -C "${BOOT_JDK_PATH}" --strip 1
# Prepare the JAVA_HOME. Due to some odd, possibly musl related reason, Java cannot find libjvm.so, so
# we give it a hand with LD_LIBRARY_PATH
export JAVA_HOME="${BOOT_JDK_PATH}"
pushd "${JAVA_HOME}" &> /dev/null
export LD_LIBRARY_PATH="$(realpath $(dirname $(find . -iname 'libjvm.so')))"
popd &> /dev/null

# We copy the entire folder so we do not affect the host file system with the build
echo "Copying the labsjdk sources"
cp -r "${LABS_JDK_PATH}" "${LABS_JDK_BUILD_PATH}"
cd "${LABS_JDK_BUILD_PATH}"
echo "Starting compilation"
python3 build_labsjdk.py "$@"
# Check if the compilation was successful, and if not, inform the user
if [ $? -ne 0 ]; then
    echo "ERROR: Compilation failed."
    exit 1
fi
echo "Compilation finished successfully!"
exit 0

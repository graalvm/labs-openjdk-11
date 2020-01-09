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

if [ $# -lt 1 ]; then
    echo "ERROR: Expected at least 1 argument."
    echo "Usage: " $(basename "$0") "<bootJDK url> <argument to be passed to the python build script>*"
    exit 1
fi
SCRIPT_DIRECTORY=$(dirname "$(readlink -f "$0")")
DIST_DIRECTORY="${SCRIPT_DIRECTORY}/dist"
DOCKER_IMAGE_NAME="olabs/jdk-musl-builder"
CONTAINER_LABS_JDK_PATH="/build/labsjdk-ce-11/"
CONTAINER_JDK_BUILD_PATH="/build/labsjdk-build/"
COMPILATION_RESULT_PATH="${CONTAINER_JDK_BUILD_PATH}/build/labsjdks"

cd "${SCRIPT_DIRECTORY}"

# Clean any previously built files
echo "Cleaning up previous builds."
rm -rf "${DIST_DIRECTORY}"
mkdir "${DIST_DIRECTORY}"

echo "Building the builder container image."
docker build . -t ${DOCKER_IMAGE_NAME}

echo "Starting the builder container."
BUILDER_CONTAINER_ID=$(docker run --net=host -d -v $(pwd)/../:"${CONTAINER_LABS_JDK_PATH}" ${DOCKER_IMAGE_NAME})
echo "Builder container started! ID: ${BUILDER_CONTAINER_ID}"
echo "Starting the build."
docker exec ${BUILDER_CONTAINER_ID} /build/builder.sh "$@"
if [ $? -eq 0 ]; then
    echo "Build finished successfully!"
    docker cp "${BUILDER_CONTAINER_ID}:${COMPILATION_RESULT_PATH}" "${DIST_DIRECTORY}"
    echo "The compiled JDK is available at ${DIST_DIRECTORY}"
else
    echo "Build failed!"
fi

echo "Shutting down the builder container."
docker kill ${BUILDER_CONTAINER_ID}
docker rm ${BUILDER_CONTAINER_ID}

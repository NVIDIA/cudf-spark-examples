#!/bin/bash
#
# Copyright (c) 2026, NVIDIA CORPORATION.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

###############################################################################
# Clone or update cuDF repository for header files
#
# This script is called by Maven during the build process to obtain cuDF
# headers needed for compiling native UDF code.
#
# Usage:
#   clone-cudf-repo.sh <target_directory> <git_ref>
#
# Arguments:
#   target_directory - Directory where cuDF repo will be cloned
#   git_ref          - Git branch, tag, or commit to checkout
#
# Exit codes:
#   0 - Success
#   1 - Failed to clone, fetch, or checkout
###############################################################################

set -e
set -o pipefail

# Parse arguments
if [ $# -ne 2 ]; then
    echo "ERROR: Usage: $0 <target_directory> <git_ref>" >&2
    exit 1
fi

CUDF_DIR="$1"
GIT_REF="$2"
GIT=(git -c "safe.directory=$CUDF_DIR")

echo "================================================"
echo "cuDF Repository Management"
echo "  Target directory: $CUDF_DIR"
echo "  Git ref: $GIT_REF"
echo "================================================"

# Check if repository already exists
if [ ! -d "$CUDF_DIR/.git" ]; then
    # Repository doesn't exist - clone it
    echo "Cloning cuDF repository..."
    
    "${GIT[@]}" clone --filter=blob:none --no-checkout https://github.com/rapidsai/cudf.git "$CUDF_DIR" || {
        echo "ERROR: Failed to clone cuDF repository" >&2
        echo "Please check:" >&2
        echo "  1. Network connectivity to GitHub" >&2
        exit 1
    }

    cd "$CUDF_DIR" || {
        echo "ERROR: Cannot access directory $CUDF_DIR" >&2
        exit 1
    }

    "${GIT[@]}" fetch --depth 1 origin "$GIT_REF" || {
        echo "ERROR: Failed to fetch cuDF ref $GIT_REF from origin" >&2
        echo "Please check:" >&2
        echo "  1. Network connectivity to GitHub" >&2
        echo "  2. Ref '$GIT_REF' exists in cuDF repository" >&2
        exit 1
    }

    "${GIT[@]}" checkout --detach FETCH_HEAD || {
        echo "ERROR: Failed to checkout cuDF ref $GIT_REF" >&2
        exit 1
    }

    echo "✓ Successfully cloned cuDF repository"
else
    # Repository exists - verify and update if needed
    echo "cuDF repository exists, verifying ref..."
    cd "$CUDF_DIR" || {
        echo "ERROR: Cannot access directory $CUDF_DIR" >&2
        exit 1
    }

    CURRENT_COMMIT=$("${GIT[@]}" rev-parse HEAD 2>/dev/null || echo "unknown")

    "${GIT[@]}" fetch --depth 1 origin "$GIT_REF" || {
        echo "ERROR: Failed to fetch cuDF ref $GIT_REF from origin" >&2
        echo "Please check:" >&2
        echo "  1. Network connectivity to GitHub" >&2
        echo "  2. Ref '$GIT_REF' exists in cuDF repository" >&2
        exit 1
    }

    FETCHED_COMMIT=$("${GIT[@]}" rev-parse FETCH_HEAD)

    if [ "$CURRENT_COMMIT" != "$FETCHED_COMMIT" ]; then
        echo "cuDF ref mismatch detected:"
        echo "  Current commit: $CURRENT_COMMIT"
        echo "  Expected commit: $FETCHED_COMMIT ($GIT_REF)"
        "${GIT[@]}" checkout --detach FETCH_HEAD || {
            echo "ERROR: Failed to checkout cuDF ref $GIT_REF" >&2
            exit 1
        }
        echo "✓ Switched cuDF repository to $GIT_REF"
    else
        echo "✓ Already on correct cuDF ref ($GIT_REF)"
    fi
fi

echo "================================================"
echo "✓ cuDF repository ready at: $CUDF_DIR"
echo "  Git ref: $GIT_REF"
echo "================================================"

exit 0


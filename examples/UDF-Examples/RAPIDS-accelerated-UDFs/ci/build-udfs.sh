#!/usr/bin/env bash
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

# Run inside the native toolchain container, from the UDF example directory.
# Image smoke checks and actual builds must initialize the same compiler/JDK.
set -eo pipefail
mode=${1:-build}
if [[ "$mode" != build && "$mode" != smoke ]]; then
  echo "Usage: $0 [build|smoke]" >&2
  exit 2
fi

# The toolset activation script is not nounset-safe.
# shellcheck source=/dev/null
source "/opt/rh/gcc-toolset-${TOOLSET_VERSION}/enable"
set -u
export CC CXX JAVA_HOME
# The existing CMake file reads CXX directly; supply the active toolset path.
CC=$(command -v gcc)
CXX=$(command -v g++)
JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")

if [[ "$mode" == smoke ]]; then
  gcc --version
  g++ --version
  nvcc --version
  cmake --version
  ninja --version
  ccache --version
  javac -version
  mvn -B --version
  exit 0
fi

ccache --max-size=500M
ccache --zero-stats
trap 'ccache --show-stats' EXIT

# A100, L4/L40G, H100/H200, RTX PRO 6000; retain PTX for newer GPUs.
mvn -B clean package -Pudf-native-examples \
  -DUSE_PREBUILT_CUDF=ON -DGPU_ARCHS="80-real;89-real;90-real;120" \
  -DCPP_PARALLEL_LEVEL="$(nproc)" -Dmaven.repo.local=/cache/maven
udf_jars=(target/rapids-4-spark-udf-examples*.jar)
[[ ${#udf_jars[@]} -eq 1 ]]
jar tf "${udf_jars[0]}" | grep -Fx "amd64/Linux/libudfexamplesjni.so"

# The UDF jar does not bundle these shared libraries; the GPU worker needs both.
mkdir -p target/native-runtime
cp -L target/cpp-build/_deps/rmm-build/librmm.so \
  target/cpp-build/_deps/rapids_logger-build/librapids_logger.so \
  target/native-runtime/

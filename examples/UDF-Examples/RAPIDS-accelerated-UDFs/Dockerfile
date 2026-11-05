#
# Copyright (c) 2021-2026, NVIDIA CORPORATION. All rights reserved.
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

# A container that can be used to build UDF native code against libcudf
# Test-only: change the recipe fingerprint to exercise PR layer-cache fallback.
ARG CUDA_VERSION=12.9.1
ARG LINUX_VERSION=rockylinux8

FROM nvidia/cuda:${CUDA_VERSION}-devel-${LINUX_VERSION}

ARG TOOLSET_VERSION=13
ENV TOOLSET_VERSION=13
ARG PARALLEL_LEVEL=10
ENV PARALLEL_LEVEL=10

### Install basic requirements
RUN dnf --enablerepo=powertools install -y \
  gcc-toolset-${TOOLSET_VERSION} \
  git \
  java-1.8.0-openjdk \
  maven \
  ninja-build \
  patch \
  python39 \
  scl-utils \
  tar \
  wget \
  zlib-devel \
  && alternatives --set python /usr/bin/python3

# 3.22.3: CUDA architecture 'native' support + flexible CMAKE_<LANG>_*_LAUNCHER for ccache
ARG CMAKE_VERSION=4.0.3
# default x86_64 from x86 build, aarch64 cmake for arm build
ARG CMAKE_ARCH=x86_64
RUN cd /usr/local && wget --quiet https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${CMAKE_ARCH}.tar.gz && \
   tar zxf cmake-${CMAKE_VERSION}-linux-${CMAKE_ARCH}.tar.gz && \
   rm cmake-${CMAKE_VERSION}-linux-${CMAKE_ARCH}.tar.gz
ENV PATH /usr/local/cmake-${CMAKE_VERSION}-linux-${CMAKE_ARCH}/bin:$PATH

# ccache for interactive builds
ARG CCACHE_VERSION=4.11.2
RUN cd /tmp && wget --quiet https://github.com/ccache/ccache/releases/download/v${CCACHE_VERSION}/ccache-${CCACHE_VERSION}.tar.gz && \
   tar zxf ccache-${CCACHE_VERSION}.tar.gz && \
   rm ccache-${CCACHE_VERSION}.tar.gz && \
   cd ccache-${CCACHE_VERSION} && \
   mkdir build && \
   cd build && \
   scl enable gcc-toolset-${TOOLSET_VERSION} \
      "cmake .. \
         -DCMAKE_BUILD_TYPE=Release \
         -DZSTD_FROM_INTERNET=ON \
         -DREDIS_STORAGE_BACKEND=OFF && \
      cmake --build . --parallel ${PARALLEL_LEVEL} --target install" && \
   cd ../.. && \
   rm -rf ccache-${CCACHE_VERSION}

ENTRYPOINT /usr/bin/scl enable gcc-toolset-${TOOLSET_VERSION} -- bash

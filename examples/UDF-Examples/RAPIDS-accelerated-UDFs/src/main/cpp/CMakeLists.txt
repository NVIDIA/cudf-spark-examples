#=============================================================================
# Copyright (c) 2021-2026, NVIDIA CORPORATION.
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
#=============================================================================

# Keep the same with https://github.com/rapidsai/rapids-cmake/blob/main/RAPIDS.cmake
cmake_minimum_required(VERSION 4.0 FATAL_ERROR)

# set to the rapids-cmake-branch
set(rapids-cmake-branch "main")

file(DOWNLOAD https://raw.githubusercontent.com/rapidsai/rapids-cmake/${rapids-cmake-branch}/RAPIDS.cmake
     ${CMAKE_BINARY_DIR}/RAPIDS.cmake)
include(${CMAKE_BINARY_DIR}/RAPIDS.cmake)

include(rapids-cmake)
include(rapids-cpm)
include(rapids-cuda)
include(rapids-export)
include(rapids-find)

# Get the rapids-cmake directory for later use
# After include(rapids-cmake), CPM will download rapids-cmake to _deps
# We can get it from the CPM cache
get_property(rapids-cmake-dir GLOBAL PROPERTY rapids-cmake-dir)
if(NOT rapids-cmake-dir)
    # Fallback: rapids-cmake is downloaded by CPM to _deps
    set(rapids-cmake-dir "${CMAKE_BINARY_DIR}/_deps/rapids-cmake-src")
    message(STATUS "rapids-cmake property not set, using fallback path")
endif()

# Verify rapids-cmake directory exists
if(NOT EXISTS "${rapids-cmake-dir}")
    message(FATAL_ERROR 
        "rapids-cmake directory not found: ${rapids-cmake-dir}\n"
        "This usually means rapids-cmake wasn't properly fetched by CPM.\n"
        "Try deleting the build directory and reconfiguring:\n"
        "  rm -rf ${CMAKE_BINARY_DIR}\n"
        "  cmake ..")
endif()

message(STATUS "rapids-cmake directory: ${rapids-cmake-dir}")

# Use GPU_ARCHS if it is defined
if(DEFINED GPU_ARCHS)
  set(CMAKE_CUDA_ARCHITECTURES "${GPU_ARCHS}")
endif()
rapids_cuda_init_architectures(UDFEXAMPLESJNI)

project(UDFEXAMPLESJNI VERSION 26.08.0 LANGUAGES C CXX CUDA)

option(PER_THREAD_DEFAULT_STREAM "Build with per-thread default stream" OFF)
option(BUILD_UDF_BENCHMARKS "Build the benchmarks" OFF)

###################################################################################################
# - build type ------------------------------------------------------------------------------------

# Set a default build type if none was specified
set(DEFAULT_BUILD_TYPE "Release")

###################################################################################################
# - compiler options ------------------------------------------------------------------------------

set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_COMPILER $ENV{CXX})
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_CUDA_STANDARD 20)
set(CMAKE_CUDA_STANDARD_REQUIRED ON)

if(CMAKE_COMPILER_IS_GNUCXX)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-unknown-pragmas")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-error=deprecated-declarations")
endif(CMAKE_COMPILER_IS_GNUCXX)

if(CMAKE_CUDA_COMPILER_VERSION)
  # Compute the version. from  CMAKE_CUDA_COMPILER_VERSION
  string(REGEX REPLACE "([0-9]+)\\.([0-9]+).*" "\\1" CUDA_VERSION_MAJOR ${CMAKE_CUDA_COMPILER_VERSION})
  string(REGEX REPLACE "([0-9]+)\\.([0-9]+).*" "\\2" CUDA_VERSION_MINOR ${CMAKE_CUDA_COMPILER_VERSION})
  set(CUDA_VERSION "${CUDA_VERSION_MAJOR}.${CUDA_VERSION_MINOR}" CACHE STRING "Version of CUDA as computed from nvcc.")
  mark_as_advanced(CUDA_VERSION)
endif()

message(STATUS "CUDA_VERSION_MAJOR: ${CUDA_VERSION_MAJOR}")
message(STATUS "CUDA_VERSION_MINOR: ${CUDA_VERSION_MINOR}")
message(STATUS "CUDA_VERSION: ${CUDA_VERSION}")

# Always set this convenience variable
set(CUDA_VERSION_STRING "${CUDA_VERSION}")

set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -w --expt-extended-lambda --expt-relaxed-constexpr")

####################################################################################################
# - cudf -------------------------------------------------------------------------------------------

# Check if USE_PREBUILT_CUDF was explicitly set by user (e.g., via -DUSE_PREBUILT_CUDF=...)
# This must be done BEFORE the option() command
if(DEFINED USE_PREBUILT_CUDF)
    set(USER_SET_USE_PREBUILT_CUDF TRUE)
    message(STATUS "USE_PREBUILT_CUDF explicitly set by user to: ${USE_PREBUILT_CUDF}")
else()
    set(USER_SET_USE_PREBUILT_CUDF FALSE)
endif()

option(USE_PREBUILT_CUDF "Use prebuilt libcudf.so from rapids-4-spark jar" ON)

message(STATUS "USE_PREBUILT_CUDF is set to: ${USE_PREBUILT_CUDF}")

# Check if Maven created a marker to force source build
# This happens when rapids-4-spark jar is not found
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/USE_SOURCE_BUILD")
    message(STATUS "Found USE_SOURCE_BUILD marker file from Maven (rapids-4-spark jar not found)")

    if(USE_PREBUILT_CUDF)
        if(USER_SET_USE_PREBUILT_CUDF)
            # User explicitly requested prebuilt mode, but jar is missing - fail fast with clear error
            message(FATAL_ERROR 
                "\n"
                "================================================================\n"
                "ERROR: rapids-4-spark jar not found, but USE_PREBUILT_CUDF=ON\n"
                "was explicitly set by the user.\n"
                "\n"
                "Cannot proceed with prebuilt mode because required libraries\n"
                "are not available.\n"
                "\n"
                "Solutions:\n"
                "  1. Remove -DUSE_PREBUILT_CUDF=ON to allow automatic fallback\n"
                "     to building from source\n"
                "\n"
                "  2. Build and install rapids-4-spark:\n"
                "     cd /path/to/spark-rapids\n"
                "     mvn clean install -DskipTests\n"
                "\n"
                "  3. Explicitly use source build:\n"
                "     -DUSE_PREBUILT_CUDF=OFF\n"
                "================================================================\n")
        else()
            # Not explicitly set by user - safe to auto-fallback
            message(STATUS "Auto-fallback: Switching to source build due to missing jar")
            set(USE_PREBUILT_CUDF OFF CACHE BOOL "Auto-fallback to source build (jar not found)" FORCE)
        endif()
    endif()
endif()

# Check prebuilt availability before making final decision
# This avoids modifying cache variables within conditional blocks
set(SHOULD_USE_PREBUILT ${USE_PREBUILT_CUDF})

if(USE_PREBUILT_CUDF AND NOT USER_SET_USE_PREBUILT_CUDF)
    # User didn't explicitly set the option - check if prebuilt components are available
    # Set paths for prebuilt library and headers
    set(CUDF_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/native-deps")
    set(CUDF_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/cudf-repo/cpp/include")
    
    message(STATUS "Checking for prebuilt libcudf.so from rapids-4-spark jar")
    message(STATUS "Looking in: ${CUDF_LIB_DIR}")
    
    # Check if prebuilt components are available
    set(PREBUILT_AVAILABLE TRUE)
    if(NOT EXISTS "${CUDF_LIB_DIR}")
        message(STATUS "Directory ${CUDF_LIB_DIR} does not exist")
        set(PREBUILT_AVAILABLE FALSE)
    else()
        # Try to find the library
        # Note: find_library sets variable to <var>-NOTFOUND on failure, not undefined
        find_library(CUDF_LIBRARY_CHECK
            NAMES cudf
            PATHS ${CUDF_LIB_DIR}
            NO_DEFAULT_PATH
        )
        
        # Proper check: find_library failure results in <VAR>-NOTFOUND string
        if(CUDF_LIBRARY_CHECK MATCHES "-NOTFOUND$")
            message(STATUS "libcudf.so not found in ${CUDF_LIB_DIR}")
            set(PREBUILT_AVAILABLE FALSE)
        else()
            message(STATUS "Found libcudf at: ${CUDF_LIBRARY_CHECK}")
        endif()
    endif()
    
    # Auto-fallback to source build if components not available
    if(NOT PREBUILT_AVAILABLE)
        message(WARNING 
            "\n"
            "================================================================\n"
            "Prebuilt libcudf.so not available.\n"
            "Automatically falling back to building cuDF from source.\n"
            "This will take 30+ minutes.\n"
            "\n"
            "To use fast build mode in future:\n"
            "  1. For SNAPSHOT versions: Build and install rapids-4-spark\n"
            "     cd /path/to/spark-rapids\n"
            "     mvn clean install -DskipTests\n"
            "  2. Run: mvn clean package -Pudf-native-examples\n"
            "\n"
            "NOTE: If you need to reset this decision, delete:\n"
            "      ${CMAKE_BINARY_DIR}/CMakeCache.txt\n"
            "================================================================\n")
        set(SHOULD_USE_PREBUILT FALSE)
        # Update cache for subsequent runs
        set(USE_PREBUILT_CUDF OFF CACHE BOOL "Auto-fallback to source build" FORCE)
    endif()
endif()

# Now use the final decision consistently
if(SHOULD_USE_PREBUILT)
    # Set paths as cache variables for user customization
    set(CUDF_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/native-deps" CACHE PATH "Path to directory containing libcudf.so")
    set(CUDF_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/cudf-repo/cpp/include" CACHE PATH "Path to cudf headers")
    
    message(STATUS "✓ Using FAST BUILD mode with prebuilt libcudf.so")
    
    # Find the prebuilt libcudf.so (should succeed based on earlier check)
    find_library(CUDF_LIBRARY
        NAMES cudf
        PATHS ${CUDF_LIB_DIR}
        NO_DEFAULT_PATH
        REQUIRED
    )
    
    message(STATUS "✓ Found libcudf: ${CUDF_LIBRARY}")
    message(STATUS "✓ cuDF include directory: ${CUDF_INCLUDE_DIR}")
    
    # Verify cuDF source directory exists (cloned by Maven)
    set(CUDF_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../target/cudf-repo/cpp")
    if(NOT EXISTS "${CUDF_SOURCE_DIR}/CMakeLists.txt")
        message(FATAL_ERROR 
            "cuDF source directory not found: ${CUDF_SOURCE_DIR}\n"
            "The cuDF repository should have been cloned by Maven.\n"
            "Check if target/cudf-repo/ exists.")
    endif()
    
    message(STATUS "✓ Found cuDF source at: ${CUDF_SOURCE_DIR}")
    
    # We'll use cuDF's dependency fetching mechanism but create our own target
    # First, let rapids-cpm fetch the dependencies that cuDF needs
    message(STATUS "Fetching cuDF dependencies (this may take a few minutes)...")
    
    rapids_cpm_init()
    
    # Set options to avoid building unnecessary components
    set(BUILD_TESTS OFF CACHE BOOL "" FORCE)
    set(BUILD_BENCHMARKS OFF CACHE BOOL "" FORCE)
    
    # Use rapids-cmake's helper scripts to get CCCL and RMM
    # These scripts use versions defined in rapids-cmake (avoiding duplicate version definitions)
    message(STATUS "Using rapids-cmake helper scripts for CCCL and RMM")

    # Get CCCL (Thrust, libcudacxx, CUB) - version defined in rapids-cmake
    set(CCCL_CMAKE_FILE "${rapids-cmake-dir}/cpm/cccl.cmake")
    if(NOT EXISTS "${CCCL_CMAKE_FILE}")
        message(FATAL_ERROR 
            "rapids-cmake CCCL helper script not found: ${CCCL_CMAKE_FILE}\n"
            "Expected location: ${rapids-cmake-dir}/cpm/cccl.cmake\n"
            "This indicates rapids-cmake directory structure is incomplete or incorrect.")
    endif()
    include(${CCCL_CMAKE_FILE})
    rapids_cpm_cccl()

    # Use rapids-cpm to get RMM - this is what cuDF uses  
    set(RMM_CMAKE_FILE "${rapids-cmake-dir}/cpm/rmm.cmake")
    if(NOT EXISTS "${RMM_CMAKE_FILE}")
        message(FATAL_ERROR 
            "rapids-cmake RMM helper script not found: ${RMM_CMAKE_FILE}\n"
            "Expected location: ${rapids-cmake-dir}/cpm/rmm.cmake\n"
            "This indicates rapids-cmake directory structure is incomplete or incorrect.")
    endif()
    include(${RMM_CMAKE_FILE})
    rapids_cpm_rmm()

    # After rapids_cpm_rmm(), the rmm::rmm target should be available
    # Verify it exists
    if(NOT TARGET rmm::rmm)
        message(FATAL_ERROR "rmm::rmm target not created by rapids_cpm_rmm()")
    endif()
    
    # Get RMM include directory from the target
    get_target_property(RMM_INCLUDE_DIR rmm::rmm INTERFACE_INCLUDE_DIRECTORIES)
    message(STATUS "RMM include directories: ${RMM_INCLUDE_DIR}")

    # Now create our own imported target for cudf using the prebuilt library
    add_library(cudf_imported SHARED IMPORTED GLOBAL)
    set_target_properties(cudf_imported PROPERTIES
        IMPORTED_LOCATION ${CUDF_LIBRARY}
    )
    
    # Add include directories to the imported target
    # Include cuDF headers and RMM headers
    target_include_directories(cudf_imported INTERFACE
        ${CUDF_INCLUDE_DIR}
        ${RMM_INCLUDE_DIR}
    )
    
    # Link against RMM to get other dependencies
    target_link_libraries(cudf_imported INTERFACE rmm::rmm)
    
    # Create an alias to match expected name
    add_library(cudf::cudf ALIAS cudf_imported)
    
    message(STATUS "✓ Prebuilt cuDF configured with all dependencies")
    message(STATUS "  Prebuilt library: ${CUDF_LIBRARY}")
    message(STATUS "  cuDF headers: ${CUDF_INCLUDE_DIR}")
    message(STATUS "  Dependencies: CCCL, RMM (via rapids-cpm)")
    
else()
    message(STATUS "Building cuDF from source (this will take a long time)")
    
    # Ensure CUDA runtime is dynamic despite statically linking Arrow in libcudf
    set(CUDA_USE_STATIC_CUDA_RUNTIME ON)
    
    rapids_cpm_init()
    rapids_cpm_find(cudf 26.08.00
            CPM_ARGS
            GIT_REPOSITORY  https://github.com/rapidsai/cudf.git
            GIT_TAG         ${rapids-cmake-branch}
            GIT_SHALLOW     TRUE
            SOURCE_SUBDIR   cpp
            OPTIONS         "BUILD_TESTS OFF"
                            "BUILD_BENCHMARKS OFF"
                            "CUDF_USE_ARROW_STATIC ON"
                            "JITIFY_USE_CACHE ON"
                            "CUDA_STATIC_RUNTIME ${CUDA_USE_STATIC_CUDA_RUNTIME}"
                            "DISABLE_DEPRECATION_WARNING ON"
                            "AUTO_DETECT_CUDA_ARCHITECTURES OFF"
                            "CUDF_KVIKIO_REMOTE_IO OFF"
        )
endif()

###################################################################################################
# - benchmarks ------------------------------------------------------------------------------------

if(BUILD_UDF_BENCHMARKS)
    # Find or install GoogleBench
    CPMFindPackage(NAME benchmark
        VERSION         1.5.2
        GIT_REPOSITORY  https://github.com/google/benchmark.git
        GIT_TAG         v1.5.2
        GIT_SHALLOW     TRUE
        OPTIONS         "BENCHMARK_ENABLE_TESTING OFF"
                        "BENCHMARK_ENABLE_INSTALL OFF")
    add_subdirectory(benchmarks)
endif()

###################################################################################################
# - find JNI -------------------------------------------------------------------------------------

find_package(JNI REQUIRED)
if(JNI_FOUND)
    message(STATUS "JDK with JNI in ${JNI_INCLUDE_DIRS}")
else()
    message(FATAL_ERROR "JDK with JNI not found, please check your settings.")
endif(JNI_FOUND)

###################################################################################################
# - library paths ---------------------------------------------------------------------------------

# CMAKE_CUDA_IMPLICIT_LINK_DIRECTORIES is an undocumented/unsupported variable containing the link directories for nvcc
link_directories("${CMAKE_CUDA_IMPLICIT_LINK_DIRECTORIES}"
                 "${CMAKE_BINARY_DIR}/lib")


###################################################################################################
# - library targets -------------------------------------------------------------------------------

set(SOURCE_FILES
    "src/CosineSimilarityJni.cpp"
    "src/StringWordCountJni.cpp"
    "src/cosine_similarity.cu"
    "src/string_word_count.cu")

add_library(udfexamplesjni SHARED ${SOURCE_FILES})

#Override RPATH for udfexamplesjni
SET_TARGET_PROPERTIES(udfexamplesjni PROPERTIES BUILD_RPATH "\$ORIGIN")

###################################################################################################
# - build options ---------------------------------------------------------------------------------

option(PER_THREAD_DEFAULT_STREAM "Build with per-thread default stream" OFF)
if(PER_THREAD_DEFAULT_STREAM)
    message(STATUS "Using per-thread default stream")
    target_compile_definitions(udfexamplesjni PRIVATE CUDA_API_PER_THREAD_DEFAULT_STREAM)
endif(PER_THREAD_DEFAULT_STREAM)

target_include_directories(udfexamplesjni PRIVATE ${JNI_INCLUDE_DIRS})

###################################################################################################
# - rmm logging level -----------------------------------------------------------------------------

set(RMM_LOGGING_LEVEL "OFF" CACHE STRING "Choose the logging level.")
# Set the possible values of build type for cmake-gui
set_property(CACHE RMM_LOGGING_LEVEL PROPERTY STRINGS
        "TRACE" "DEBUG" "INFO" "WARN" "ERROR" "CRITICAL" "OFF")
message(STATUS "RMM_LOGGING_LEVEL = '${RMM_LOGGING_LEVEL}'.")

target_compile_definitions(udfexamplesjni
    PUBLIC SPDLOG_ACTIVE_LEVEL=SPDLOG_LEVEL_${RMM_LOGGING_LEVEL})

###################################################################################################
# - link libraries --------------------------------------------------------------------------------

target_link_libraries(udfexamplesjni cudf::cudf)

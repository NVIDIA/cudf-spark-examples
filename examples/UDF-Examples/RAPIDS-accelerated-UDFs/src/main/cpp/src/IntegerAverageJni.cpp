/*
 * Copyright (c) 2025, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "integer_average.hpp"
#include "integer_average_host_udf.hpp"

#include <jni.h>

namespace {
/**
 * @brief Throw a Java exception
 *
 * @param env The Java environment
 * @param msg The message string to associate with the exception
 */
void throw_java_exception(JNIEnv* env, char const* msg) {
  jclass exp_class = env->FindClass("java/lang/RuntimeException");
  if (exp_class != NULL) {
    env->ThrowNew(exp_class, msg);
  }
}

}  // anonymous namespace

extern "C" {

JNIEXPORT jlong JNICALL Java_com_nvidia_spark_rapids_udaf_java_AverageExampleUDF_createAverageHostUDF(
  JNIEnv* env, jclass, jint agg_type)
{
  try {
    auto udf_ptr = [&] {
      // The value of agg_type must be sync with
      // `AverageExampleUDF.java#AggregationType`.
      switch (agg_type) {
        case 0: return examples::create_average_example_reduction_host_udf();
        case 1: return examples::create_average_example_reduction_merge_host_udf();
        case 2: return examples::create_average_example_groupby_host_udf();
        case 3: return examples::create_average_example_groupby_merge_host_udf();
        default: CUDF_FAIL("Invalid aggregation type.");
      }
    }();
    CUDF_EXPECTS(udf_ptr != nullptr, "Invalid AverageExample UDF instance.");
    return reinterpret_cast<jlong>(udf_ptr);
  } catch (std::bad_alloc const& e) {
      auto msg = std::string("Unable to allocate native memory: ") +
          (e.what() == nullptr ? "" : e.what());
      throw_java_exception(env, msg.c_str());
  } catch (std::exception const& e) {
    auto msg = e.what() == nullptr ? "" : e.what();
    throw_java_exception(env, msg);
  }
  return 0;
}

JNIEXPORT jlong JNICALL Java_com_nvidia_spark_rapids_udaf_java_AverageExampleUDF_computeAvg(
  JNIEnv* env, jclass, jlong input)
{
  if (input == 0) {
    throw_java_exception(env, "input column is null");
  } else {
    try {
      auto const input_view = reinterpret_cast<cudf::column_view const*>(input);
      return reinterpret_cast<jlong>(examples::compute_average_example(*input_view).release());
    } catch (std::bad_alloc const& e) {
      auto msg = std::string("Unable to allocate native memory: ") +
          (e.what() == nullptr ? "" : e.what());
      throw_java_exception(env, msg.c_str());
    } catch (std::exception const& e) {
      auto msg = e.what() == nullptr ? "" : e.what();
      throw_java_exception(env, msg);
    }
  }
  return 0;
}

}  // extern "C"
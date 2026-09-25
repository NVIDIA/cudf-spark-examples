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
#pragma once

#include <cudf/column/column.hpp>
#include <cudf/column/column_view.hpp>
#include <cudf/utilities/default_stream.hpp>
#include <cudf/utilities/memory_resource.hpp>
#include <cudf/utilities/span.hpp>

namespace examples {
/**
 * @brief Aggregate sum and count for each group.
 * Input is a int column.
 * Output is a struct column: struct(sum, avg),
 * the num of rows is equal to num of groups.
 */
std::unique_ptr<cudf::column> group_average_example(
  cudf::column_view const& input,
  cudf::device_span<cudf::size_type const> group_offsets,
  rmm::cuda_stream_view stream      = cudf::get_default_stream(),
  rmm::device_async_resource_ref mr = cudf::get_current_device_resource_ref());

/**
 * @brief Merge sums and counts in the same group.
 * Input is a struct column: struct(sum, avg).
 * Output is a struct column: struct(sum, avg), the num of rows is equal to num of groups.
 */
std::unique_ptr<cudf::column> group_merge_average_example(
  cudf::column_view const& input,
  cudf::device_span<cudf::size_type const> group_offsets,
  rmm::cuda_stream_view stream      = cudf::get_default_stream(),
  rmm::device_async_resource_ref mr = cudf::get_current_device_resource_ref());

/**
 * @brief Aggregate sum and count for all input rows.
 * Input is a int column.
 * Output is a struct scalar: struct(sum, avg).
 */
std::unique_ptr<cudf::scalar> reduce_average_example(
  cudf::column_view const& input,
  rmm::cuda_stream_view stream      = cudf::get_default_stream(),
  rmm::device_async_resource_ref mr = cudf::get_current_device_resource_ref());

/**
 * @brief Merge all sum and count into one sum and count
 * Input is a struct column: struct(sum, avg).
 * Output is a struct scalar: struct(sum, avg).
 */
std::unique_ptr<cudf::scalar> reduce_merge_average_example(
  cudf::column_view const& input,
  rmm::cuda_stream_view stream      = cudf::get_default_stream(),
  rmm::device_async_resource_ref mr = cudf::get_current_device_resource_ref());

/**
 * @brief Compute average from sum and count.
 * Input is a struct column: struct(sum, avg).
 * Output is a int column.
 * This is the final step for both group and reduction average example.
 */
std::unique_ptr<cudf::column> compute_average_example(
  cudf::column_view const& input,
  rmm::cuda_stream_view stream      = cudf::get_default_stream(),
  rmm::device_async_resource_ref mr = cudf::get_current_device_resource_ref());
}  // namespace examples
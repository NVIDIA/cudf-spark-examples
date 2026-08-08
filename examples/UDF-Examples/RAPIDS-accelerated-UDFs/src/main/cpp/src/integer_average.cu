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

#include <cudf/column/column_device_view.cuh>
#include <cudf/column/column_factories.hpp>
#include <cudf/detail/iterator.cuh>
#include <cudf/detail/nvtx/ranges.hpp>
#include <cudf/detail/valid_if.cuh>
#include <cudf/scalar/scalar.hpp>
#include <cudf/structs/structs_column_view.hpp>
#include <cudf/types.hpp>

#include <rmm/device_uvector.hpp>
#include <rmm/exec_policy.hpp>

#include <thrust/for_each.h>
#include <thrust/reduce.h>
#include <thrust/tabulate.h>

namespace examples {
namespace detail {
namespace {

struct group_fn {
  // inputs
  int const* key_offsets_ptr;
  cudf::column_device_view d_data;

  // outputs
  int* sum_output;
  bool* sum_validity;  // false indicates all values in a group are null(sum is null)
  int* count_output;

  __device__ void operator()(cudf::size_type group_idx) const
  {
    bool is_sum_valid = false;
    int sum           = 0;
    int count         = 0;
    for (auto i = key_offsets_ptr[group_idx]; i < key_offsets_ptr[group_idx + 1]; ++i) {
      if (d_data.is_valid(i)) {
        is_sum_valid = true;
        sum += d_data.element<int>(i);
        ++count;
      }
    }

    sum_output[group_idx]   = sum;
    sum_validity[group_idx] = is_sum_valid;
    count_output[group_idx] = count;
  }
};

struct group_merge_fn {
  // inputs
  int const* key_offsets_ptr;
  cudf::column_device_view d_input_sum;
  int const* input_count_ptr;

  // outputs
  int* sum_output;
  bool* sum_validity;  // false indicates all values in a group are null(sum is null)
  int* count_output;

  __device__ void operator()(cudf::size_type group_idx) const
  {
    bool is_sum_valid = false;
    int sum           = 0;
    int count         = 0;
    for (auto i = key_offsets_ptr[group_idx]; i < key_offsets_ptr[group_idx + 1]; ++i) {
      if (d_input_sum.is_valid(i)) {
        is_sum_valid = true;
        sum += d_input_sum.element<int>(i);
        count += input_count_ptr[i];
      }
    }

    sum_output[group_idx]   = sum;
    sum_validity[group_idx] = is_sum_valid;
    count_output[group_idx] = count;
  }
};

}  // anonymous namespace

std::unique_ptr<cudf::column> group_avg(cudf::column_view const& grouped_data,
                                        cudf::column_view const& key_offsets,
                                        rmm::cuda_stream_view stream,
                                        rmm::device_async_resource_ref mr)
{
  auto num_groups   = key_offsets.size() - 1;
  auto const d_data = cudf::column_device_view::create(grouped_data, stream);

  // create output columns: sum and count
  auto sum_col = cudf::make_numeric_column(
    cudf::data_type{cudf::type_id::INT32}, num_groups, cudf::mask_state::UNALLOCATED, stream, mr);
  rmm::device_uvector<bool> sum_validity(num_groups, stream);
  auto count_col = cudf::make_numeric_column(
    cudf::data_type{cudf::type_id::INT32}, num_groups, cudf::mask_state::UNALLOCATED, stream, mr);

  // merge sum and count for each group
  thrust::for_each_n(rmm::exec_policy_nosync(stream),
                     thrust::make_counting_iterator(0),
                     num_groups,
                     group_fn{key_offsets.begin<int>(),
                              *d_data,
                              sum_col->mutable_view().begin<int>(),
                              sum_validity.begin(),
                              count_col->mutable_view().begin<int>()});

  // set nulls for sum column
  auto [sum_null_mask, sum_null_count] = cudf::detail::valid_if(
    sum_validity.begin(), sum_validity.end(), cuda::std::identity{}, stream, mr);
  if (sum_null_count > 0) { sum_col->set_null_mask(std::move(sum_null_mask), sum_null_count); }

  // make struct column with (sum, count)
  std::vector<std::unique_ptr<cudf::column>> children;
  children.push_back(std::move(sum_col));
  children.push_back(std::move(count_col));
  return cudf::make_structs_column(num_groups,
                                   std::move(children),
                                   0,                     // null count
                                   rmm::device_buffer{},  // null mask
                                   stream);
}

std::unique_ptr<cudf::column> group_merge_avg(cudf::column_view const& grouped_data,
                                              cudf::column_view const& key_offsets,
                                              rmm::cuda_stream_view stream,
                                              rmm::device_async_resource_ref mr)
{
  auto num_groups = key_offsets.size() - 1;

  // inputs
  cudf::structs_column_view scv(grouped_data);
  auto input_sum_cv              = scv.get_sliced_child(0, stream);
  auto input_count_cv            = scv.get_sliced_child(1, stream);
  auto d_input_sum               = cudf::column_device_view::create(input_sum_cv, stream);
  int32_t const* input_count_ptr = input_count_cv.begin<int32_t>();

  // create output columns: sum and count
  auto output_sum_col = cudf::make_numeric_column(
    cudf::data_type{cudf::type_id::INT32}, num_groups, cudf::mask_state::UNALLOCATED, stream, mr);
  rmm::device_uvector<bool> sum_validity(num_groups, stream);
  auto output_count_col = cudf::make_numeric_column(
    cudf::data_type{cudf::type_id::INT32}, num_groups, cudf::mask_state::UNALLOCATED, stream, mr);

  // merge sum and count for each group
  thrust::for_each_n(rmm::exec_policy_nosync(stream),
                     thrust::make_counting_iterator(0),
                     num_groups,
                     group_merge_fn{key_offsets.begin<int>(),
                                    *d_input_sum,
                                    input_count_ptr,
                                    output_sum_col->mutable_view().begin<int>(),
                                    sum_validity.begin(),
                                    output_count_col->mutable_view().data<int>()});

  // set nulls for sum column
  auto [sum_null_mask, sum_null_count] = cudf::detail::valid_if(
    sum_validity.begin(), sum_validity.end(), cuda::std::identity{}, stream, mr);
  if (sum_null_count > 0) {
    output_sum_col->set_null_mask(std::move(sum_null_mask), sum_null_count);
  }

  // make struct column with (sum, count)
  std::vector<std::unique_ptr<cudf::column>> children;
  children.push_back(std::move(output_sum_col));
  children.push_back(std::move(output_count_col));
  return cudf::make_structs_column(num_groups,
                                   std::move(children),
                                   0,                     // null count
                                   rmm::device_buffer{},  // null mask
                                   stream);
}

std::unique_ptr<cudf::scalar> reduce_avg(cudf::column_view const& input,
                                         rmm::cuda_stream_view stream,
                                         rmm::device_async_resource_ref mr)
{
  // 1. compute count
  int count         = input.size() - input.null_count();
  bool is_sum_valid = count > 0;

  // 2. compute sum, if element is null, treat it as 0
  auto d_input           = cudf::column_device_view::create(input, stream);
  auto const element_itr = cudf::detail::make_counting_transform_iterator(
    0,
    cuda::proclaim_return_type<cudf::size_type>(
      [d_input = *d_input] __device__(cudf::size_type idx) -> cudf::size_type {
        if (d_input.is_valid(idx)) {
          return d_input.element<int>(idx);
        } else {
          // null element, treat it as 0
          return 0;
        }
      }));
  int sum =
    thrust::reduce(rmm::exec_policy_nosync(stream), element_itr, element_itr + input.size());

  // 2. create output columns: sum and count
  auto num_long_cols      = 2;
  auto const results_iter = cudf::detail::make_counting_transform_iterator(0, [&](int i) {
    return cudf::make_numeric_column(cudf::data_type{cudf::type_id::INT32},
                                     1, /** scalar has only 1 element */
                                     cudf::mask_state::UNALLOCATED,
                                     stream,
                                     mr);
  });
  auto children =
    std::vector<std::unique_ptr<cudf::column>>(results_iter, results_iter + num_long_cols);
  int32_t* output_sum = children[0]->mutable_view().data<int32_t>();
  rmm::device_uvector<bool> sum_validity(1, stream);
  int32_t* output_count = children[1]->mutable_view().data<int32_t>();
  thrust::fill(
    rmm::exec_policy_nosync(stream), sum_validity.begin(), sum_validity.end(), is_sum_valid);
  thrust::fill(rmm::exec_policy_nosync(stream), output_count, output_count + 1, count);
  thrust::fill(rmm::exec_policy_nosync(stream), output_sum, output_sum + 1, sum);

  // 3. set null for sum
  auto [sum_null_mask, sum_null_count] = cudf::detail::valid_if(
    sum_validity.begin(), sum_validity.end(), cuda::std::identity{}, stream, mr);
  if (sum_null_count > 0) { children[0]->set_null_mask(std::move(sum_null_mask), sum_null_count); }

  // 4. create struct scalar
  return std::make_unique<cudf::struct_scalar>(cudf::table{std::move(children)}, true, stream, mr);
}

std::unique_ptr<cudf::scalar> reduce_merge_avg(cudf::column_view const& input,
                                               rmm::cuda_stream_view stream,
                                               rmm::device_async_resource_ref mr)
{
  // inputs
  cudf::structs_column_view scv(input);
  auto input_sum_cv   = scv.get_sliced_child(0, stream);
  auto input_count_cv = scv.get_sliced_child(1, stream);

  // 1. compute sum and count
  bool is_sum_valid = input_sum_cv.size() > input_sum_cv.null_count();
  int sum           = thrust::reduce(
    rmm::exec_policy_nosync(stream), input_sum_cv.begin<int>(), input_sum_cv.end<int>());
  int count = thrust::reduce(
    rmm::exec_policy_nosync(stream), input_count_cv.begin<int>(), input_count_cv.end<int>());

  // 2. create output columns: sum and count
  auto num_long_cols      = 2;
  auto const results_iter = cudf::detail::make_counting_transform_iterator(0, [&](int i) {
    return cudf::make_numeric_column(cudf::data_type{cudf::type_id::INT32},
                                     1 /** scalar has only 1 element */,
                                     cudf::mask_state::UNALLOCATED,
                                     stream,
                                     mr);
  });
  auto children =
    std::vector<std::unique_ptr<cudf::column>>(results_iter, results_iter + num_long_cols);
  int32_t* output_sum = children[0]->mutable_view().data<int32_t>();
  rmm::device_uvector<bool> sum_validity(1, stream);
  int32_t* output_count = children[1]->mutable_view().data<int32_t>();
  thrust::fill(
    rmm::exec_policy_nosync(stream), sum_validity.begin(), sum_validity.end(), is_sum_valid);
  thrust::fill(rmm::exec_policy_nosync(stream), output_count, output_count + 1, count);
  thrust::fill(rmm::exec_policy_nosync(stream), output_sum, output_sum + 1, sum);

  // 3. set null for sum
  auto [sum_null_mask, sum_null_count] = cudf::detail::valid_if(
    sum_validity.begin(), sum_validity.end(), cuda::std::identity{}, stream, mr);
  if (sum_null_count > 0) { children[0]->set_null_mask(std::move(sum_null_mask), sum_null_count); }

  // 4. create struct scalar
  return std::make_unique<cudf::struct_scalar>(cudf::table{std::move(children)}, true, stream, mr);
}

/**
 * input is a struct column: struct(sum, count).
 * sum column may have nulls, count column has no nulls.
 * output is a int column: avg.
 */
std::unique_ptr<cudf::column> compute_average_example(cudf::column_view const& input,
                                                      rmm::cuda_stream_view stream,
                                                      rmm::device_async_resource_ref mr)
{
  cudf::structs_column_view scv(input);
  auto sum_cv              = scv.get_sliced_child(0, stream);
  auto count_cv            = scv.get_sliced_child(1, stream);
  auto d_sum               = cudf::column_device_view::create(sum_cv, stream);
  int32_t const* count_ptr = count_cv.begin<int32_t>();

  // if sum is null, result is null. Use sum's null mask for result.
  auto result = cudf::make_fixed_width_column(cudf::data_type{cudf::type_id::INT32},
                                              input.size(),
                                              cudf::detail::copy_bitmask(sum_cv, stream, mr),
                                              input.null_count(),
                                              stream,
                                              mr);

  thrust::tabulate(rmm::exec_policy_nosync(stream),
                   result->mutable_view().begin<int32_t>(),
                   result->mutable_view().end<int32_t>(),
                   [d_sum = *d_sum, count_ptr] __device__(cudf::size_type idx) {
                     if (d_sum.is_null(idx)) {
                       // sum is null
                       return 0;
                     }
                     return d_sum.element<int32_t>(idx) / count_ptr[idx];
                   });
  return result;
}

}  // namespace detail

/**
 * @brief Aggregate sum and count for each group.
 * Input is a int column.
 * Output is a struct column: struct(sum, avg),
 * the num of rows is equal to num of groups.
 */
std::unique_ptr<cudf::column> group_average_example(
  cudf::column_view const& input,
  cudf::device_span<cudf::size_type const> group_offsets,
  rmm::cuda_stream_view stream,
  rmm::device_async_resource_ref mr)
{
  CUDF_FUNC_RANGE();
  return detail::group_avg(input, group_offsets, stream, mr);
}

/**
 * @brief Merge sums and counts in the same group.
 * Input is a struct column: struct(sum, avg).
 * Output is a struct column: struct(sum, avg), the num of rows is equal to num of groups.
 */
std::unique_ptr<cudf::column> group_merge_average_example(
  cudf::column_view const& input,
  cudf::device_span<cudf::size_type const> group_offsets,
  rmm::cuda_stream_view stream,
  rmm::device_async_resource_ref mr)
{
  CUDF_FUNC_RANGE();
  return detail::group_merge_avg(input, group_offsets, stream, mr);
}

/**
 * @brief Aggregate sum and count for all input rows.
 * Input is a int column.
 * Output is a struct scalar: struct(sum, avg).
 */
std::unique_ptr<cudf::scalar> reduce_average_example(cudf::column_view const& input,
                                                     rmm::cuda_stream_view stream,
                                                     rmm::device_async_resource_ref mr)
{
  CUDF_FUNC_RANGE();
  return detail::reduce_avg(input, stream, mr);
}

/**
 * @brief Merge all sum and count into one sum and count
 * Input is a struct column: struct(sum, avg).
 * Output is a struct scalar: struct(sum, avg).
 */
std::unique_ptr<cudf::scalar> reduce_merge_average_example(cudf::column_view const& input,
                                                           rmm::cuda_stream_view stream,
                                                           rmm::device_async_resource_ref mr)
{
  CUDF_FUNC_RANGE();
  return detail::reduce_merge_avg(input, stream, mr);
}

/**
 * @brief Compute average from sum and count.
 * Input is a struct column: struct(sum, avg).
 * Output is a int column.
 * This is the final step for both group and reduction average example.
 */
std::unique_ptr<cudf::column> compute_average_example(cudf::column_view const& input,
                                                      rmm::cuda_stream_view stream,
                                                      rmm::device_async_resource_ref mr)
{
  CUDF_FUNC_RANGE();
  return detail::compute_average_example(input, stream, mr);
}

}  // namespace examples
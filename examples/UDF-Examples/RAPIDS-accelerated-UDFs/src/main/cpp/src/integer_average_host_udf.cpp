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

#include "integer_average_host_udf.hpp"
#include "integer_average.hpp"

#include <cudf/column/column_factories.hpp>
#include <cudf/detail/iterator.cuh>

namespace examples {

namespace {

struct average_example_groupby_udf : cudf::groupby_host_udf {
  average_example_groupby_udf(bool is_merge_) : is_merge(is_merge_) {}

  /**
   * @brief Perform the main groupby computation for average_example UDF.
   */
  [[nodiscard]] std::unique_ptr<cudf::column> operator()(
    rmm::cuda_stream_view stream, rmm::device_async_resource_ref mr) const override
  {
    auto const group_values = get_grouped_values();
    if (group_values.size() == 0) { return get_empty_output(stream, mr); }
    auto const group_offsets = get_group_offsets();
    if (is_merge) {
      // input is a struct column: struct(sum, avg)
      return examples::group_merge_average_example(group_values, group_offsets, stream, mr);
    } else {
      // input is a int column
      return examples::group_average_example(group_values, group_offsets, stream, mr);
    }
  }

  /**
   * @brief Create an empty column when the input is empty for groupby UDF.
   * Create a struct(sum, count) column with zero rows.
   */
  [[nodiscard]] std::unique_ptr<cudf::column> get_empty_output(
    rmm::cuda_stream_view stream, rmm::device_async_resource_ref mr) const override
  {
    int num_long_cols       = 2;  // sum and count
    auto const results_iter = cudf::detail::make_counting_transform_iterator(
      0, [&](int i) { return cudf::make_empty_column(cudf::data_type{cudf::type_id::INT32}); });
    auto children =
      std::vector<std::unique_ptr<cudf::column>>(results_iter, results_iter + num_long_cols);
    return cudf::make_structs_column(0,
                                     std::move(children),
                                     0,                     // null count
                                     rmm::device_buffer{},  // null mask
                                     stream,
                                     mr);
  }

  [[nodiscard]] bool is_equal(cudf::host_udf_base const& other) const override
  {
    auto o = dynamic_cast<average_example_groupby_udf const*>(&other);
    return o != nullptr && o->is_merge == this->is_merge;
  }

  [[nodiscard]] std::size_t do_hash() const override
  {
    return 31 * std::hash<std::string>{}({"average_example_groupby_udf"}) + is_merge;
  }

  [[nodiscard]] std::unique_ptr<cudf::host_udf_base> clone() const override
  {
    return std::make_unique<average_example_groupby_udf>(is_merge);
  }

 private:
  bool is_merge;
};

struct average_example_reduction_udf : cudf::reduce_host_udf {
  average_example_reduction_udf(bool is_merge_) : is_merge(is_merge_) {}

  /**
   * @brief Create an empty scalar when the input is empty.
   */
  std::unique_ptr<cudf::scalar> get_empty_scalar(rmm::cuda_stream_view stream,
                                                 rmm::device_async_resource_ref mr) const
  {
    int num_long_cols       = 2;  // sum and count
    auto const results_iter = cudf::detail::make_counting_transform_iterator(
      0, [&](int i) { return cudf::make_empty_column(cudf::data_type{cudf::type_id::INT32}); });
    auto children =
      std::vector<std::unique_ptr<cudf::column>>(results_iter, results_iter + num_long_cols);
    return std::make_unique<cudf::struct_scalar>(
      cudf::table{std::move(children)}, true, stream, mr);
  }

  /**
   * @brief Perform the main reduce computation for average_example UDF.
   */
  std::unique_ptr<cudf::scalar> operator()(
    cudf::column_view const& input,
    cudf::data_type,                                           /** output_dtype is useless */
    std::optional<std::reference_wrapper<cudf::scalar const>>, /** init is useless */
    rmm::cuda_stream_view stream,
    rmm::device_async_resource_ref mr) const override
  {
    if (input.size() == 0) { return get_empty_scalar(stream, mr); }
    if (is_merge) {
      // input is a struct column: struct(sum, avg)
      return examples::reduce_merge_average_example(input, stream, mr);
    } else {
      // intput is a int column
      return examples::reduce_average_example(input, stream, mr);
    }
  }

  [[nodiscard]] bool is_equal(cudf::host_udf_base const& other) const override
  {
    auto o = dynamic_cast<average_example_reduction_udf const*>(&other);
    return o != nullptr && o->is_merge == this->is_merge;
  }

  [[nodiscard]] std::size_t do_hash() const override
  {
    return 31 * (31 * std::hash<std::string>{}({"average_example_reduction_udf"}) + is_merge);
  }

  [[nodiscard]] std::unique_ptr<cudf::host_udf_base> clone() const override
  {
    return std::make_unique<average_example_reduction_udf>(is_merge);
  }

 private:
  bool is_merge;
};

}  // namespace

cudf::host_udf_base* create_average_example_reduction_host_udf()
{
  return new average_example_reduction_udf(/*is_merge*/ false);
}

cudf::host_udf_base* create_average_example_reduction_merge_host_udf()
{
  return new average_example_reduction_udf(/*is_merge*/ true);
}

cudf::host_udf_base* create_average_example_groupby_host_udf()
{
  return new average_example_groupby_udf(/*is_merge*/ false);
}

cudf::host_udf_base* create_average_example_groupby_merge_host_udf()
{
  return new average_example_groupby_udf(/*is_merge*/ true);
}

}  // namespace examples
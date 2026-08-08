# Copyright (c) 2025, NVIDIA CORPORATION.
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

import pytest

from asserts import assert_gpu_and_cpu_are_equal_sql
from data_gen import *
from rapids_udf_test import drop_udf

def load_java_udaf(spark, udf_name, udf_class):
    drop_udf(spark, udf_name)
    spark.udf.registerJavaUDAF(udf_name, udf_class)


@pytest.mark.ignore_order(local=True)
@pytest.mark.rapids_udf_example_native
def test_java_udaf_integer_average_groupby():
    def two_cols_table(spark):
        load_java_udaf(spark, "int_avg", "com.nvidia.spark.rapids.udaf.java.IntegerAverage")
        group_gen = RepeatSeqGen(string_gen, 100)  # 100 groups at most
        int_value_gen = IntegerGen(min_val=-100, max_val=100)  # avoid integer overflow
        return two_col_df(spark, group_gen, int_value_gen)

    assert_gpu_and_cpu_are_equal_sql(
        two_cols_table,
        "int_avg_udaf_test_table",
        "SELECT a, int_avg(b) FROM int_avg_udaf_test_table GROUP BY a")


@pytest.mark.ignore_order(local=True)
@pytest.mark.rapids_udf_example_native
def test_java_udaf_integer_average_reduction():
    def int_col_table(spark):
        load_java_udaf(spark, "int_avg", "com.nvidia.spark.rapids.udaf.java.IntegerAverage")
        int_value_gen = IntegerGen(min_val=-100, max_val=100)  # avoid integer overflow
        return unary_op_df(spark, int_value_gen)

    assert_gpu_and_cpu_are_equal_sql(
        int_col_table,
        "int_avg_udaf_test_table",
        "SELECT int_avg(a) FROM int_avg_udaf_test_table")

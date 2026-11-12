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

"""Reads text files with the textlines source and prints the physical plan.

Usage: spark-submit --jars <plugin jar>,<example jar> demo.py <input path>
If the local input path does not exist, a small sample is written there first.
"""

import os
import sys

from pyspark.sql import SparkSession, functions as F

path = sys.argv[1]
spark = SparkSession.builder.appName("textlines-demo").getOrCreate()

if not os.path.exists(path):
    (spark.range(0, 2_000_000, numPartitions=8)
     .select(F.concat_ws(" ", F.lit("record"), F.col("id"),
                         F.sha2(F.col("id").cast("string"), 256)).alias("value"))
     .write.text(path))

lines = spark.read.format("textlines").option("includeBytes", "true").load(path)
result = (lines
          .groupBy(F.length("line").alias("length"))
          .agg(F.count("*").alias("lines"),
               F.max("offset").alias("max_offset"),
               # Decodes the binary column on the GPU
               F.sum((F.col("bytes").cast("string") == F.col("line")).cast("int"))
               .alias("bytes_match"))
          .orderBy("length"))
for row in result.collect():
    print(row)
# With adaptive query execution, the final plan is known only after the query ran. With the
# cuDF plugin, the BatchScan of TextLinesScan is followed by HostColumnarToGpu and GPU operators.
print(result._jdf.queryExecution().executedPlan().toString())
spark.stop()

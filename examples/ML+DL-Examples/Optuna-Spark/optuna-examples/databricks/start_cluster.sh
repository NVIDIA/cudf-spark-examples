#!/bin/bash
#
# Copyright (c) 2025-2026, NVIDIA CORPORATION.
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

if [[ -z ${INIT_PATH} ]]; then
    echo "Please export INIT_PATH per README.md"
    exit 1
fi

json_config=$(cat <<EOF
{
    "cluster_name": "optuna-xgboost-gpu",
    "spark_version": "13.3.x-gpu-ml-scala2.12",
    "spark_conf": {
        "spark.task.resource.gpu.amount": "1",
        "spark.executorEnv.PYTHONPATH": "/databricks/jars/rapids-4-spark_2.12-26.06.0.jar:/databricks/spark/python:/databricks/python3",
        "spark.executor.cores": "8",
        "spark.rapids.memory.gpu.minAllocFraction": "0.0001",
        "spark.plugins": "com.nvidia.spark.SQLPlugin",
        "spark.locality.wait": "0s",
        "spark.sql.cache.serializer": "com.nvidia.spark.ParquetCachedBatchSerializer",
        "spark.rapids.memory.gpu.pooling.enabled": "false",
        "spark.executor.resource.gpu.amount": "1",
        "spark.rapids.sql.explain": "NONE",
        "spark.sql.execution.sortBeforeRepartition": "false",
        "spark.rapids.sql.python.gpu.enabled": "true",
        "spark.rapids.memory.pinnedPool.size": "2G",
        "spark.task.maxFailures": "1",
        "spark.python.daemon.module": "rapids.daemon_databricks",
        "spark.rapids.sql.batchSizeBytes": "512m",
        "spark.sql.adaptive.enabled": "false",
        "spark.rapids.sql.format.parquet.reader.type": "MULTITHREADED",
        "spark.sql.execution.arrow.pyspark.enabled": "true",
        "spark.rapids.sql.format.parquet.multiThreadedRead.maxNumFilesParallel": "20",
        "spark.sql.files.maxPartitionBytes": "512m",
        "spark.rapids.sql.multiThreadedRead.numThreads": "20",
        "spark.rapids.sql.concurrentGpuTasks": "2"
    },
    "node_type_id": "Standard_NC8as_T4_v3",
    "driver_node_type_id": "Standard_NC8as_T4_v3",
    "spark_env_vars": {
        "LIBCUDF_CUFILE_POLICY": "OFF"
    },
    "autotermination_minutes": 60,
    "enable_elastic_disk": true,
    "init_scripts": [
        {
            "workspace": {
                "destination": "${INIT_PATH}"
            }
        }
    ],
    "runtime_engine": "STANDARD",
    "num_workers": 4
}
EOF
)

databricks clusters create --json "$json_config"
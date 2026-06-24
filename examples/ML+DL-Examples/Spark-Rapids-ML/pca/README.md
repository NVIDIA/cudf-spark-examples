# Spark-Rapids-ML PCA example

This is an example of the GPU accelerated PCA algorithm from the [Spark-Rapids-ML](https://github.com/NVIDIA/spark-rapids-ml) library, which provides PySpark ML compatible algorithms powered by RAPIDS cuML.
The notebook uses PCA to reduce a random dataset with 2048 feature dimensions to 3 dimensions. We train both the GPU and CPU algorithms for comparison.

## Build

Please refer to the Spark-Rapids-ML [README](https://github.com/NVIDIA/spark-rapids-ml/blob/HEAD/python) to setup the RAPIDS conda environment and install Spark-Rapids-ML dependencies.

## Download RAPIDS Jar from Maven Central

Download the [Spark-Rapids plugin](https://nvidia.github.io/spark-rapids/docs/download.html#download-rapids-accelerator-for-apache-spark-v26060).
For Spark-RAPIDS-ML version 26.06.0, download the RAPIDS jar from Maven Central: [rapids-4-spark_2.12-26.06.0.jar](https://repo1.maven.org/maven2/com/nvidia/rapids-4-spark_2.12/26.06.0/rapids-4-spark_2.12-26.06.0.jar).

## Running the Notebooks

Once you have built your environment, please follow these instructions to run the notebooks. Make sure `jupyterlab` is installed in the environment.

**Note**: for demonstration purposes, these examples just use a local Spark Standalone cluster with a single executor, but you should be able to run them on any distributed Spark cluster.
```
# setup environment variables
export SPARK_HOME=/path/to/spark
export RAPIDS_JAR=/path/to/rapids.jar

# launches the standalone cluster and jupyter with pyspark
./start-spark-rapids.sh

# BROWSE to localhost:8888 to view/run notebooks

# stop spark standalone cluster
${SPARK_HOME}/sbin/stop-worker.sh; ${SPARK_HOME}/sbin/stop-master.sh
```

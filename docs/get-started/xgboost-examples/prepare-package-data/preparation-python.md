## Prepare packages and dataset for pyspark

For simplicity export the location to these jars. All examples assume the packages and dataset will be placed in the `/opt/xgboost` directory:

### Download the jars

Download the RAPIDS Accelerator for Apache Spark plugin jar
  * [RAPIDS Spark Package](https://repo1.maven.org/maven2/com/nvidia/rapids-4-spark_2.12/26.06.0/rapids-4-spark_2.12-26.06.0.jar)

### Build XGBoost Python Examples

Following this [guide](/docs/get-started/xgboost-examples/building-sample-apps/python.md), you can get *samples.zip* and *main.py* and copy them to `/opt/xgboost`

### Download dataset

You need to copy the dataset to `/opt/xgboost`. Use the following links to download the data.
1. [Mortgage dataset](/docs/get-started/xgboost-examples/dataset/mortgage.md)
2. [Taxi dataset](https://www1.nyc.gov/site/tlc/about/tlc-trip-record-data.page)
3. [Agaricus dataset](https://github.com/dmlc/xgboost/tree/master/demo/data)

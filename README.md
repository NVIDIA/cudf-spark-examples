# spark-rapids-examples

This is the [NVIDIA cuDF plugin for Apache Spark](https://nvidia.github.io/cudf-spark/) examples repo.
The cuDF plugin accelerates Spark applications with no code changes.
You can download the latest version of the cuDF plugin [here](https://nvidia.github.io/cudf-spark/docs/download.html).
This repo contains examples and applications that showcases the performance and benefits of using 
the cuDF plugin in data processing and machine learning pipelines.
There are broadly five categories of examples in this repo: 
1. [SQL/Dataframe](./examples/SQL+DF-Examples) 
2. [Spark XGBoost](./examples/XGBoost-Examples) 
3. [Machine Learning/Deep Learning](./examples/ML+DL-Examples) 
4. [cuDF plugin UDF](./examples/UDF-Examples)
5. [Databricks Tools demo notebooks](./tools/databricks)

For more information on each of the examples please look into respective categories.

Here is the list of notebooks in this repo:

|   | Category  | Notebook Name | Description
| ------------- | ------------- | ------------- | -------------
| 1 | SQL/DF | Microbenchmark | Spark SQL operations such as expand, hash aggregate, windowing, and cross joins with up to 20x performance benefits
| 2 | SQL/DF | Customer Churn | Data federation for modeling customer Churn with a sample telco customer data
| 3 | XGBoost | Agaricus (Scala) | Uses XGBoost classifier function to create model that can accurately differentiate between edible and poisonous mushrooms with the [agaricus dataset](https://archive.ics.uci.edu/ml/datasets/mushroom)
| 4 | XGBoost | Mortgage (Scala) | End-to-end ETL + XGBoost example to predict mortgage default with [Fannie Mae Single-Family Loan Performance Data](https://capitalmarkets.fanniemae.com/credit-risk-transfer/single-family-credit-risk-transfer/fannie-mae-single-family-loan-performance-data)
| 5 | XGBoost | Taxi (Scala) | End-to-end ETL + XGBoost example to predict taxi trip fare amount with [NYC taxi trips data set](https://www1.nyc.gov/site/tlc/about/tlc-trip-record-data.page)
| 6 | ML/DL | PCA | [Spark-Rapids-ML](https://github.com/NVIDIA/spark-rapids-ml) based PCA example to train and transform with a synthetic dataset
| 7 | ML/DL | DL Inference | Several notebooks demonstrating distributed model inference on Spark using the `predict_batch_udf` across various frameworks: PyTorch, HuggingFace, vLLM, and TensorFlow
| 8 | SQL/DF + MLlib | GPU-Accelerated Spark Connect | End-to-end SQL/DF + MLlib acceleration to predict mortgage default with [Fannie Mae Single-Family Loan Performance Data](https://capitalmarkets.fanniemae.com/credit-risk-transfer/single-family-credit-risk-transfer/fannie-mae-single-family-loan-performance-data) using the lightweight Spark Connect integration for Apache Spark 4.0+
| 9 | SQL/DF | [TPC-DS](https://www.tpc.org/tpcds/) Scale Factor 10 | Comparison of Spark SQL CPU vs GPU. Easy to run locally and on Google Colab

Here is the list of Apache Spark applications (Scala and PySpark) that 
can be built for running on GPU with the cuDF plugin in this repo:

|   | Category  | Notebook Name | Description
| ------------- | ------------- | ------------- | -------------
| 1 | XGBoost | Agaricus (Scala) | Uses XGBoost classifier function to create model that can accurately differentiate between edible and poisonous mushrooms with the [agaricus dataset](https://archive.ics.uci.edu/ml/datasets/mushroom)
| 2 | XGBoost | Mortgage (Scala) | End-to-end ETL + XGBoost example to predict mortgage default with [Fannie Mae Single-Family Loan Performance Data](https://capitalmarkets.fanniemae.com/credit-risk-transfer/single-family-credit-risk-transfer/fannie-mae-single-family-loan-performance-data)
| 3 | XGBoost | Taxi (Scala) | End-to-end ETL + XGBoost example to predict taxi trip fare amount with [NYC taxi trips data set](https://www1.nyc.gov/site/tlc/about/tlc-trip-record-data.page)
| 4 | ML/DL | PCA | [Spark-Rapids-ML](https://github.com/NVIDIA/spark-rapids-ml) based PCA example to train and transform with a synthetic dataset
| 5 | UDF | URL Decode | Decodes URL-encoded strings using the [Java APIs of RAPIDS cudf](https://docs.rapids.ai/api/cudf-java/legacy/)
| 6 | UDF | URL Encode | URL-encodes strings using the [Java APIs of RAPIDS cudf](https://docs.rapids.ai/api/cudf-java/legacy/)
| 7 | UDF | [CosineSimilarity](./examples/UDF-Examples/RAPIDS-accelerated-UDFs/src/main/java/com/nvidia/spark/rapids/udf/java/CosineSimilarity.java) | Computes the cosine similarity between two float vectors using [native code](./examples/UDF-Examples/RAPIDS-accelerated-UDFs/src/main/cpp/src)
| 8 | UDF | [StringWordCount](./examples/UDF-Examples/RAPIDS-accelerated-UDFs/src/main/java/com/nvidia/spark/rapids/udf/hive/StringWordCount.java)  | Implements a Hive simple UDF using [native code](./examples/UDF-Examples/RAPIDS-accelerated-UDFs/src/main/cpp/src) to count words in strings

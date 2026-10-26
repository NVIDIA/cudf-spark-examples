# Spark XGBoost Examples

Spark XGBoost examples here showcase the need for ETL+Training pipeline GPU acceleration.
The Scala based XGBoost examples here use [DMLC’s version](https://repo1.maven.org/maven2/ml/dmlc/xgboost4j-spark_2.12/).
The pyspark based XGBoost examples requires [installing RAPIDS via pip](https://rapids.ai/pip.html#install).
Most data scientists spend a lot of time not only on
Training models but also processing the large amounts of data needed to train these models.
As shown below, PySpark and XGBoost training on GPUs can be up to 13X faster, while data processing with
the NVIDIA cuDF plugin for Apache Spark can deliver an end-to-end speedup of 11X over CPU execution.
In the public cloud, better performance can lead to significantly lower costs as demonstrated in this [blog](https://developer.nvidia.com/blog/gpu-accelerated-spark-xgboost/).

![mortgage-speedup](/docs/img/guides/mortgage-perf.png)

Note that the Training test result is based on 4 years [Fannie Mea Single-Family Loan Performance Data](https://capitalmarkets.fanniemae.com/credit-risk-transfer/single-family-credit-risk-transfer/fannie-mae-single-family-loan-performance-data) 
with a 8 A100 GPU and 1024 CPU vcores cluster, the performance is affected by many aspects, 
including data size and type of GPU. 

In this folder, there are three blue prints for users to learn about using 
Spark XGBoost and the cuDF plugin on GPUs:

1. Mortgage Prediction
2. Agaricus Classification
3. Taxi Fare Prediction

For each of these examples we have prepared a [sample dataset](/datasets) 
in this folder for testing. These datasets are only provided for convenience. In order to test for performance,
please download the larger dataset from their respectives sources.

There are three sections in this readme section. 
In the first section, we will list the notebooks that can be run on Jupyter with Python or Scala
([Spylon Kernel](https://pypi.org/project/spylon-kernel/) or [Apache Toree Kernel](https://toree.apache.org/)). 

In the second section, we have sample jar files and source code if users would like to build 
and run this as a Scala or a PySpark Spark-XGBoost application. 

In the last section, we provide basic “Getting Started Guides” for setting up GPU
Spark-XGBoost on different environments based on the Apache Spark scheduler such as YARN,
Standalone or Kubernetes.

## SECTION 1: SPARK-XGBOOST EXAMPLE NOTEBOOKS

1. Mortgage Notebooks
   - Python
     - [Mortgage ETL](mortgage/notebooks/python/MortgageETL.ipynb)
     - [Mortgage Training Prediction](mortgage/notebooks/python/mortgage-gpu.ipynb)
     - [Mortgage ETL + XGBoost Training](mortgage/notebooks/python/MortgageETL+XGBoost.ipynb)
   - Scala
     - [Mortgage ETL](mortgage/notebooks/scala/mortgage-ETL.ipynb)
     - [Mortgage Training Prediction](mortgage/notebooks/scala/mortgage-gpu.ipynb)
2. Agaricus Notebooks    
   - Python
     - [Agaricus Training Classification](agaricus/notebooks/python/agaricus-gpu.ipynb)
   - Scala
     - [Agaricus Training Classification](agaricus/notebooks/scala/agaricus-gpu.ipynb)
3. Taxi Notebook    
   - Python
     - [Taxi Training Classification](taxi/notebooks/python/taxi-gpu.ipynb)
   - Scala    
     - [Taxi Training Classification](taxi/notebooks/scala/taxi-gpu.ipynb)
    
## SECTION 2: BUILDING A PYSPARK OR A SCALA XGBOOST APPLICATION
The first step to build a Spark application is preparing packages and datasets
needed to build the jars. Please use the instructions below for building the

- [Scala](/docs/get-started/xgboost-examples/prepare-package-data/preparation-scala.md)
- [Python](/docs/get-started/xgboost-examples/prepare-package-data/preparation-python.md)

In addition, we have the source code for building reference applications. 
Below are source codes for the example Spark jobs:
- Mortgage: [Scala](mortgage/scala/src/com/nvidia/spark/examples/mortgage), [Python](mortgage/python/com/nvidia/spark/examples/mortgage)
- Taxi: [Scala](taxi/scala/src/com/nvidia/spark/examples/taxi), [Python](taxi/python/com/nvidia/spark/examples/taxi)
- Agaricus: [Scala](agaricus/scala/src/com/nvidia/spark/examples/agaricus), [Python](agaricus/python/com/nvidia/spark/examples/agaricus)


## SECTION 3: SETTING UP THE ENVIRONMENT
Please follow below steps to run the example Spark jobs in different Spark environments:
- Getting started on on-premises clusters
    - [Standalone cluster for Scala](/docs/get-started/xgboost-examples/on-prem-cluster/standalone-scala.md)
    - [Standalone cluster for Python](/docs/get-started/xgboost-examples/on-prem-cluster/standalone-python.md)
    - [YARN for Scala](/docs/get-started/xgboost-examples/on-prem-cluster/yarn-scala.md)
    - [YARN for Python](/docs/get-started/xgboost-examples/on-prem-cluster/yarn-python.md)
    - [Kubernetes](/docs/get-started/xgboost-examples/on-prem-cluster/kubernetes-scala.md)
- Getting started on cloud service providers    
  - Amazon AWS
    - [EC2](/docs/get-started/xgboost-examples/csp/aws/ec2.md)
  - [Databricks](/docs/get-started/xgboost-examples/csp/databricks/databricks.md)
  - [GCP](/docs/get-started/xgboost-examples/csp/dataproc/gcp.md)
    
Please follow below steps to run the example notebooks in different notebook environments:

- Getting started for Jupyter Notebook applications
    - [Apache Toree Notebook for Scala](/docs/get-started/xgboost-examples/notebook/toree.md)
    - [Jupyter Notebook with spylon kernel](/docs/get-started/xgboost-examples/notebook/spylon.md)
    - [Jupyter Notebook for Python](/docs/get-started/xgboost-examples/notebook/python-notebook.md)
    
Note: 
Update the default value of `spark.sql.execution.arrow.maxRecordsPerBatch` to a larger number(such as 200000) will  
significantly improve performance by accelerating data transfer between JVM and Python process.

For the CrossValidator job, we need to set `spark.task.resource.gpu.amount=1` to allow only 1 training task running on 1 GPU(executor),
otherwise the customized CrossValidator may schedule more than 1 xgboost training tasks into one executor simultaneously and trigger 
[issue-131](https://github.com/NVIDIA/spark-rapids-examples/issues/131).
For XGBoost job, if the number of shuffle stage tasks before training is less than the num_worker, 
the training tasks will be scheduled to run on part of nodes instead of all nodes due to Spark Data Locality feature.
The workaround is to increase the partitions of the shuffle stage by setting `spark.sql.files.maxPartitionBytes=RightNum`.
If you are running XGBoost scala notebooks on Dataproc, please make sure to update below configs to avoid job failure:
```
spark.dynamicAllocation.enabled=false
spark.task.resource.gpu.amount=1
```
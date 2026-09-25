# TPC-DS Scale Factor 10 (GiB) - CPU Spark vs GPU Spark

[TPC-DS](https://www.tpc.org/tpcds/) is a decision support benchmark often used to evaluate
performance of OLAP Databases and Big Data systems.

The notebook in this folder runs a user-specified subset of the TPC-DS queries on the
Scale Factor 10 (GiB) dataset. It uses [TPCDS PySpark](https://github.com/cerndb/SparkTraining/blob/master/notebooks/TPCDS_PySpark_CERN_SWAN_getstarted.ipynb)
to execute TPC-DS queries with SparkSQL on GPU and CPU capturing the metrics
as a Pandas dataframe. It then plots a comparison bar chart visualizing
the GPU acceleration achieved for the queries run with RAPIDS Spark in this
very notebook.

This notebook can be opened and executed using standard

- Jupyter(Lab)
- in VSCode with Jupyter [extension](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter)

It can also be opened and evaluated on hosted Notebook environments. Use the link below to launch on
Google Colab and connect it to a [GPU instance](https://research.google.com/colaboratory/faq.html).

 <a target="_blank" href="https://colab.research.google.com/github/NVIDIA/spark-rapids-examples/blob/main/examples/SQL%2BDF-Examples/tpcds/notebooks/TPCDS-SF10.ipynb">
  <img src="https://colab.research.google.com/assets/colab-badge.svg" alt="Open In Colab"/>
</a>

Here is the bar chart from a recent execution on Google Colab's T4 High RAM instance using
RAPIDS Spark 26.06.0 with Apache Spark 3.5.0

![tpcds-speedup](/docs/img/guides/tpcds.png)

## Execute the notebook on Dataproc

### 1. Create a Dataproc cluster

```
export OS_VERSION=ubuntu22
export CLUSTER_NAME=test-$OS_VERSION
export GCS_BUCKET=mybucket
export REGION=us-central1
export ZONE=us-central1-a
export NUM_GPUS=1
export NUM_WORKERS=2

PROPERTIES=(
    "spark:spark.history.fs.logDirectory=gs://$GCS_BUCKET/eventlog/"
    "spark:spark.eventLog.dir=gs://$GCS_BUCKET/eventlog/"
    "spark:spark.history.fs.gs.outputstream.type=FLUSHABLE_COMPOSITE"
    "spark:spark.history.fs.gs.outputstream.sync.min.interval.ms=60000"
    "spark:spark.driver.memory=20g"
    "spark:spark.executor.memory=42g"
    "spark:spark.executor.memoryOverhead=8g"
    "spark:spark.executor.cores=16"
    "spark:spark.executor.instances=2"
    "spark:spark.task.resource.gpu.amount=0.001"
    "spark:spark.sql.files.maxPartitionBytes=512M"
    "spark:spark.rapids.memory.pinnedPool.size=4g"
    "spark:spark.shuffle.manager=com.nvidia.spark.rapids.spark353.RapidsShuffleManager"
    "spark:spark.jars.packages=ch.cern.sparkmeasure:spark-measure_2.12:0.27"
)

gcloud dataproc clusters create $CLUSTER_NAME  \
    --region $REGION \
    --zone $ZONE \
    --image-version=2.3-$OS_VERSION \
    --master-machine-type n1-standard-16 \
    --master-boot-disk-size 200 \
    --num-workers $NUM_WORKERS \
    --worker-accelerator type=nvidia-tesla-t4,count=$NUM_GPUS \
    --worker-machine-type n1-standard-16 \
    --num-worker-local-ssds 2 \
    --initialization-actions gs://goog-dataproc-initialization-actions-${REGION}/spark-rapids/spark-rapids.sh \
    --optional-components=JUPYTER,ZEPPELIN \
    --metadata gpu-driver-provider="NVIDIA",rapids-runtime="SPARK" \
    --no-shielded-secure-boot \
    --bucket $GCS_BUCKET \
    --subnet=default \
    --properties="$(IFS=,; echo "${PROPERTIES[*]}")" \
    --enable-component-gateway

```

Note: Please adjust the value of `spark.shuffle.manager` based on the Spark version of the Dataproc cluster version.

### 2. Execute the example notebook in Jupyter lab

[TPCDS-SF3K-Dataproc.ipynb](notebooks/TPCDS-SF3K-Dataproc.ipynb)



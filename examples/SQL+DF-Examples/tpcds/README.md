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

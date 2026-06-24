# Databricks Qualification/Profiling Quick Start Notebooks

The RAPIDS Accelerator for Apache Spark includes two key tools for understanding the benefits of
GPU acceleration as well as analyzing GPU Spark jobs.  For customers on Databricks, the quick start notebooks offer a simple interface for running the tools given a set of Spark event logs from
CPU (qualification) or GPU (profiling) application runs.

To use a demo notebook, you can import the notebook in the Databricks Notebook UI via File->Import Notebook.

Once the demo notebook is imported, you can select run to activate the notebook to an available compute
cluster.  Once the notebook is activated, you can enter in the log path location in the text widget at the
top of the notebook.  After that, select *Run all* to execute the tools for the specific logs in the log path.

## Limitations
1. Currently local, S3 or DBFS event log paths are supported.
1. S3 path is only supported on Databricks AWS using [instance profiles](https://docs.databricks.com/en/connect/storage/tutorial-s3-instance-profile.html).
1. Eventlog path must follow the formats `/dbfs/path/to/eventlog` or `dbfs:/path/to/eventlog` for logs stored in DBFS.
1. Use wildcards for nested lookup of eventlogs. 
   - For example: `/dbfs/path/to/clusterlogs/*/*`
1. Multiple event logs must be comma-separated. 
   - For example: `/dbfs/path/to/eventlog1,/dbfs/path/to/eventlog2`

**Latest Tools Version Supported** 26.06.0
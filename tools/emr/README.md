# EMR Qualification/Profiling Quick Start Notebooks

The NVIDIA cuDF plugin for Apache Spark provides two key tools for understanding the benefits of
GPU acceleration as well as analyzing GPU Spark jobs.  For customers on EMR, the quick start
notebooks offer a simple interface for running the tools given a set of Spark event logs from
CPU (qualification) or GPU (profiling) application runs.

## Usage

### Pre-requisites: Setup EMR Studio and Workspace
1. Ensure that you have an **EMR cluster** running.
2. Set up **EMR Studio** and **Workspace** by following the instructions in the [AWS Documentation](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-studio-create-studio.html):
   - Select **Custom Settings** while creating the Studio.
   - Choose the **VPC** and **Subnet** where the EMR cluster is running.
3. Attach the Workspace to the running EMR cluster. For more details, refer to the [AWS Documentation](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-studio-create-use-clusters.html).

### Running the Notebook
1. Import the notebook into the EMR Workspace by dragging and dropping the notebook file.
2. In the **User Input** section of the notebook, enter the path to event log files.
3. Click the **fast-forward** icon labeled *Restart the kernel, then re-run the whole notebook* to process the logs at the specified path.

## Limitations
1. Currently, local and S3 event log paths are supported.
1. Eventlog path must follow the formats `/local/path/to/eventlog` for local logs or `s3://my-bucket/path/to/eventlog` for logs stored in S3.
1. The specified path can also be a directory. In such cases, the tool will recursively search for event logs within the directory.
   - For example: `/path/to/clusterlogs`
1. To specify multiple event logs, separate the paths with commas.
   - For example: `s3://my-bucket/path/to/eventlog1,s3://my-bucket/path/to/eventlog2`

**Latest Tools Version Supported** 24.08.2

# Spark DL Inference on Databricks

**Note**: fields in \<brackets\> require user inputs.  
Make sure you are in [this](./) directory.

## Setup

1. Install the latest [databricks-cli](https://docs.databricks.com/en/dev-tools/cli/tutorial.html) and configure for your workspace.

2. Specify the path to your Databricks workspace:
    ```shell
    export WS_PATH=</Users/someone@example.com>
    ```

    ```shell
    export SPARK_DL_WS=${WS_PATH}/spark-dl
    databricks workspace mkdirs ${SPARK_DL_WS}
    ```
3. Specify the local paths to the notebook you wish to run.
    As an example for a PyTorch notebook:
    ```shell
    export NOTEBOOK_SRC=</path/to/notebook_torch.ipynb>
    ```
4. Specify the framework to torch, tf, or vllm, corresponding to the notebook you wish to run. Continuing with the PyTorch example:
    ```shell
    export FRAMEWORK=torch
    ```
    This will tell the init script which libraries to install on the cluster.

5. Copy the notebook, the utils file, and the init script to the Databricks Workspace:
    ```shell
    databricks workspace import ${SPARK_DL_WS}/$(basename "$NOTEBOOK_SRC") --format JUPYTER --file $NOTEBOOK_SRC
    databricks workspace import ${SPARK_DL_WS}/server_utils.py --format AUTO --file $(realpath ../server_utils.py)
    databricks workspace import ${SPARK_DL_WS}/init_spark_dl.sh --format AUTO --file $(pwd)/setup/init_spark_dl.sh
    ```

6. Launch the cluster with the provided script with the argument `aws` or `azure` based on your provider. Modify the scripts if you do not have the specific instance types. By default the script will create a cluster with 2 A10 workers and 1 A10 driver. 
    ```shell
    cd setup
    chmod +x start_cluster.sh
    ./start_cluster.sh aws  # or ./start_cluster.sh azure
    ```
    To create a cluster capable of tensor parallelism, include the argument `tp` to acquire multiple GPUs per node:
    ```shell
    ./start_cluster.sh aws tp  # or ./start_cluster.sh azure tp
    ```
    In this case, the Azure worker nodes will have 2 GPUs each and the AWS workers will have 4 GPUs each (since AWS does not have an instance type with 2 GPUs) to run the tensor parallel example.* 

7. Navigate to the notebook in your workspace and attach it to the cluster. The default cluster name is `spark-dl-inference-$FRAMEWORK`.  

*Note that the NVIDIA cuDF plugin for Apache Spark is not compatible with this case, since [multiple GPUs per executor are not yet supported](https://docs.nvidia.com/spark-rapids/user-guide/latest/faq.html#why-are-multiple-gpus-per-executor-not-supported).
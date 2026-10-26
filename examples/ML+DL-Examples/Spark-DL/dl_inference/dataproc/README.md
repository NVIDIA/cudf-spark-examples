# Spark DL Inference on Dataproc

## Setup

**Note**: fields in \<brackets\> require user inputs.  
Make sure you are in [this](./) directory.

#### Setup GCloud CLI

1. Install the latest [gcloud-cli](https://cloud.google.com/sdk/docs/install) and initialize with `gcloud init`.

2. Configure the following settings:
    ```shell
    export PROJECT=<your_project>
    export DATAPROC_REGION=<your_dataproc_region>
    export COMPUTE_REGION=<your_compute_region>
    export COMPUTE_ZONE=<your_compute_zone>

    gcloud config set project ${PROJECT}
    gcloud config set dataproc/region ${DATAPROC_REGION}
    gcloud config set compute/region ${COMPUTE_REGION}
    gcloud config set compute/zone ${COMPUTE_ZONE}
    ```

#### Copy files to GCS

3. Create a GCS bucket if you don't already have one:
    ```shell
    export GCS_BUCKET=<your_gcs_bucket_name>

    gcloud storage buckets create gs://${GCS_BUCKET} 
    ```

4.  Specify the local path to the notebook(s) and copy to the GCS bucket.
    As an example for a torch notebook:
    ```shell
    export SPARK_DL_HOME=${GCS_BUCKET}/spark-dl
    
    gcloud storage cp </path/to/notebook_name_torch.ipynb> gs://${SPARK_DL_HOME}/notebooks/
    ```
    Repeat this step for any notebooks you wish to run. All notebooks under `gs://${SPARK_DL_HOME}/notebooks/` will be copied to the master node during initialization.

5. Copy the utils file to the GCS bucket.
    ```shell
    gcloud storage cp $(realpath ../server_utils.py) gs://${SPARK_DL_HOME}/
    ```

#### Start cluster and run

5. Specify the framework to use (torch, tf, or vllm), which will determine what libraries to install on the cluster. For example:
    ```shell
    export FRAMEWORK=torch
    ```
    Run the cluster startup script. The script will also retrieve and use the [spark-rapids initialization script](https://github.com/GoogleCloudDataproc/initialization-actions/blob/master/spark-rapids/spark-rapids.sh) to setup GPU resources. The script will create 2 L4 worker nodes and 1 L4 driver node by default, named `${USER}-spark-dl-inference-${FRAMEWORK}`. 
    ```shell
    cd setup
    chmod +x start_cluster.sh
    ./start_cluster.sh
    ```
    To create a cluster capable of tensor parallelism, include the argument `tp` to acquire multiple GPUs per node:
    ```shell
    ./start_cluster.sh tp
    ```
    In this case, the worker nodes will have 2 L4s each to run the tensor parallel example.*

7. Browse to the Jupyter web UI:
    - Go to `Dataproc` > `Clusters` > `(Cluster Name)` > `Web Interfaces` > `Jupyter/Lab`
    
    Or, get the link by running this command (under httpPorts > Jupyter/Lab):
    ```shell
    gcloud dataproc clusters describe ${CLUSTER_NAME} --region=${COMPUTE_REGION}
    ```

8. Open and run the notebook interactively with the **Python 3 kernel**.  
The notebooks can be found under `Local Disk/spark-dl-notebooks` on the master node (folder icon on the top left > Local Disk).

*Note that the NVIDIA cuDF plugin for Apache Spark is not applicable in this case, since [multiple GPUs per executor are not yet supported](https://docs.nvidia.com/spark-rapids/user-guide/latest/faq.html#why-are-multiple-gpus-per-executor-not-supported).
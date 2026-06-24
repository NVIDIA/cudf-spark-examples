# GPU-Accelerated Spark Connect Server

This project demonstrates how to set up a GPU-accelerated Spark server using Apache Spark 4.0
with Spark Connect, featuring the RAPIDS Accelerator.

## 🚀 Key Features

- **Apache Spark 4.0** with cutting-edge Spark Connect capabilities
- **GPU acceleration** via RAPIDS Accelerator
- **MLlib over Spark Connect** - new in Spark 4.0
- **Zero-code-change acceleration** - existing Spark applications automatically benefit
- **Jupyter Lab integration** for interactive development
- **Docker Compose** setup for easy deployment with clear distinction what dependencies are
required by what service and where GPUs are really used

## 🏗️ Architecture

The setup consists of four Docker services:

### Apache Spark Standalone Cluster 
1. **Spark Master** (`spark-master`) - Cluster coordination and job scheduling. This container does 
not have GPU capability

2. **Spark Worker** (`spark-worker`) - GPU-enabled worker node for task execution. This is the only 
service requiring and having access to the host GPUs 

### Middle Tier 
3. **Spark Connect Server** (`spark-connect-server`) - gRPC interface with the RAPIDS integration

### Proxy Service
4. nginx configured as provide access to various Apache Spark WebUI using the Docker network

### Frontend Web Browser
5. WebUI for the Spark Connect Server and the Spark Standalone Cluster

To reduce the complexity of the demo, no services for global storage is included.
The demo relies on the **DATA_DIR** location mounted from the host in place of a storage
service. This location is also used for convenience to preserve metrics and
Spark event logs beyond the container life cycle for analysis or debugging.

When the **DATA_DIR** is accessed in a way that would normally require a global access
we indicate this by using the `global_` prefix for the variable storing the complete
path. Otherwise, we use variables starting with `local_`.

## 📋 Prerequisites

### Required
- [Docker](https://docs.docker.com/engine/install/) and [Docker Compose](https://docs.docker.com/compose/install/linux)
- At least 8GB of available RAM
- Available ports: 2080, 8080, 8081, 8888, 7077, 4040, 15002

### For GPU Acceleration
- NVIDIA GPU with CUDA compute capability supported by RAPIDS
- [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- Docker Compose version should be `2.30.x` or newer to avoid an NVIDIA Container Toolkit related bug.  [Update](https://docs.docker.com/compose/install/linux) if necessary
- CUDA 12.x drivers

## 🚀 Quick Start

1. **Clone and navigate to the project:**
   ```bash
   cd examples/spark-connect-gpu/server
   ```

2. **Set up data directory (if needed):**
   ```bash
   export DATA_DIR=$(pwd)/data
   mkdir -p $DATA_DIR/mortgage.input.csv $DATA_DIR/spark-events $DATA_DIR/nds
   chmod 1777 $DATA_DIR $DATA_DIR/spark-events 
   ```
   Download a few quarters worth of the [Mortgage Dataset](https://capitalmarkets.fanniemae.com/credit-risk-transfer/single-family-credit-risk-transfer/fannie-mae-single-family-loan-performance-data)
   to the `$DATA_DIR/mortgage.input.csv` location. More details can refer to [How to download the Mortgage dataset](https://github.com/NVIDIA/spark-rapids-examples/blob/main/docs/get-started/xgboost-examples/dataset/mortgage.md)

   To run NDS (see [NDS v2.0 Automation](https://github.com/NVIDIA/spark-rapids-benchmarks/tree/dev/nds#nds-v20-automation)),
   generate the dataset and place it in "$DATA_DIR/nds". For more details,
   refer to [NDS Data Generation](https://github.com/NVIDIA/spark-rapids-benchmarks/tree/dev/nds#data-generation).

3. **Start all services:**

   ```bash
   $ docker compose up -d
   ```
   (`docker compose` can be used in place of `docker-compose` here and throughout)

4. **Access the Web UI interfaces:**

   ***Option 1 (default)***

   All containers' webUI are available using localhost URI's by default

   - **Spark Master UI**: http://localhost:8080 - Cluster coordination and resource management
   - **Spark Worker UI**: http://localhost:8081 - GPU-enabled worker node status and tasks
   - **Spark Driver UI**: http://localhost:4040 - Application monitoring and SQL queries
    
   ***Option 2***

   if you launch docker compose in the environment with `SPARK_PUBLIC_DNS=container-hostname`, all containers'
   web UI but Jupyter Lab is available using the corresponding container host names such as spark-master
  
   - **Spark Master UI**: http://spark-master:8080 - Cluster coordination and resource management
   - **Spark Worker UI**: http://spark-worker:8081 - GPU-enabled worker node status and tasks
   - **Spark Driver UI**: http://spark-connect-server:4040 - Application monitoring and SQL queries
   
   Docker DNS names require configuring your browser an http proxy on the Docker network exposed at http://localhost:2080.
  
   Here are examples of launching Google Chrome with a temporary user profile without making persistent changes on the browser

   ***Linux***

   ```bash
   $ google-chrome --user-data-dir="/tmp/chrome-proxy-profile" --proxy-server="http=http://localhost:2080"
   ```

   ***macOS***

   ```bash
   $ open -n -a "Google Chrome" --args --user-data-dir="/tmp/chrome-proxy-profile" --proxy-server="http=http://localhost:2080"
   ```

   ***Launching containers on a remote machine***

   Your local machine might not have a GPU, and it is common in this case to use a
   remote machine/cluster with GPUs residing in a remote Cloud or on-prem environment

   If you followed the default Option 1 make sure to create local port forwards for
   every webUI port

   ```bash
   ssh <user@gpu-host> -L 8888:localhost:8888 -L 8080:localhost:8080 -L 8081:localhost:8081 -L 4040:localhost:4040
   ```

   if you used Option 2 it is sufficient to forward ports only for the HTTP proxy and the Notebook app:
  
   ```bash
   ssh <user@gpu-host> -L 2080:localhost:2080 -L 8888:localhost:8888
   ```

## 🐳 Service Details

### Spark Master
- **Image**: `apache/spark:4.0.0`
- **Ports**: 8080 (Web UI), 7077 (Master)
- **Role**: Cluster coordination and resource management

### Spark Worker (the only GPU node role)
- **Image**: Custom build based on `apache/spark:4.0.0`
- **GPU**: NVIDIA GPU support via Docker Compose deploy configuration
- **Ports**: 8081 (Web UI)
- **Features**: GPU resource discovery and task execution

### Spark Connect Server
- **Image**: Custom build based on `apache/spark:4.0.0` with Spark RAPIDS ETL and ML Plugins
- **RAPIDS Version**: 26.06.0 for CUDA 12
- **Ports**: 15002 (gRPC), 4040 (Driver UI)
- **Configuration**: Optimized for GPU acceleration with memory management

## 📊 Performance Monitoring

You can use tools like nvtop, nvitop, btop or jupyterlab_nvdashboard running on the GPU host(s)


## 🧹 Cleanup

Stop and remove all services:
```bash
docker-compose down -v
```

Remove built images:
```bash
docker-compose down --rmi all -v
```

### Logs
Logs for the spark driver/connect server, standalone master, standalone worker, and jupyter server can be viewed using the respective commands:
```bash
docker logs spark-connect-server
docker logs spark-master
docker logs spark-worker
```

Spark executor logs can be accessed via the Spark UI as usual.

## 📖 Additional Resources

- [Apache Spark 4.0 Documentation](https://spark.apache.org/docs/latest/)
- [Spark Connect Guide](https://spark.apache.org/docs/latest/spark-connect-overview.html)
- [NVIDIA RAPIDS Accelerator](https://nvidia.github.io/spark-rapids/)
- [Data and AI Summit Session](https://www.databricks.com/dataaisummit/session/gpu-accelerated-spark-connect)

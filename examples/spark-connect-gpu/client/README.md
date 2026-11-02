# GPU-Accelerated Spark Connect for ETL and ML (Spark 4.0)

This project demonstrates some python/scala batch jobs and a complete GPU-accelerated ETL and
Machine Learning pipeline using Apache Spark 4.0 with Spark Connect, featuring the NVIDIA cuDF plugin for Apache Spark.

## 🏗️ Architecture

The client side consists of one Docker services:

**Jupyter Lab - Spark Connect Client** (`spark-connect-client`) - Interactive development environment

The first step, however, is to set up the GPU-accelerated Spark Connect Server. More details can be
found [here](../server/README.md).

## 📋 Prerequisites

### Required
- [Docker](https://docs.docker.com/engine/install/) and [Docker Compose](https://docs.docker.com/compose/install/linux)
- At least 8GB of available RAM
- Available ports: 8888

## 🚀 Quick Start

1. **Clone and navigate to the project:**
   ```bash
   cd examples/spark-connect-gpu/client
   ```

2. **Start all services:**

   Set the `SPARK_REMOTE` environment variable to point to your spark-connect-gpu server. By default
   this is `sc://localhost` (for same node deployments). If the client and server are on `different nodes`,
   you can either establish an SSH tunnel with port 15002 forwarded (e.g., `ssh -g -L 15002:localhost:15002 -N CONNECT_SERVER_IP`)
   and use the default `SPARK_REMOTE` value (`sc://localhost`), or override it with the server’s accessible IP address:

   ``` bash
   export SPARK_REMOTE=sc://CONNECT_SERVER_IP
   ```
   Then start the client service:

   ```bash
   $ docker compose up -d
   ```
   (`docker compose` can be used in place of `docker-compose` here and throughout)

3. **Access the Web UI interfaces:**

   **Jupyter Lab**: http://localhost:8888 (no password required) - Interactive notebook environment

4. **Run the demo ETL + ML notebook:**
   - Navigate to `notebook/spark-connect-gpu-etl-ml.ipynb` in Jupyter Lab
   - You can also open it in VS Code by selecting http://localhost:8888 as the
     existing notebook server connection
   - Run the complete ETL and ML pipeline demonstration

5. **Run the demo python batch job:**
   - Create a Terminal in the Jupyter Lab
   - Navigate to `/home/spark/demo/python`
   - Execute `python batch-job.py`

6. **Run the demo scala batch job:**
   - Create a Terminal in the Jupyter Lab
   - Navigate to `/home/spark/demo/scala`
   - Execute `./run.sh`

7. **Run the demo NDS notebook:**
   - Navigate to `nds/nds.ipynb` in Jupyter Lab
   - Run the nds demonstration

## Advanced GPU Configurations

Most users won't need to adjust the GPU configurations. However, if you'd like
to tune your GPU for better performance, refer to the
[advanced GPU configurations documentation](https://nvidia.github.io/cudf-spark/docs/additional-functionality/advanced_configs.html).

**Note**: Configurations prefixed with spark.rapids.sql are session-specific
and can be set safely. However, those marked as **startup** will not take
effect in Spark Connect.

## 🐳 Service Details

### JupyterLab - Spark Connect Client
- **Image**: Based on `apache/spark:4.0.0`
- **Environment**: Pre-configured with PySpark Connect Client
- **Ports**: 8888 (Jupyter Lab)
- **Volumes**: Notebooks and work directory mounted

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
docker logs spark-connect-client
```

## 📖 Additional Resources

- [Apache Spark 4.0 Documentation](https://spark.apache.org/docs/latest/)
- [Spark Connect Guide](https://spark.apache.org/docs/latest/spark-connect-overview.html)
- [NVIDIA cuDF plugin for Apache Spark](https://nvidia.github.io/cudf-spark/)
- [Data and AI Summit Session](https://www.databricks.com/dataaisummit/session/gpu-accelerated-spark-connect)

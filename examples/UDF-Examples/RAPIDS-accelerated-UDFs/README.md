# RAPIDS Accelerated UDF Examples

This project contains sample implementations of RAPIDS accelerated user-defined functions.

The ideal solution would be to replace the UDF with a series of DataFrame or SQL operations. If that
is not possible, we also provide
a [UDF compiler extension](https://nvidia.github.io/spark-rapids/docs/additional-functionality/udf-to-catalyst-expressions.html)
to translate UDFs to Catalyst expressions. The extension is limited to only support compiling simple
operations. For complicated cases, you can choose to implement a RAPIDS accelerated UDF.

## Spark Scala UDF Examples

[URLDecode](src/main/scala/com/nvidia/spark/rapids/udf/scala/URLDecode.scala)
is the simplest demo for getting started. From the code you can see there is an original CPU
implementation provided by the `apply` method. We only need to implement the RapidsUDF interface
which provides a single method we need to override called
`evaluateColumnar`. The CPU URLDecode function processes the input row by row, but the GPU
evaluateColumnar returns a cudf ColumnVector, because the GPU get its speed by performing operations
on many rows at a time. In the `evaluateColumnar` function, there is a cudf implementation of URL
decode that we're leveraging, so we don't need to write any native C++ code. This is all done
through the [Java APIs of RAPIDS cudf](https://docs.rapids.ai/api/cudf-java/legacy). The benefit to
implement via the Java API is ease of development, but the memory model is not friendly for doing
GPU operations because the JVM makes the assumption that everything we're trying to do is in heap
memory. We need to free the GPU resources in a timely manner with try-finally blocks. Note that we
need to implement both CPU and GPU functions so the UDF will still work if a higher-level operation
involving the RAPIDS accelerated UDF falls back to the CPU.

- [URLDecode](src/main/scala/com/nvidia/spark/rapids/udf/scala/URLDecode.scala)
  decodes URL-encoded strings using the
  [Java APIs of RAPIDS cudf](https://docs.rapids.ai/api/cudf-java/legacy)
- [URLEncode](src/main/scala/com/nvidia/spark/rapids/udf/scala/URLEncode.scala)
  URL-encodes strings using the
  [Java APIs of RAPIDS cudf](https://docs.rapids.ai/api/cudf-java/legacy)

## Spark Java UDF Examples

Below are some examples for implementing RAPIDS accelerated Scala UDF via JNI and native code. If
there is no existing simple Java API we could leverage, we can write native custom code.
Take [CosineSimilarity](src/main/java/com/nvidia/spark/rapids/udf/java/CosineSimilarity.java) as the
example, the Java class for the UDF is similar as the previous URLDecode/URLEncode demo. We need to
implement a cosineSimilarity function in C++ code and goes into the native code as quickly as
possible, because it is easier to write the code safely. In the native code, it `reinterpret_cast`
the input to a column view, do some sanity checking and convert to list column views, then compute
the cosine similarity, finally return the unique pointer to a column, release the underlying
resources. On Java side we are going to wrap it in a column vector and own that resource.
In `cosine_similarity.cu` we implement the computation as the actual CUDA kernel. In the CUDA kernel
we can leverage the [Thrust template library](https://docs.nvidia.com/cuda/thrust/index.html) to
write the standard algorithms for GPU parallelizing code. The benefit of implementing the UDF in
native code is for maximum control over GPU memory utilization and performance. However the
trade-off is a more complicated build environment, as we need to build against libcudf with
significantly longer build times. Implementing a RAPIDS accelerated UDF in native code is a
significant effort.

- [URLDecode](src/main/java/com/nvidia/spark/rapids/udf/java/URLDecode.java)
  decodes URL-encoded strings using the
  [Java APIs of RAPIDS cudf](https://docs.rapids.ai/api/cudf-java/legacy)
- [URLEncode](src/main/java/com/nvidia/spark/rapids/udf/java/URLEncode.java)
  URL-encodes strings using the
  [Java APIs of RAPIDS cudf](https://docs.rapids.ai/api/cudf-java/legacy)
- [CosineSimilarity](src/main/java/com/nvidia/spark/rapids/udf/java/CosineSimilarity.java)
  computes the [cosine similarity](https://en.wikipedia.org/wiki/Cosine_similarity)
  between two float vectors using [native code](src/main/cpp/src)

## Hive UDF Examples

Below are some examples for implementing RAPIDS accelerated Hive UDF via JNI and native code.

- [URLDecode](src/main/java/com/nvidia/spark/rapids/udf/hive/URLDecode.java)
  implements a Hive simple UDF using the
  [Java APIs of RAPIDS cudf](https://docs.rapids.ai/api/cudf-java/legacy)
  to decode URL-encoded strings
- [URLEncode](src/main/java/com/nvidia/spark/rapids/udf/hive/URLEncode.java)
  implements a Hive generic UDF using the
  [Java APIs of RAPIDS cudf](https://docs.rapids.ai/api/cudf-java/legacy)
  to URL-encode strings
- [StringWordCount](src/main/java/com/nvidia/spark/rapids/udf/hive/StringWordCount.java)
  implements a Hive simple UDF using
  [native code](src/main/cpp/src) to count words in strings

## Building and run the tests without Native Code Examples

Some UDF examples use native code in their implementation. Building the native code requires a
libcudf build environment, so these examples do not build by default.

### Prerequisites

Download [Apache Spark](https://spark.apache.org/downloads.html) and set `SPARK_HOME` environment variable.
Install Python 3.8+, then install `pytest`, `sre_yield` by using pip or conda. For
example:

```
export SPARK_HOME=path-to-spark
pip install pytest              # If running in the docker container, please use pip3
pip install sre_yield           # If running in the docker container, please use pip3
```

Run the following command to build and run tests

```bash
cd spark-rapids-examples/examples/UDF-Examples/RAPIDS-accelerated-UDFs
mvn clean package
./run_pyspark_from_build.sh -m "not rapids_udf_example_native"
```

## Building with Native Code Examples and run test cases

The `udf-native-examples` Maven profile can be used to include the native UDF examples in the build,
i.e.: specify
`-Pudf-native-examples` on the `mvn` command-line.

### Creating a libcudf Build Environment

Building the native code requires a libcudf build environment.  
The `Dockerfile` in this directory can be used to setup a Docker image that provides a libcudf build
environment. This repository will either need to be cloned or mounted into a container using that
Docker image. The `Dockerfile` contains build arguments to control the Linux version, CUDA version,
and other settings. See the top of the `Dockerfile` for details.

First install docker and [nvidia-docker](https://github.com/NVIDIA/nvidia-docker)

Run the following commands to build and start a docker

```bash
cd spark-rapids-examples/examples/UDF-Examples/RAPIDS-accelerated-UDFs
docker build -t my-local:my-udf-example .
nvidia-docker run -it my-local:my-udf-example
```

### Build the udf-examples jar

#### Option 1: Fast Build Using Prebuilt libcudf (Recommended)

Instead of building cuDF from source (which takes a long time), you can use the prebuilt `libcudf.so` 
from the `rapids-4-spark` jar. This is much faster!

**Prerequisites:**
- rapids-4-spark jar must be available in your local Maven repository

**Steps:**

1. Extract libcudf.so and cuDF headers (automatic with Maven):
```bash
cd spark-rapids-examples/examples/UDF-Examples/RAPIDS-accelerated-UDFs
mvn clean package -Pudf-native-examples
```

The build will automatically:
- Extract `libcudf.so` from the rapids-4-spark jar
- Clone cuDF repository for headers (shallow clone)
- Build only your UDF native code against the prebuilt library

**Native ABI compatibility note:**

Native UDFs compile C++ code against cuDF, RMM, and CCCL headers, and the
resulting shared library is loaded with the `libcudf.so` packaged in the
rapids-4-spark jar. Those native dependencies do not guarantee ABI
compatibility across RAPIDS releases or across different `-SNAPSHOT` builds.
If the headers used at compile time do not match the `libcudf.so` in the jar,
the UDF may fail with undefined symbols or crash when Spark loads the native
library.

When changing the rapids-4-spark jar version, rebuild the native UDFs with
matching cuDF/RMM/CCCL headers and libraries. For snapshot or locally built
jars, make sure `cudf.git.branch`, the rapids-cmake branch in
`src/main/cpp/CMakeLists.txt`, and the RMM/CCCL versions resolved by
rapids-cmake correspond to the same source state used to build the jar. After
changing these values, remove `target/native-deps` and `target/cudf-repo`
before rebuilding so stale headers or libraries are not reused.

**Or manually extract first:**
```bash
./extract-cudf-libs.sh
mvn clean package -Pudf-native-examples
```

This approach typically reduces the native cuDF build time by almost **2 hours**!

#### Option 2: Build cuDF from Source (Slow but Complete)

If you need to build cuDF from source, you can disable the prebuilt library option.

**How it works:**
- The Maven property `USE_PREBUILT_CUDF` (default: `ON` in pom.xml) is passed to CMake
- Use `-DUSE_PREBUILT_CUDF=OFF` as a Maven system property to override the default
- Maven replaces `${USE_PREBUILT_CUDF}` in pom.xml and passes it to CMake as `-DUSE_PREBUILT_CUDF=OFF`

**Build with source:**

```bash
cd spark-rapids-examples/examples/UDF-Examples/RAPIDS-accelerated-UDFs
export LOCAL_CCACHE_DIR="$HOME/.ccache"
mkdir -p $LOCAL_CCACHE_DIR
export CCACHE_DIR="$LOCAL_CCACHE_DIR"
export CMAKE_C_COMPILER_LAUNCHER="ccache"
export CMAKE_CXX_COMPILER_LAUNCHER="ccache"
export CMAKE_CUDA_COMPILER_LAUNCHER="ccache"
export CMAKE_CXX_LINKER_LAUNCHER="ccache"
mvn clean package -Pudf-native-examples -DUSE_PREBUILT_CUDF=OFF
```

**Alternative: Edit CMakeLists.txt directly**

You can also edit `src/main/cpp/CMakeLists.txt` and set:
```cmake
option(USE_PREBUILT_CUDF "Use prebuilt libcudf.so from rapids-4-spark jar" OFF)
```

#### Configurable Maven Properties

You can customize the build by passing Maven system properties via `-D<property>=<value>`. These properties are defined in `pom.xml` and passed to CMake:

| Maven Property | Default Value | Description |
|----------------|---------------|-------------|
| `USE_PREBUILT_CUDF` | `ON` | Use prebuilt libcudf.so from rapids-4-spark jar (faster build) |
| `GPU_ARCHS` | `RAPIDS` | GPU architectures to compile for (e.g., `60;70;75;80`) |
| `CPP_PARALLEL_LEVEL` | `10` | Number of parallel compilation jobs |
| `BUILD_UDF_BENCHMARKS` | `OFF` | Build benchmark executables |
| `PER_THREAD_DEFAULT_STREAM` | `ON` | Enable per-thread default CUDA streams |
| `CUDF_ENABLE_ARROW_S3` | `OFF` | Enable Arrow S3 support in cuDF |
| `cudf.git.branch` | `main` | cuDF git branch to clone for headers |
| `skipCudfExtraction` | `false` | Skip extracting cuDF dependencies from jar |

**Example usage:**
```bash
# Build for specific GPU architectures with more parallel jobs
mvn clean package -Pudf-native-examples -DGPU_ARCHS="75;80;86" -DCPP_PARALLEL_LEVEL=16

# Skip cuDF extraction and use existing dependencies
mvn clean package -Pudf-native-examples -DskipCudfExtraction=true
```

#### Using ccache to Accelerate Builds

The Docker container has installed ccache 4.6 to accelerate the incremental building.
You can change the LOCAL_CCACHE_DIR to a mounted folder so that the cache can persist.
If you don't want to use ccache, you can remove or unset the ccache environment variables.

```bash
unset CCACHE_DIR
unset CMAKE_C_COMPILER_LAUNCHER
unset CMAKE_CXX_COMPILER_LAUNCHER
unset CMAKE_CUDA_COMPILER_LAUNCHER
unset CMAKE_CXX_LINKER_LAUNCHER
```

The first build could take a long time (e.g.: 1.5 hours). Then the rapids-4-spark-udf-examples*.jar is
generated under RAPIDS-accelerated-UDFs/target directory.
The following build can benefit from ccache if you enable it.

If you want to enable building with ccache on your own system,
please refer to the commands which build ccache from the source code in the Dockerfile.

### Run all the examples including native examples in the docker

See the above [Prerequisites section](#prerequisites)

```
export SPARK_HOME=path-to-spark
pip install pytest
pip install sre_yield
```

Run the following command to run tests

```
./run_pyspark_from_build.sh
```

## How to run the Native UDFs on Spark local mode

First finish the steps in 
[Building with Native Code Examples and run test cases](#building-with-native-code-examples-and-run-test-cases) section, 
then do the following inside the Docker container.

### Get jars from Maven Central

[rapids-4-spark_2.12-26.06.0.jar](https://repo1.maven.org/maven2/com/nvidia/rapids-4-spark_2.12/26.06.0/rapids-4-spark_2.12-26.06.0.jar)


### Launch a local mode Spark

```bash
export SPARK_RAPIDS_PLUGIN_JAR=path-to-rapids-4-spark-jar
export SPARK_RAPIDS_UDF_EXAMPLES_JAR=path-to-udf-examples-jar

$SPARK_HOME/bin/pyspark --master local[*] \
--conf spark.executor.cores=6 \
--driver-memory 5G  \
--executor-memory 5G  \
--jars ${SPARK_RAPIDS_PLUGIN_JAR},${SPARK_RAPIDS_UDF_EXAMPLES_JAR} \
--conf spark.plugins=com.nvidia.spark.SQLPlugin \
--conf spark.rapids.sql.enabled=true
```

### Test native based UDF

Input the following commands to test wordcount JNI UDF

```python
from pyspark.sql.types import *
schema = StructType([
    StructField("c1", StringType()),
    StructField("c2", IntegerType()),
])
data = [
    ("a b c d",1),
    ("",2),
    (None,3),
    ("the quick brown fox jumped over the lazy dog",3),
]
df = spark.createDataFrame(
        SparkContext.getOrCreate().parallelize(data, numSlices=2),
        schema)
df.createOrReplaceTempView("tab")

spark.sql("CREATE TEMPORARY FUNCTION {} AS '{}'".format("wordcount", "com.nvidia.spark.rapids.udf.hive.StringWordCount"))
spark.sql("select c1, wordcount(c1) from tab").show()
spark.sql("select c1, wordcount(c1) from tab").explain()
```

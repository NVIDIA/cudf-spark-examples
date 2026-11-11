# Columnar DataSource V2 Example

This example is a small [DataSource V2](https://spark.apache.org/docs/latest/api/java/org/apache/spark/sql/connector/read/package-summary.html)
source, `textlines`, that reads text files line by line on the CPU and returns columnar batches
backed by [Apache Arrow](https://arrow.apache.org/) vectors. With the
[NVIDIA cuDF plugin for Apache Spark](https://nvidia.github.io/cudf-spark/), the batches go to
the GPU through `HostColumnarToGpu`, and the rest of the query runs on the GPU.

Spark already reads text files, so the format is only a stand-in. The same pattern applies to a
format that Spark cannot read: decode it on the CPU into Arrow vectors, and let the plugin move
the batches to the GPU.

## What the example shows

- The DataSource V2 read path: `TableProvider`, `Table` with `SupportsRead`, `ScanBuilder` with
  column pruning, `Scan`/`Batch`, one `InputPartition` per Hadoop split, and a
  `PartitionReaderFactory` whose `supportColumnarReads` returns `true`.
- A `PartitionReader<ColumnarBatch>` that fills Arrow vectors of three types: `BIGINT`, `STRING`
  and `BINARY`.
- How the batches reach the GPU, and what to look for in the plan.

The source returns these columns:

| Column | Type | Description |
|--------|------|-------------|
| `offset` | `BIGINT` | Byte offset of the line in its file |
| `line` | `STRING` | The line, without the line terminator |
| `bytes` | `BINARY` | The same bytes as `line`, only with the option `includeBytes=true` |

Options:

| Option | Default | Description |
|--------|---------|-------------|
| `includeBytes` | `false` | Add the `bytes` column |
| `maxPartitionBytes` | `spark.sql.files.maxPartitionBytes` | Largest split of a file |
| `maxBatchBytes` | `2m` | Largest number of line bytes in one batch |
| `maxBatchRows` | `262144` | Largest number of lines in one batch |

## Build

Requires Java 8 or later and Maven. The unit tests run Spark locally on the CPU.

```shell
mvn package
```

This produces `target/columnar-datasource-v2-example_2.12-26.12.0-SNAPSHOT.jar`. The source only
uses Spark APIs, so the jar does not depend on the cuDF plugin.

## Run

On the CPU:

```shell
$SPARK_HOME/bin/spark-submit \
  --jars target/columnar-datasource-v2-example_2.12-26.12.0-SNAPSHOT.jar \
  demo.py /tmp/textlines-demo
```

With the cuDF plugin, add the plugin jar and enable it, see the
[getting started guides](https://docs.nvidia.com/spark-rapids/user-guide/latest/getting-started/overview.html):

```shell
$SPARK_HOME/bin/spark-submit \
  --jars rapids-4-spark_2.12-<version>-cuda12.jar,target/columnar-datasource-v2-example_2.12-26.12.0-SNAPSHOT.jar \
  --conf spark.plugins=com.nvidia.spark.SQLPlugin \
  demo.py /tmp/textlines-demo
```

[demo.py](demo.py) writes a small sample to the path if it does not exist, groups the lines by
length, and prints the result and the final physical plan. In Scala or Python, the source is
used like any other:

```python
df = spark.read.format("textlines").option("includeBytes", "true").load(path)
```

With the plugin, the scan is followed by `HostColumnarToGpu`, and the operators above it run on
the GPU:

```
GpuHashAggregate (keys=[_groupingexpression#20], functions=[partial_gpucount(1, false), ...])
+- GpuProject [offset#0L, line#1, bytes#2, length(line#1) AS _groupingexpression#20], true
   +- HostColumnarToGpu targetsize(1073741824)
      +- BatchScan textlines[offset#0L, line#1, bytes#2] TextLinesScan(/tmp/textlines-demo)
```

For comparison, `spark.read.text` returns rows, so its scan is followed by
`GpuRowToColumnarExec`, which converts the data row by row.

## How the batches reach the GPU

`HostColumnarToGpu` combines the host batches of a task into GPU batches of about
`spark.rapids.sql.batchSizeBytes` and copies them to the GPU. So the batches of the source can be
small; a few MiB each is enough.

Starting with version 26.12, the plugin copies Arrow vectors of fixed-width, string and binary
types into its host columns in bulk, one buffer at a time. Earlier versions read the same
batches, but a schema with a binary column is copied value by value. The source works with both;
only the speed of the copy differs.

## Writing your own source

Points that this example handles, and that matter for any columnar source:

- **Return Arrow vectors for every column.** `ArrowColumnVector` is what the plugin copies in
  bulk. Other `ColumnVector` implementations are copied value by value.
- **Give each batch new vectors.** [TextLinesColumnarReader](src/main/java/com/nvidia/spark/examples/textlines/TextLinesColumnarReader.java)
  closes the previous batch when Spark asks for the next one, and does not refill vectors that
  a consumer may still read. Arrow buffers are reference counted, so a consumer that needs them
  longer keeps its own reference.
- **Keep Arrow buffers small.** With Spark 3.5, Arrow allocates buffers larger than 4 MiB outside
  its pool, and every such allocation is zero-filled. The default batch limits keep each buffer
  at or below 2 MiB. A source that needs larger buffers can use an Arrow
  `AllocationManager` that allocates with `malloc` instead.
- **Prune columns.** `SupportsPushDownRequiredColumns` lets the reader fill only the columns that
  the query reads. A query that reads no columns, such as `count()`, still gets batches with the
  row count.
- **Plan the input once.** Spark may call `planInputPartitions` and `createReaderFactory` several
  times while planning; [TextLinesScan](src/main/java/com/nvidia/spark/examples/textlines/TextLinesScan.java)
  computes them once.

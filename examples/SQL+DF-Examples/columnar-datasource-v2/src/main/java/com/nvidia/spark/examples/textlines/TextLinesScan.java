/*
 * Copyright (c) 2026, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.nvidia.spark.examples.textlines;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.mapreduce.InputSplit;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.input.FileSplit;
import org.apache.hadoop.mapreduce.lib.input.TextInputFormat;
import org.apache.spark.api.java.JavaSparkContext;
import org.apache.spark.broadcast.Broadcast;
import org.apache.spark.network.util.JavaUtils;
import org.apache.spark.sql.SparkSession;
import org.apache.spark.sql.connector.read.Batch;
import org.apache.spark.sql.connector.read.InputPartition;
import org.apache.spark.sql.connector.read.PartitionReaderFactory;
import org.apache.spark.sql.connector.read.Scan;
import org.apache.spark.sql.types.StructType;
import org.apache.spark.sql.util.CaseInsensitiveStringMap;

/** Plans one input partition per Hadoop text split. */
final class TextLinesScan implements Scan, Batch {
  private final CaseInsensitiveStringMap options;
  private final StructType required;
  private InputPartition[] partitions;
  private PartitionReaderFactory readerFactory;

  TextLinesScan(CaseInsensitiveStringMap options, StructType required) {
    this.options = options;
    this.required = required;
  }

  @Override
  public StructType readSchema() {
    return required;
  }

  @Override
  public String description() {
    return "TextLinesScan(" + String.join(",", paths()) + ")";
  }

  @Override
  public Batch toBatch() {
    return this;
  }

  private String[] paths() {
    String single = options.get("path");
    if (single != null) {
      return new String[] {single};
    }
    // DataFrameReader.load(paths: _*) passes several paths as a JSON array.
    String json = options.get("paths");
    if (json == null) {
      throw new IllegalArgumentException("textlines requires a path");
    }
    try {
      return new ObjectMapper().readValue(json, String[].class);
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    }
  }

  // Spark may call these several times while planning; list and split the input only once.
  @Override
  public synchronized InputPartition[] planInputPartitions() {
    if (partitions == null) {
      partitions = computePartitions();
    }
    return partitions;
  }

  @Override
  public synchronized PartitionReaderFactory createReaderFactory() {
    if (readerFactory == null) {
      SparkSession spark = SparkSession.active();
      Broadcast<SerializableConf> conf = JavaSparkContext.fromSparkContext(spark.sparkContext())
          .broadcast(new SerializableConf(spark.sparkContext().hadoopConfiguration()));
      // The defaults keep each Arrow buffer at or below 2 MiB, see the README.
      readerFactory = new TextLinesReaderFactory(conf, required,
          options.getInt("maxBatchRows", 1 << 18),
          JavaUtils.byteStringAsBytes(options.getOrDefault("maxBatchBytes", "2m")));
    }
    return readerFactory;
  }

  private InputPartition[] computePartitions() {
    SparkSession spark = SparkSession.active();
    Configuration conf = new Configuration(spark.sparkContext().hadoopConfiguration());
    long maxSplitBytes = JavaUtils.byteStringAsBytes(options.getOrDefault("maxPartitionBytes",
        spark.conf().get("spark.sql.files.maxPartitionBytes")));
    List<InputSplit> splits;
    try {
      Job job = Job.getInstance(conf);
      for (String path : paths()) {
        FileInputFormat.addInputPath(job, new Path(path));
      }
      FileInputFormat.setMaxInputSplitSize(job, maxSplitBytes);
      // TextInputFormat keeps compressed files that cannot be split in one piece.
      splits = new TextInputFormat().getSplits(job);
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    }
    InputPartition[] result = new InputPartition[splits.size()];
    for (int i = 0; i < result.length; i++) {
      result[i] = TextSplitPartition.of((FileSplit) splits.get(i));
    }
    return result;
  }
}

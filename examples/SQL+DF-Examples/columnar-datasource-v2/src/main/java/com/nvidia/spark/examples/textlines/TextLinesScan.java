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
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

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

/** Splits the files like Hadoop's TextInputFormat and packs the splits into partitions. */
final class TextLinesScan implements Scan, Batch {
  private final CaseInsensitiveStringMap options;
  private final StructType required;
  private Configuration hadoopConf;
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

  // Like Spark's file sources: the session's Hadoop settings, such as those set with
  // spark.conf.set, and the options of this read, such as fs.s3a.endpoint.
  private Configuration hadoopConf() {
    if (hadoopConf == null) {
      hadoopConf = SparkSession.active().sessionState().newHadoopConf();
      for (Map.Entry<String, String> e : options.asCaseSensitiveMap().entrySet()) {
        if (!e.getKey().equalsIgnoreCase("path") && !e.getKey().equalsIgnoreCase("paths")) {
          hadoopConf.set(e.getKey(), e.getValue());
        }
      }
    }
    return hadoopConf;
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
          .broadcast(new SerializableConf(hadoopConf()));
      // The defaults keep each Arrow buffer at or below 2 MiB, see the README.
      readerFactory = new TextLinesReaderFactory(conf, required,
          options.getInt("maxBatchRows", 1 << 18),
          JavaUtils.byteStringAsBytes(options.getOrDefault("maxBatchBytes", "2m")));
    }
    return readerFactory;
  }

  private InputPartition[] computePartitions() {
    SparkSession spark = SparkSession.active();
    long maxPartitionBytes = JavaUtils.byteStringAsBytes(options.getOrDefault(
        "maxPartitionBytes", spark.conf().get("spark.sql.files.maxPartitionBytes")));
    long openCost = JavaUtils.byteStringAsBytes(
        spark.conf().get("spark.sql.files.openCostInBytes"));
    List<InputSplit> splits;
    try {
      Job job = Job.getInstance(new Configuration(hadoopConf()));
      for (String path : paths()) {
        FileInputFormat.addInputPath(job, new Path(path));
      }
      FileInputFormat.setMaxInputSplitSize(job, maxPartitionBytes);
      // TextInputFormat keeps compressed files that cannot be split in one piece.
      splits = new TextInputFormat().getSplits(job);
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    }
    // Like Spark's file sources, pack small splits into one partition, counting each split as
    // at least openCostInBytes, so that a task builds GPU batches of a useful size.
    List<InputPartition> result = new ArrayList<>();
    List<FileSplit> current = new ArrayList<>();
    long currentBytes = 0;
    for (InputSplit split : splits) {
      FileSplit fileSplit = (FileSplit) split;
      if (!current.isEmpty() && currentBytes + fileSplit.getLength() > maxPartitionBytes) {
        result.add(TextSplitPartition.of(current));
        current = new ArrayList<>();
        currentBytes = 0;
      }
      current.add(fileSplit);
      currentBytes += fileSplit.getLength() + openCost;
    }
    if (!current.isEmpty()) {
      result.add(TextSplitPartition.of(current));
    }
    return result.toArray(new InputPartition[0]);
  }
}

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

import org.apache.arrow.memory.BufferAllocator;
import org.apache.arrow.memory.RootAllocator;
import org.apache.arrow.vector.BigIntVector;
import org.apache.arrow.vector.FieldVector;
import org.apache.arrow.vector.VarBinaryVector;
import org.apache.arrow.vector.VarCharVector;
import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.TaskAttemptID;
import org.apache.hadoop.mapreduce.lib.input.FileSplit;
import org.apache.hadoop.mapreduce.lib.input.LineRecordReader;
import org.apache.hadoop.mapreduce.task.TaskAttemptContextImpl;
import org.apache.spark.sql.connector.read.PartitionReader;
import org.apache.spark.sql.types.StructField;
import org.apache.spark.sql.types.StructType;
import org.apache.spark.sql.vectorized.ArrowColumnVector;
import org.apache.spark.sql.vectorized.ColumnVector;
import org.apache.spark.sql.vectorized.ColumnarBatch;

/**
 * Reads the lines of one split into Arrow-backed columnar batches.
 *
 * Each batch gets new vectors, and the previous batch is closed when Spark asks for the next one,
 * so a consumer never sees its buffers change. The batch limits keep every Arrow buffer at or
 * below {@code maxBatchBytes} (2 MiB by default) for typical lines.
 */
final class TextLinesColumnarReader implements PartitionReader<ColumnarBatch> {
  private final BufferAllocator allocator = new RootAllocator();
  private final LineRecordReader lines = new LineRecordReader();
  private final String[] columns;
  private final int maxBatchRows;
  private final long maxBatchBytes;
  // A line read past the end of the previous batch
  private boolean pending;
  private ColumnarBatch batch;

  TextLinesColumnarReader(Configuration conf, TextSplitPartition partition, StructType required,
      int maxBatchRows, long maxBatchBytes) {
    this.columns = required.fieldNames();
    this.maxBatchRows = maxBatchRows;
    this.maxBatchBytes = maxBatchBytes;
    FileSplit split = new FileSplit(new Path(partition.path), partition.start, partition.length,
        new String[0]);
    try {
      lines.initialize(split, new TaskAttemptContextImpl(conf, new TaskAttemptID()));
    } catch (IOException e) {
      close();
      throw new UncheckedIOException(e);
    }
  }

  @Override
  public boolean next() throws IOException {
    closeBatch();
    if (!pending && !lines.nextKeyValue()) {
      return false;
    }
    pending = false;
    List<FieldVector> vectors = new ArrayList<>();
    try {
      for (String name : columns) {
        vectors.add(newVector(name));
      }
      int rows = 0;
      long bytes = 0;
      do {
        Text line = lines.getCurrentValue();
        if (rows > 0 && (rows == maxBatchRows || bytes + line.getLength() > maxBatchBytes)) {
          pending = true;
          break;
        }
        append(vectors, rows, lines.getCurrentKey(), line);
        rows++;
        bytes += line.getLength();
      } while (lines.nextKeyValue());
      ColumnVector[] result = new ColumnVector[vectors.size()];
      for (int i = 0; i < result.length; i++) {
        vectors.get(i).setValueCount(rows);
        result[i] = new ArrowColumnVector(vectors.get(i));
      }
      // A query that reads no columns, such as count(*), still gets the row count.
      batch = new ColumnarBatch(result, rows);
      return true;
    } catch (Throwable t) {
      vectors.forEach(FieldVector::close);
      throw t;
    }
  }

  private FieldVector newVector(String name) {
    switch (name) {
      case TextLinesSource.OFFSET: {
        BigIntVector v = new BigIntVector(name, allocator);
        v.allocateNew(Math.min(maxBatchRows, 1 << 12));
        return v;
      }
      case TextLinesSource.LINE: {
        VarCharVector v = new VarCharVector(name, allocator);
        v.allocateNew(maxBatchBytes, Math.min(maxBatchRows, 1 << 12));
        return v;
      }
      case TextLinesSource.BYTES: {
        VarBinaryVector v = new VarBinaryVector(name, allocator);
        v.allocateNew(maxBatchBytes, Math.min(maxBatchRows, 1 << 12));
        return v;
      }
      default:
        throw new IllegalArgumentException("Unknown column " + name);
    }
  }

  // setSafe grows a vector when it is full.
  private static void append(List<FieldVector> vectors, int row, LongWritable offset, Text line) {
    for (FieldVector v : vectors) {
      if (v instanceof BigIntVector) {
        ((BigIntVector) v).setSafe(row, offset.get());
      } else if (v instanceof VarCharVector) {
        ((VarCharVector) v).setSafe(row, line.getBytes(), 0, line.getLength());
      } else {
        ((VarBinaryVector) v).setSafe(row, line.getBytes(), 0, line.getLength());
      }
    }
  }

  @Override
  public ColumnarBatch get() {
    return batch;
  }

  private void closeBatch() {
    if (batch != null) {
      batch.close();
      batch = null;
    }
  }

  @Override
  public void close() {
    try {
      closeBatch();
      lines.close();
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    } finally {
      allocator.close();
    }
  }
}

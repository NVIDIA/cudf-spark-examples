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

import org.apache.spark.broadcast.Broadcast;
import org.apache.spark.sql.catalyst.InternalRow;
import org.apache.spark.sql.connector.read.InputPartition;
import org.apache.spark.sql.connector.read.PartitionReader;
import org.apache.spark.sql.connector.read.PartitionReaderFactory;
import org.apache.spark.sql.types.StructType;
import org.apache.spark.sql.vectorized.ColumnarBatch;

final class TextLinesReaderFactory implements PartitionReaderFactory {
  private final Broadcast<SerializableConf> conf;
  private final StructType required;
  private final int maxBatchRows;
  private final long maxBatchBytes;

  TextLinesReaderFactory(Broadcast<SerializableConf> conf, StructType required,
      int maxBatchRows, long maxBatchBytes) {
    this.conf = conf;
    this.required = required;
    this.maxBatchRows = maxBatchRows;
    this.maxBatchBytes = maxBatchBytes;
  }

  // Columnar output lets the cuDF plugin copy whole Arrow buffers to the GPU
  // (HostColumnarToGpu) instead of converting row by row (GpuRowToColumnarExec).
  @Override
  public boolean supportColumnarReads(InputPartition partition) {
    return true;
  }

  @Override
  public PartitionReader<ColumnarBatch> createColumnarReader(InputPartition partition) {
    return new TextLinesColumnarReader(conf.value().get(), (TextSplitPartition) partition,
        required, maxBatchRows, maxBatchBytes);
  }

  // Spark only asks for rows when supportColumnarReads returns false.
  @Override
  public PartitionReader<InternalRow> createReader(InputPartition partition) {
    throw new UnsupportedOperationException("textlines only supports columnar reads");
  }
}

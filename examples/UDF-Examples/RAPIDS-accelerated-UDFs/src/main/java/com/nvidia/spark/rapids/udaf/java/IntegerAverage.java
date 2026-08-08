/*
 * Copyright (c) 2025, NVIDIA CORPORATION.
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

package com.nvidia.spark.rapids.udaf.java;

import ai.rapids.cudf.ColumnVector;
import ai.rapids.cudf.ColumnView;
import ai.rapids.cudf.DType;
import ai.rapids.cudf.GroupByAggregation;
import ai.rapids.cudf.GroupByAggregationOnColumn;
import ai.rapids.cudf.HostUDFWrapper;
import ai.rapids.cudf.ReductionAggregation;
import ai.rapids.cudf.Scalar;
import com.nvidia.spark.RapidsSimpleGroupByAggregation;
import com.nvidia.spark.RapidsUDAF;
import com.nvidia.spark.RapidsUDAFGroupByAggregation;
import com.nvidia.spark.rapids.udf.java.NativeUDFExamplesLoader;
import org.apache.spark.sql.Row;
import org.apache.spark.sql.expressions.MutableAggregationBuffer;
import org.apache.spark.sql.expressions.UserDefinedAggregateFunction;
import org.apache.spark.sql.types.DataType;
import org.apache.spark.sql.types.IntegerType$;
import org.apache.spark.sql.types.StructType;

import java.util.Arrays;
import java.util.Objects;

/**
 * A user-defined aggregate function (UDAF) that computes the average value
 * of integers.
 * This class demonstrates how to implement a UDAF that also provides a
 * RAPIDS implementation that can run on the GPU when the query is executed
 * with the RAPIDS Accelerator for Apache Spark.
 */
@SuppressWarnings("deprecation")
public class IntegerAverage extends UserDefinedAggregateFunction implements RapidsUDAF {
  /** Row-by-row implementation that executes on the CPU */
  @Override
  public StructType inputSchema() {
    // Integer values as the input
    return StructType.fromDDL("input INTEGER");
  }

  @Override
  public StructType bufferSchema() {
    // two long buffers, sum and count
    return StructType.fromDDL("sum BIGINT, count BIGINT");
  }

  @Override
  public DataType dataType() {
    // integer as the result type
    return IntegerType$.MODULE$;
  }

  @Override
  public boolean deterministic() {
    return true;
  }

  @Override
  public void initialize(MutableAggregationBuffer buffer) {
    buffer.update(0, null); // sum
    buffer.update(1, 0L); // count
  }

  @Override
  public void update(MutableAggregationBuffer buffer, Row input) {
    if (!input.isNullAt(0)) {
      long accSum = input.getInt(0);
      if(!buffer.isNullAt(0)) {
        accSum += buffer.getLong(0);
      }
      buffer.update(0, accSum); // sum field in buffer
      buffer.update(1, buffer.getLong(1) + 1L); // count field in buffer
    } // ignore nulls
  }

  @Override
  public void merge(MutableAggregationBuffer buffer1, Row buffer2) {
    if (!buffer2.isNullAt(0)) {
      long accMergedSum = buffer2.getLong(0);
      if (!buffer1.isNullAt(0)) {
        accMergedSum += buffer1.getLong(0);
      }
      buffer1.update(0, accMergedSum); // sum
    } // else{} // NOOP, "buffer2[0]" is null so "buffer1" holds the correct value already
    buffer1.update(1, buffer1.getLong(1) + buffer2.getLong(1)); // count
  }

  @Override
  public Object evaluate(Row buffer) {
    long count = buffer.getLong(1);
    if (count == 0) {
      return null;
    } else {
      return (int)(buffer.getLong(0) / count);
    }
  }

  /** Columnar implementation that runs on the GPU */
  @Override
  public Scalar[] getDefaultValue() {
    // The output should follow the buffer schema defined by "aggBufferTypes".
    // aka, a single struct type.
    try (
        Scalar nullLong = Scalar.fromNull(DType.INT32);
        ColumnVector nullSum = ColumnVector.fromScalar(nullLong, 1);
        ColumnVector count = ColumnVector.fromInts( 0)) {
      return new Scalar[]{ Scalar.structFromColumnViews(nullSum, count) };
    }
  }

  // preProcess, the default implementation is good enough.

  @Override
  public RapidsUDAFGroupByAggregation updateAggregation() {
    return new RapidsSimpleGroupByAggregation() {
      @Override
      public GroupByAggregationOnColumn[] aggregate(int[] ids) {
        assert ids.length == 1; // the integer input column
        HostUDFWrapper avgUDAF = new RapidsAverageUDAF(AggregationType.GroupBy);
        return new GroupByAggregationOnColumn[] {
            GroupByAggregation.hostUDF(avgUDAF).onColumn(ids[0])
        };
      }

      @Override
      public Scalar[] reduce(int numRows, ColumnVector[] args) {
        assert args.length == 1;
        HostUDFWrapper avgUDAF = new RapidsAverageUDAF(AggregationType.Reduction);
        return new Scalar[] { args[0].reduce(ReductionAggregation.hostUDF(avgUDAF)) };
      }
    };
  }

  @Override
  public RapidsUDAFGroupByAggregation mergeAggregation() {
    return new RapidsSimpleGroupByAggregation() {
      @Override
      public GroupByAggregationOnColumn[] aggregate(int[] ids) {
        // Column of struct type with two children: sum and count, after "update" stage.
        assert ids.length == 1;
        HostUDFWrapper avgUDAF = new RapidsAverageUDAF(AggregationType.GroupByMerge);
        return new GroupByAggregationOnColumn[] {
            GroupByAggregation.hostUDF(avgUDAF).onColumn(ids[0])
        };
      }

      @Override
      public Scalar[] reduce(int numRows, ColumnVector[] args) {
        // Column of struct type with two children: sum and count, after "update" stage.
        assert args.length == 1;
        HostUDFWrapper avgUDAF = new RapidsAverageUDAF(AggregationType.ReductionMerge);
        return new Scalar[] { args[0].reduce(ReductionAggregation.hostUDF(avgUDAF)) };
      }
    };
  }

  @Override
  public ColumnVector postProcess(int numRows, ColumnVector[] buffers, DataType retType) {
    try {
      // Column of struct type with two children: sum and count, after "merge" stage.
      assert buffers.length == 1;
      return RapidsAverageUDAF.computeAvg(buffers[0]);
    } finally {
      // Make sure buffers always be closed to avoid memory leak.
      Arrays.stream(buffers).forEach(ColumnVector::close);
    }
  }

  @Override
  public DataType[] aggBufferTypes() {
    return new DataType[] { bufferSchema() };
  }
}

// The customized cuDF aggregation to perform the average computation on integer values.
class RapidsAverageUDAF extends HostUDFWrapper {
  public RapidsAverageUDAF(AggregationType type) {
    this.aggType = type;
  }

  @Override
  public long createUDFInstance() {
    if (nativeInstance == 0L) {
      NativeUDFExamplesLoader.ensureLoaded();
      nativeInstance = createAverageHostUDF(aggType.nativeId);
    }
    return nativeInstance;
  }

  @Override
  public int computeHashCode() {
    return Objects.hash(this.getClass().getName(), aggType, createUDFInstance());
  }

  @Override
  public boolean isEqual(Object o) {
    if (this == o) return true;
    if (o == null || getClass() != o.getClass()) {
      return false;
    }
    RapidsAverageUDAF other = (RapidsAverageUDAF) o;
    return aggType == other.aggType;
  }

  // input struct(sum, count), output avg column
  public static ColumnVector computeAvg(ColumnView input) {
    NativeUDFExamplesLoader.ensureLoaded();
    return new ColumnVector(computeAvg(input.getNativeView()));
  }

  private static native long createAverageHostUDF(int type);
  private static native long computeAvg(long inputHandle);

  private final AggregationType aggType;
  private long nativeInstance;
}

enum AggregationType {
  // input: int column, output: sum, count
  Reduction(0),
  // input: sum, count, output: sum, count
  ReductionMerge(1),
  // input: int column, output: struct(sum: int, count: int)
  GroupBy(2),
  // input: struct(sum: int, count: int), output: struct(sum: int, count: int)
  GroupByMerge(3);

  final int nativeId;

  AggregationType(int nativeId) {
    this.nativeId = nativeId;
  }
}
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

import java.util.Map;

import org.apache.spark.sql.connector.catalog.Table;
import org.apache.spark.sql.connector.catalog.TableProvider;
import org.apache.spark.sql.connector.expressions.Transform;
import org.apache.spark.sql.sources.DataSourceRegister;
import org.apache.spark.sql.types.DataTypes;
import org.apache.spark.sql.types.StructType;
import org.apache.spark.sql.util.CaseInsensitiveStringMap;

/**
 * A DataSource V2 source that reads text files line by line and returns columnar batches
 * backed by Arrow vectors.
 *
 * <pre>
 *   spark.read.format("textlines").load(path)
 * </pre>
 *
 * Columns:
 * <ul>
 *   <li>{@code offset} (BIGINT): byte offset of the line in its file</li>
 *   <li>{@code line} (STRING): the line, without the line terminator</li>
 *   <li>{@code bytes} (BINARY): the same bytes as {@code line}, only with the option
 *       {@code includeBytes=true}</li>
 * </ul>
 */
public class TextLinesSource implements TableProvider, DataSourceRegister {
  static final String OFFSET = "offset";
  static final String LINE = "line";
  static final String BYTES = "bytes";

  static StructType schema(CaseInsensitiveStringMap options) {
    StructType schema = new StructType()
        .add(OFFSET, DataTypes.LongType, false)
        .add(LINE, DataTypes.StringType, false);
    if (options.getBoolean("includeBytes", false)) {
      schema = schema.add(BYTES, DataTypes.BinaryType, false);
    }
    return schema;
  }

  @Override
  public String shortName() {
    return "textlines";
  }

  @Override
  public StructType inferSchema(CaseInsensitiveStringMap options) {
    return schema(options);
  }

  @Override
  public Table getTable(StructType schema, Transform[] partitioning,
      Map<String, String> properties) {
    return new TextLinesTable(schema, new CaseInsensitiveStringMap(properties));
  }
}

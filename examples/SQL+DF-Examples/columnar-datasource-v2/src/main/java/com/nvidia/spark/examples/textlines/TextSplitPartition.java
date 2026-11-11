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

import org.apache.hadoop.mapreduce.lib.input.FileSplit;
import org.apache.spark.sql.connector.read.InputPartition;

/** A byte range of one file; the reader starts at the first line that begins in it. */
final class TextSplitPartition implements InputPartition {
  final String path;
  final long start;
  final long length;
  private final String[] hosts;

  private TextSplitPartition(String path, long start, long length, String[] hosts) {
    this.path = path;
    this.start = start;
    this.length = length;
    this.hosts = hosts;
  }

  static TextSplitPartition of(FileSplit split) {
    List<String> hosts = new ArrayList<>();
    try {
      for (String host : split.getLocations()) {
        if (!"localhost".equals(host)) {
          hosts.add(host);
        }
      }
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    }
    return new TextSplitPartition(split.getPath().toString(), split.getStart(),
        split.getLength(), hosts.toArray(new String[0]));
  }

  @Override
  public String[] preferredLocations() {
    return hosts;
  }
}

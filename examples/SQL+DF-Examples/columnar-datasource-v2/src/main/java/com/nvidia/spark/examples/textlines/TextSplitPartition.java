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
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

import org.apache.hadoop.mapreduce.lib.input.FileSplit;
import org.apache.spark.sql.connector.read.InputPartition;

/**
 * Byte ranges of one or more files. The reader starts each range at the first line that begins
 * in it.
 */
final class TextSplitPartition implements InputPartition {
  final String[] paths;
  final long[] starts;
  final long[] lengths;
  private final String[] hosts;

  private TextSplitPartition(String[] paths, long[] starts, long[] lengths, String[] hosts) {
    this.paths = paths;
    this.starts = starts;
    this.lengths = lengths;
    this.hosts = hosts;
  }

  static TextSplitPartition of(List<FileSplit> splits) {
    int n = splits.size();
    String[] paths = new String[n];
    long[] starts = new long[n];
    long[] lengths = new long[n];
    Set<String> hosts = new LinkedHashSet<>();
    for (int i = 0; i < n; i++) {
      FileSplit split = splits.get(i);
      paths[i] = split.getPath().toString();
      starts[i] = split.getStart();
      lengths[i] = split.getLength();
      try {
        for (String host : split.getLocations()) {
          if (!"localhost".equals(host)) {
            hosts.add(host);
          }
        }
      } catch (IOException e) {
        throw new UncheckedIOException(e);
      }
    }
    return new TextSplitPartition(paths, starts, lengths, hosts.toArray(new String[0]));
  }

  @Override
  public String[] preferredLocations() {
    return hosts;
  }
}

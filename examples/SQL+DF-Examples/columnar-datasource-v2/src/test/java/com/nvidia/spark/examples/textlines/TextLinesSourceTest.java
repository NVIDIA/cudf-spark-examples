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

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

import org.apache.spark.sql.Dataset;
import org.apache.spark.sql.Row;
import org.apache.spark.sql.SparkSession;
import org.junit.AfterClass;
import org.junit.BeforeClass;
import org.junit.Test;

public class TextLinesSourceTest {
  private static SparkSession spark;
  private static File dir;
  private static List<File> files = new ArrayList<>();

  @BeforeClass
  public static void setUp() throws IOException {
    spark = SparkSession.builder().master("local[2]").appName("TextLinesSourceTest")
        .config("spark.ui.enabled", "false").getOrCreate();
    dir = Files.createTempDirectory("textlines").toFile();
    // Empty lines, multi-byte characters, a long line and both line terminators
    StringBuilder text = new StringBuilder();
    for (int i = 0; i < 20000; i++) {
      if (i % 97 == 0) {
        text.append("\n");
      } else if (i % 1001 == 0) {
        text.append(String.join("", Collections.nCopies(5000, "x"))).append("\r\n");
      } else {
        text.append("line ").append(i).append(" é中\n");
      }
    }
    for (int f = 0; f < 3; f++) {
      File file = new File(dir, "part-" + f + ".txt");
      Files.write(file.toPath(), (text + "last line without terminator " + f)
          .getBytes(StandardCharsets.UTF_8));
      files.add(file);
    }
  }

  @AfterClass
  public static void tearDown() {
    spark.stop();
    for (File f : files) {
      f.delete();
    }
    dir.delete();
  }

  // Small splits and batches, so lines cross split and batch boundaries.
  private Dataset<Row> read(String path, boolean includeBytes) {
    return spark.read().format("textlines")
        .option("maxPartitionBytes", "64k")
        .option("maxBatchBytes", "16k")
        .option("maxBatchRows", "1000")
        .option("includeBytes", String.valueOf(includeBytes))
        .load(path);
  }

  @Test
  public void readsTheSameLinesAsSparkText() {
    Dataset<Row> lines = read(dir.getPath(), false);
    assertTrue(lines.rdd().getNumPartitions() > files.size());
    Dataset<Row> expected = spark.read().text(dir.getPath());
    // count() reads no columns
    assertEquals(expected.count(), lines.count());
    assertEquals(0, expected.exceptAll(lines.select("line")).count());
    assertEquals(0, lines.select("line").exceptAll(expected).count());
  }

  @Test
  public void offsetsAndBytesMatchTheFile() throws IOException {
    File file = files.get(0);
    byte[] content = Files.readAllBytes(file.toPath());
    List<Row> rows = read(file.getPath(), true).orderBy("offset").collectAsList();
    long next = 0;
    for (Row row : rows) {
      long offset = row.getLong(0);
      byte[] line = row.getString(1).getBytes(StandardCharsets.UTF_8);
      assertEquals(next, offset);
      assertArrayEquals(line, (byte[]) row.get(2));
      byte[] inFile = new byte[line.length];
      System.arraycopy(content, (int) offset, inFile, 0, line.length);
      assertArrayEquals(line, inFile);
      // The next line starts after the terminator
      next = offset + line.length;
      if (next < content.length && content[(int) next] == '\r') {
        next++;
      }
      next++;
    }
    assertEquals(content.length + 1, next);
  }
}

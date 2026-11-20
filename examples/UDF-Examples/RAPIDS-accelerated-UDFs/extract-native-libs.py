#!/usr/bin/env python3
#
# Copyright (c) 2026, NVIDIA CORPORATION.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

"""Extract native cuDF libraries from a rapids-4-spark jar.

Large native libraries may be stored as a versioned manifest and numbered
chunks. This script supports both that representation and conventional jar
entries such as amd64/Linux/libcudf.so.
"""

import argparse
import binascii
import ctypes
import ctypes.util
import os
import shutil
import tempfile
import zipfile


COPY_BUFFER_SIZE = 1024 * 1024
MANIFEST_SUFFIX = ".chunks.properties"
CHUNK_DIRECTORY_SUFFIX = ".chunks"
CUDF_LIBRARY_NAME = "libcudf.so"


def parse_properties(data, manifest_name):
    properties = {}
    for raw_line in data.decode("utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith(("#", "!")):
            continue
        key, separator, value = line.partition("=")
        if not separator:
            raise RuntimeError(f"Invalid property in {manifest_name}: {raw_line!r}")
        properties[key.strip()] = value.strip()
    return properties


def require_property(properties, key, manifest_name):
    value = properties.get(key)
    if not value:
        raise RuntimeError(f"Missing {key} in {manifest_name}")
    return value


def parse_positive_int(properties, key, manifest_name):
    value = require_property(properties, key, manifest_name)
    try:
        result = int(value)
    except ValueError as error:
        raise RuntimeError(f"Invalid {key} in {manifest_name}: {value}") from error
    if result <= 0:
        raise RuntimeError(f"{key} must be positive in {manifest_name}: {value}")
    return result


def temporary_output(output_dir, library_name):
    descriptor, path = tempfile.mkstemp(prefix=f".{library_name}.", dir=output_dir)
    return os.fdopen(descriptor, "wb"), path


def install_output(temporary_path, output_path):
    os.chmod(temporary_path, 0o755)
    os.replace(temporary_path, output_path)


def extract_conventional_library(archive, entry_name, output_dir):
    library_name = os.path.basename(entry_name)
    output_path = os.path.join(output_dir, library_name)
    output, temporary_path = temporary_output(output_dir, library_name)
    try:
        with output, archive.open(entry_name) as source:
            shutil.copyfileobj(source, output, COPY_BUFFER_SIZE)
        install_output(temporary_path, output_path)
    except Exception:
        try:
            os.remove(temporary_path)
        except FileNotFoundError:
            pass
        raise
    print(f"Extracted {entry_name} -> {output_path}")


def load_zstd():
    # Use the system library; older Python versions in the build image have no zstd module.
    name = ctypes.util.find_library("zstd")
    if not name:
        raise RuntimeError("Cannot decode zstd native chunks: install the libzstd runtime")
    lib = ctypes.CDLL(name)
    size = ctypes.c_size_t
    lib.ZSTD_decompress.argtypes = [ctypes.c_void_p, size, ctypes.c_void_p, size]
    lib.ZSTD_decompress.restype = size
    lib.ZSTD_isError.argtypes = [size]
    lib.ZSTD_isError.restype = ctypes.c_uint
    lib.ZSTD_getErrorName.argtypes = [size]
    lib.ZSTD_getErrorName.restype = ctypes.c_char_p
    return lib


def chunk_blocks(source, chunk_name, expected_size, zstd):
    if zstd is None:
        yield from iter(lambda: source.read(COPY_BUFFER_SIZE), b"")
        return

    # Each entry is one independent frame. Limit output to the manifest chunk size.
    frame = source.read()
    decoded = ctypes.create_string_buffer(expected_size)
    length = zstd.ZSTD_decompress(decoded, expected_size, frame, len(frame))
    if zstd.ZSTD_isError(length):
        reason = zstd.ZSTD_getErrorName(length).decode()
        raise RuntimeError(f"Cannot decode zstd chunk {chunk_name}: {reason}")
    yield memoryview(decoded).cast("B")[:length]


def reconstruct_chunked_library(archive, manifest_name, output_dir):
    library_entry = manifest_name[: -len(MANIFEST_SUFFIX)]
    library_name = os.path.basename(library_entry)
    properties = parse_properties(archive.read(manifest_name), manifest_name)

    format_version = require_property(properties, "format.version", manifest_name)
    if format_version != "1":
        raise RuntimeError(
            f"Unsupported native chunk format.version in {manifest_name}: {format_version}"
        )

    compression = properties.get("chunk.compression", "none")
    if compression not in ("none", "zstd"):
        raise RuntimeError(f"Unsupported chunk.compression in {manifest_name}: {compression}")
    zstd = load_zstd() if compression == "zstd" else None

    library_size = parse_positive_int(properties, "library.size", manifest_name)
    chunk_size = parse_positive_int(properties, "chunk.size", manifest_name)
    chunk_count = parse_positive_int(properties, "chunk.count", manifest_name)
    expected_count = (library_size + chunk_size - 1) // chunk_size
    if chunk_count != expected_count:
        raise RuntimeError(
            f"Invalid chunk.count in {manifest_name}: expected {expected_count}, "
            f"found {chunk_count}"
        )

    output_path = os.path.join(output_dir, library_name)
    output, temporary_path = temporary_output(output_dir, library_name)
    total_bytes = 0
    try:
        with output:
            for index in range(chunk_count):
                chunk_name = (
                    f"{library_entry}{CHUNK_DIRECTORY_SUFFIX}/{index:05d}"
                )
                expected_size = min(chunk_size, library_size - total_bytes)
                crc_key = f"chunk.{index:05d}.crc32"
                expected_crc_text = require_property(properties, crc_key, manifest_name)
                try:
                    expected_crc = int(expected_crc_text, 16)
                except ValueError as error:
                    raise RuntimeError(
                        f"Invalid {crc_key} in {manifest_name}: {expected_crc_text}"
                    ) from error

                actual_size = 0
                actual_crc = 0
                try:
                    source = archive.open(chunk_name)
                except KeyError as error:
                    raise RuntimeError(
                        f"Missing native library chunk {chunk_name}"
                    ) from error
                with source:
                    for data in chunk_blocks(source, chunk_name, expected_size, zstd):
                        output.write(data)
                        actual_size += len(data)
                        actual_crc = binascii.crc32(data, actual_crc)

                actual_crc &= 0xFFFFFFFF
                if actual_size != expected_size:
                    raise RuntimeError(
                        f"Invalid size for {chunk_name}: expected {expected_size}, "
                        f"found {actual_size}"
                    )
                if actual_crc != expected_crc:
                    raise RuntimeError(
                        f"CRC32 mismatch for {chunk_name}: expected "
                        f"{expected_crc:08x}, found {actual_crc:08x}"
                    )
                total_bytes += actual_size

        if total_bytes != library_size:
            raise RuntimeError(
                f"Invalid reconstructed size for {library_name}: expected "
                f"{library_size}, found {total_bytes}"
            )
        install_output(temporary_path, output_path)
    except Exception:
        try:
            os.remove(temporary_path)
        except FileNotFoundError:
            pass
        raise
    print(
        f"Reconstructed {library_name} from {chunk_count} chunks -> {output_path}"
    )


def find_native_entries(archive):
    conventional = {}
    chunked = {}
    for entry in archive.infolist():
        if entry.is_dir():
            continue
        basename = os.path.basename(entry.filename)
        if basename.endswith(MANIFEST_SUFFIX):
            library_name = basename[: -len(MANIFEST_SUFFIX)]
            if library_name == CUDF_LIBRARY_NAME:
                chunked.setdefault(library_name, []).append(entry.filename)
        elif basename == CUDF_LIBRARY_NAME:
            conventional.setdefault(basename, []).append(entry.filename)

    duplicates = {
        name: entries
        for name, entries in {**conventional, **chunked}.items()
        if len(entries) != 1
    }
    if duplicates:
        details = "; ".join(
            f"{name}: {', '.join(entries)}" for name, entries in duplicates.items()
        )
        raise RuntimeError(f"Multiple jar entries map to the same native library: {details}")

    overlap = sorted(set(conventional).intersection(chunked))
    if overlap:
        raise RuntimeError(
            "Jar contains conventional and chunked representations for: "
            + ", ".join(overlap)
        )
    return conventional, chunked


def extract_native_libraries(jar_path, output_dir):
    os.makedirs(output_dir, exist_ok=True)
    with zipfile.ZipFile(jar_path) as archive:
        conventional, chunked = find_native_entries(archive)
        if CUDF_LIBRARY_NAME not in conventional and CUDF_LIBRARY_NAME not in chunked:
            raise RuntimeError(
                "libcudf.so was not found as a conventional library or chunk manifest "
                f"in {jar_path}"
            )
        for library_name in sorted(conventional):
            extract_conventional_library(
                archive, conventional[library_name][0], output_dir
            )
        for library_name in sorted(chunked):
            reconstruct_chunked_library(archive, chunked[library_name][0], output_dir)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("jar", help="rapids-4-spark jar")
    parser.add_argument("output_dir", help="directory for reconstructed native libraries")
    args = parser.parse_args()

    try:
        extract_native_libraries(args.jar, args.output_dir)
    except (OSError, RuntimeError, UnicodeError, zipfile.BadZipFile) as error:
        parser.exit(1, f"ERROR: {error}\n")


if __name__ == "__main__":
    main()

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

import binascii
import importlib.util
import pathlib
import tempfile
import unittest
import zipfile


SCRIPT_PATH = pathlib.Path(__file__).with_name("extract-native-libs.py")
SPEC = importlib.util.spec_from_file_location("extract_native_libs", SCRIPT_PATH)
EXTRACTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXTRACTOR)

# Independent frames from `zstd -c` on each part (including a short final chunk).
PARTS = (b"libcudf" * 32, b"tail")
FRAMES = (
    bytes.fromhex("28b52ffd0458750000386c69626375646601005651c5085e72abfd"),
    bytes.fromhex("28b52ffd04582100007461696cdd2bfacb"),
)


class ExtractNativeLibrariesTest(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary_directory.name)

    def tearDown(self):
        self.temporary_directory.cleanup()

    def write_conventional_jar(self, cudf_data):
        jar_path = self.root / "conventional.jar"
        with zipfile.ZipFile(jar_path, "w") as archive:
            archive.writestr("amd64/Linux/libcudf.so", cudf_data)
        return jar_path

    def write_chunked_jar(
        self,
        data,
        *,
        chunk_size=7,
        format_version="1",
        compression=None,
        stored_chunks=None,
        corrupt_crc_index=None,
        omit_property=None,
        root=None,
    ):
        root = root or self.root
        jar_path = root / "chunked.jar"
        chunks = [
            data[offset : offset + chunk_size]
            for offset in range(0, len(data), chunk_size)
        ]
        properties = {
            "format.version": format_version,
            "library.size": str(len(data)),
            "chunk.size": str(chunk_size),
            "chunk.count": str(len(chunks)),
        }
        if compression is not None:
            properties["chunk.compression"] = compression
        for index, chunk in enumerate(chunks):
            crc = binascii.crc32(chunk) & 0xFFFFFFFF
            if index == corrupt_crc_index:
                crc ^= 1
            properties[f"chunk.{index:05d}.crc32"] = f"{crc:08x}"
        properties.pop(omit_property, None)

        base = "amd64/Linux/libcudf.so"
        with zipfile.ZipFile(jar_path, "w") as archive:
            manifest = "".join(f"{key}={value}\n" for key, value in properties.items())
            archive.writestr(base + EXTRACTOR.MANIFEST_SUFFIX, manifest)
            for index, chunk in enumerate(chunks if stored_chunks is None else stored_chunks):
                archive.writestr(
                    f"{base}{EXTRACTOR.CHUNK_DIRECTORY_SUFFIX}/{index:05d}", chunk
                )
        return jar_path

    def test_extracts_conventional_library(self):
        cudf_data = b"conventional libcudf"
        jar_path = self.write_conventional_jar(cudf_data)
        output_dir = self.root / "output"

        EXTRACTOR.extract_native_libraries(jar_path, output_dir)

        self.assertEqual(cudf_data, (output_dir / "libcudf.so").read_bytes())

    def test_reconstructs_chunked_library(self):
        cudf_data = b"chunked libcudf data spanning several entries"
        output_dir = self.root / "output"
        for compression in (None, "none"):
            with self.subTest(compression=compression):
                jar_path = self.write_chunked_jar(cudf_data, compression=compression)
                EXTRACTOR.extract_native_libraries(jar_path, output_dir)
                self.assertEqual(cudf_data, (output_dir / "libcudf.so").read_bytes())

    def test_reconstructs_zstd_chunks(self):
        cudf_data = b"".join(PARTS)
        jar_path = self.write_chunked_jar(
            cudf_data, chunk_size=len(PARTS[0]), compression="zstd", stored_chunks=FRAMES
        )
        output_dir = self.root / "output"
        EXTRACTOR.extract_native_libraries(jar_path, output_dir)
        self.assertEqual(cudf_data, (output_dir / "libcudf.so").read_bytes())

    def test_rejects_invalid_zstd_chunks_without_replacing_library(self):
        output_dir = self.root / "output"
        output_dir.mkdir()
        installed = output_dir / "libcudf.so"
        installed.write_bytes(b"previous library")
        cases = [
            ((FRAMES[0], FRAMES[1][:-1]), None, "Cannot decode zstd chunk .*00001"),
            ((FRAMES[1], FRAMES[1]), None, "Invalid size for .*00000"),
            (FRAMES, 1, "CRC32 mismatch for .*00001"),
        ]
        for stored, corrupt_crc, expected_error in cases:
            with self.subTest(expected_error=expected_error):
                jar = self.write_chunked_jar(
                    b"".join(PARTS), chunk_size=len(PARTS[0]), compression="zstd",
                    stored_chunks=stored, corrupt_crc_index=corrupt_crc,
                )
                with self.assertRaisesRegex(RuntimeError, expected_error):
                    EXTRACTOR.extract_native_libraries(jar, output_dir)
                self.assertEqual(installed.read_bytes(), b"previous library")
                self.assertEqual(list(output_dir.iterdir()), [installed])

    def test_rejects_invalid_manifest_metadata(self):
        cases = [
            {"format_version": "2"},
            {"compression": "unsupported"},
            {"omit_property": "library.size"},
            {"omit_property": "chunk.00000.crc32"},
        ]
        for index, arguments in enumerate(cases):
            with self.subTest(arguments=arguments):
                case_root = self.root / f"case-{index}"
                case_root.mkdir()
                jar_path = self.write_chunked_jar(
                    b"invalid metadata", root=case_root, **arguments
                )
                with self.assertRaises(RuntimeError):
                    EXTRACTOR.extract_native_libraries(jar_path, case_root / "output")

    def test_crc_failure_preserves_output_and_removes_temporary_file(self):
        jar_path = self.write_chunked_jar(
            b"corrupt chunk data", corrupt_crc_index=1
        )
        output_dir = self.root / "output"
        output_dir.mkdir()
        installed = output_dir / "libcudf.so"
        installed.write_bytes(b"previous valid library")

        with self.assertRaisesRegex(RuntimeError, "CRC32 mismatch"):
            EXTRACTOR.extract_native_libraries(jar_path, output_dir)

        self.assertEqual(b"previous valid library", installed.read_bytes())
        self.assertEqual([installed], list(output_dir.iterdir()))

    def test_requires_libcudf_entry(self):
        jar_path = self.root / "missing.jar"
        with zipfile.ZipFile(jar_path, "w") as archive:
            archive.writestr("README", b"no native libraries")

        with self.assertRaisesRegex(RuntimeError, "libcudf.so was not found"):
            EXTRACTOR.extract_native_libraries(jar_path, self.root / "output")


if __name__ == "__main__":
    unittest.main()

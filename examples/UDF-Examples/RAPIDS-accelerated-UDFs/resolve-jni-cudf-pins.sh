#!/bin/bash
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

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <rapids-4-spark-jar> <pins-output-dir> <properties-output-file>" >&2
    exit 1
fi

JAR_PATH="$1"
PINS_DIR="$2"
PROPERTIES_FILE="$3"

if [ ! -f "$JAR_PATH" ]; then
    echo "ERROR: rapids-4-spark jar not found: $JAR_PATH" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to read jar metadata and validate cudf-pins" >&2
    exit 1
fi

mkdir -p "$PINS_DIR"
mkdir -p "$(dirname "$PROPERTIES_FILE")"

read_property_from_jar() {
    local entry="$1"
    local property="$2"
    python3 - "$JAR_PATH" "$entry" "$property" <<'PY'
import sys
import zipfile

jar_path, entry, prop = sys.argv[1:]
try:
    with zipfile.ZipFile(jar_path) as jar:
        data = jar.read(entry).decode("utf-8", errors="replace")
except Exception:
    sys.exit(0)

for line in data.splitlines():
    key, sep, value = line.partition("=")
    if sep and key == prop:
        print(value)
        break
PY
}

normalize_github_raw_base() {
    local repo_url="$1"
    repo_url="${repo_url%.git}"
    case "$repo_url" in
        https://github.com/*)
            echo "${repo_url/github.com/raw.githubusercontent.com}"
            ;;
        *)
            echo ""
            ;;
    esac
}

download_file() {
    local url="$1"
    local output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$output"
    else
        echo "ERROR: curl or wget is required to download $url" >&2
        exit 1
    fi
}

JNI_INFO="cudf-spark-jni-version-info.properties"
CUDF_INFO="cudf-java-version-info.properties"

JNI_REVISION="$(read_property_from_jar "$JNI_INFO" revision || true)"
JNI_URL="$(read_property_from_jar "$JNI_INFO" url || true)"
CUDF_REVISION="$(read_property_from_jar "$CUDF_INFO" revision || true)"

if [ -z "$JNI_REVISION" ] || [ -z "$JNI_URL" ]; then
    echo "ERROR: Failed to read cudf-spark-jni revision/url from $JAR_PATH" >&2
    echo "Expected $JNI_INFO in the jar." >&2
    exit 1
fi

if [ -z "$CUDF_REVISION" ]; then
    echo "ERROR: Failed to read cuDF revision from $JAR_PATH" >&2
    echo "Expected $CUDF_INFO in the jar." >&2
    exit 1
fi

RAW_BASE="$(normalize_github_raw_base "$JNI_URL")"
if [ -z "$RAW_BASE" ]; then
    echo "ERROR: Unsupported cudf-spark-jni URL for automatic pin lookup: $JNI_URL" >&2
    echo "Only github.com URLs can be resolved automatically." >&2
    exit 1
fi

VERSIONS_FILE="$PINS_DIR/versions.json"
RAPIDS_CMAKE_SHA_FILE="$PINS_DIR/rapids-cmake.sha"
RAPIDS_CMAKE_FILE="$PINS_DIR/RAPIDS.cmake"

download_file "$RAW_BASE/$JNI_REVISION/thirdparty/cudf-pins/versions.json" "$VERSIONS_FILE"
download_file "$RAW_BASE/$JNI_REVISION/thirdparty/cudf-pins/rapids-cmake.sha" "$RAPIDS_CMAKE_SHA_FILE"

python3 - "$VERSIONS_FILE" <<'PY'
import json
import sys

versions_file = sys.argv[1]
with open(versions_file, encoding="utf-8") as fh:
    data = json.load(fh)

packages = data.get("packages")
if not isinstance(packages, dict) or not packages:
    raise SystemExit(f"ERROR: {versions_file} does not contain a non-empty packages map")

missing_metadata = []
for name, package in sorted(packages.items()):
    if "version" not in package:
        missing_metadata.append(f"{name}: missing version")
    has_git_source = "git_url" in package and "git_tag" in package
    has_url_source = "url" in package and "url_hash" in package
    if not (has_git_source or has_url_source):
        missing_metadata.append(f"{name}: missing pinned git/url source")

if missing_metadata:
    raise SystemExit("ERROR: invalid cudf-pins metadata:\n  " + "\n  ".join(missing_metadata))

required = ["CCCL", "rmm"]
missing_required = [name for name in required if name not in packages]
if missing_required:
    raise SystemExit("ERROR: cudf-pins missing required packages: " + ", ".join(missing_required))
PY

RAPIDS_CMAKE_SHA="$(tr -d '[:space:]' < "$RAPIDS_CMAKE_SHA_FILE")"
if [ -z "$RAPIDS_CMAKE_SHA" ]; then
    echo "ERROR: rapids-cmake sha file is empty: $RAPIDS_CMAKE_SHA_FILE" >&2
    exit 1
fi

download_file "https://raw.githubusercontent.com/rapidsai/rapids-cmake/$RAPIDS_CMAKE_SHA/RAPIDS.cmake" \
    "$RAPIDS_CMAKE_FILE"

cat > "$PROPERTIES_FILE" <<EOF
jar.cudf.revision=$CUDF_REVISION
jar.cudf.spark.jni.revision=$JNI_REVISION
jar.rapids.cmake.sha=$RAPIDS_CMAKE_SHA
jar.rapids.cmake.file=$RAPIDS_CMAKE_FILE
jar.cudf.pins.file=$VERSIONS_FILE
EOF

echo "Resolved native dependency pins from rapids-4-spark jar:"
echo "  cudf-spark-jni revision: $JNI_REVISION"
echo "  cuDF revision: $CUDF_REVISION"
echo "  rapids-cmake sha: $RAPIDS_CMAKE_SHA"
echo "  rapids-cmake entrypoint: $RAPIDS_CMAKE_FILE"
echo "  cuDF pins: $VERSIONS_FILE"

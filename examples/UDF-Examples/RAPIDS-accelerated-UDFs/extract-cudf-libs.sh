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

###############################################################################
# Extract libcudf.so from rapids-4-spark jar
#
# This script extracts prebuilt cuDF libraries from the rapids-4-spark jar
# to enable faster builds by avoiding building cuDF from source.
#
# Configuration values are read from pom.xml by default, but can be overridden
# using environment variables:
#
# Usage:
#   ./extract-cudf-libs.sh
#
# Environment Variables (optional, will use pom.xml values if not set):
#   RAPIDS_JAR_PATH      - explicit rapids-4-spark jar path
#   RAPIDS4SPARK_VERSION - rapids-4-spark version (e.g., 26.10.0 or 26.10.0-SNAPSHOT)
#   SCALA_VERSION        - Scala binary version (e.g., 2.12, 2.13)
#   CUDA_VERSION         - CUDA version (e.g., cuda11, cuda12)
#   CUDF_BRANCH          - cuDF git branch for headers (e.g., main, branch-26.10)
#
# Example with overrides:
#   RAPIDS4SPARK_VERSION=26.10.0 CUDA_VERSION=cuda12 ./extract-cudf-libs.sh
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${TARGET_DIR:-$SCRIPT_DIR/target}"
NATIVE_DEPS_DIR="$TARGET_DIR/native-deps"
CUDF_REPO_DIR="$TARGET_DIR/cudf-repo"
POM_FILE="$SCRIPT_DIR/pom.xml"

# Function to extract property value from pom.xml
# Usage: extract_pom_property "property_name"
extract_pom_property() {
    local property_name="$1"
    local value

    if [ ! -f "$POM_FILE" ]; then
        echo ""
        return
    fi
    
    # Use xmllint if available (more reliable)
    if command -v xmllint >/dev/null 2>&1; then
        value=$(xmllint --xpath "string(//*[local-name()='project']/*[local-name()='properties']/*[local-name()='${property_name}'])" "$POM_FILE" 2>/dev/null)
    else
        # Fallback to grep/sed (less robust but widely available)
        value=$(grep -A 1 "<${property_name}>" "$POM_FILE" | grep -v "^--$" | sed -n "s/.*<${property_name}>\(.*\)<\/${property_name}>.*/\1/p" | head -1 | xargs)
    fi
    
    echo "$value"
}

echo "=================================================="
echo "Extract cuDF Dependencies for UDF Examples"
echo "=================================================="
echo "Reading configuration from pom.xml..."

# Read defaults from pom.xml
POM_RAPIDS4SPARK_VERSION=$(extract_pom_property "rapids4spark.version")
POM_SCALA_VERSION=$(extract_pom_property "scala.binary.version")
POM_CUDA_VERSION=$(extract_pom_property "cuda.version")
POM_CUDF_BRANCH=$(extract_pom_property "cudf.git.branch")

# Use environment variables if set, otherwise use pom.xml values
RAPIDS4SPARK_VERSION="${RAPIDS4SPARK_VERSION:-${POM_RAPIDS4SPARK_VERSION}}"
SCALA_VERSION="${SCALA_VERSION:-${POM_SCALA_VERSION}}"
CUDA_VERSION="${CUDA_VERSION:-${POM_CUDA_VERSION}}"
CUDF_BRANCH="${CUDF_BRANCH:-${POM_CUDF_BRANCH}}"

# Validate that we have all required values
if [ -z "$RAPIDS4SPARK_VERSION" ] || [ -z "$SCALA_VERSION" ] || [ -z "$CUDA_VERSION" ] || [ -z "$CUDF_BRANCH" ]; then
    echo "ERROR: Failed to read required properties from pom.xml" >&2
    echo "Please ensure pom.xml exists and contains all required properties:" >&2
    echo "  - rapids4spark.version" >&2
    echo "  - scala.binary.version" >&2
    echo "  - cuda.version" >&2
    echo "  - cudf.git.branch" >&2
    exit 1
fi

echo "Configuration:"
echo "  RAPIDS4SPARK_VERSION: $RAPIDS4SPARK_VERSION"
echo "  SCALA_VERSION: $SCALA_VERSION"
echo "  CUDA_VERSION: $CUDA_VERSION"
echo "  CUDF_BRANCH: $CUDF_BRANCH"
echo "=================================================="

# Create directories
mkdir -p "$NATIVE_DEPS_DIR"
mkdir -p "$CUDF_REPO_DIR"

# Find rapids-4-spark jar in local Maven repository
MAVEN_REPO="${HOME}/.m2/repository"

# Try multiple naming patterns
JAR_PATH_WITH_CLASSIFIER="$MAVEN_REPO/com/nvidia/rapids-4-spark_${SCALA_VERSION}/${RAPIDS4SPARK_VERSION}/rapids-4-spark_${SCALA_VERSION}-${RAPIDS4SPARK_VERSION}-${CUDA_VERSION}.jar"
JAR_PATH_NO_CLASSIFIER="$MAVEN_REPO/com/nvidia/rapids-4-spark_${SCALA_VERSION}/${RAPIDS4SPARK_VERSION}/rapids-4-spark_${SCALA_VERSION}-${RAPIDS4SPARK_VERSION}.jar"

echo "Looking for rapids-4-spark jar..."
if [ -n "${RAPIDS_JAR_PATH:-}" ]; then
    echo "  Explicit path: $RAPIDS_JAR_PATH"
fi
echo "  Pattern 1 (with classifier): $JAR_PATH_WITH_CLASSIFIER"
echo "  Pattern 2 (no classifier):   $JAR_PATH_NO_CLASSIFIER"

if [ -n "${RAPIDS_JAR_PATH:-}" ] && [ -f "$RAPIDS_JAR_PATH" ]; then
    JAR_PATH="$RAPIDS_JAR_PATH"
    echo "✓ Found jar (explicit path): $JAR_PATH"
elif [ -f "$JAR_PATH_WITH_CLASSIFIER" ]; then
    JAR_PATH="$JAR_PATH_WITH_CLASSIFIER"
    echo "✓ Found jar (with classifier): $JAR_PATH"
elif [ -f "$JAR_PATH_NO_CLASSIFIER" ]; then
    JAR_PATH="$JAR_PATH_NO_CLASSIFIER"
    echo "✓ Found jar (no classifier): $JAR_PATH"
else
    echo ""
    echo "ERROR: rapids-4-spark jar not found!"
    echo "Tried:"
    if [ -n "${RAPIDS_JAR_PATH:-}" ]; then
        echo "  $RAPIDS_JAR_PATH"
    fi
    echo "  $JAR_PATH_WITH_CLASSIFIER"
    echo "  $JAR_PATH_NO_CLASSIFIER"
    echo ""
    echo "For SNAPSHOT versions:"
    echo "  cd /path/to/spark-rapids"
    echo "  mvn clean install -DskipTests"
    echo ""
    echo "For release versions:"
    echo "  mvn dependency:get -Dartifact=com.nvidia:rapids-4-spark_${SCALA_VERSION}:${RAPIDS4SPARK_VERSION}:jar:${CUDA_VERSION}"
    exit 1
fi

# Extract or reconstruct libcudf.so and dependencies
echo "Extracting native libraries from jar..."
echo "  Jar: $JAR_PATH"
echo "  Supports conventional and chunked native library entries"

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to extract native libraries" >&2
    exit 1
fi

python3 "$SCRIPT_DIR/extract-native-libs.py" "$JAR_PATH" "$NATIVE_DEPS_DIR"

# Verify that libcudf.so was successfully written to the final location
if [ ! -f "$NATIVE_DEPS_DIR/libcudf.so" ]; then
    echo "ERROR: libcudf.so not found in $NATIVE_DEPS_DIR" >&2
    exit 1
fi

echo "✓ Successfully extracted libraries to: $NATIVE_DEPS_DIR"

PINS_DIR="$TARGET_DIR/cudf-pins"
PINS_PROPERTIES="$TARGET_DIR/jar-native-deps.properties"
"$SCRIPT_DIR/resolve-jni-cudf-pins.sh" "$JAR_PATH" "$PINS_DIR" "$PINS_PROPERTIES"
RESOLVED_CUDF_REF=$(awk -F= '$1 == "jar.cudf.revision" {print $2; exit}' "$PINS_PROPERTIES")
if [ -z "$RESOLVED_CUDF_REF" ]; then
    echo "ERROR: Failed to resolve cuDF revision from $PINS_PROPERTIES" >&2
    exit 1
fi

# Clone cuDF repo for headers (shallow clone)
if [ ! -d "$CUDF_REPO_DIR/.git" ]; then
    echo "Cloning cuDF repository for headers..."
else
    echo "✓ cuDF repo already exists at: $CUDF_REPO_DIR"
fi
"$SCRIPT_DIR/clone-cudf-repo.sh" "$CUDF_REPO_DIR" "$RESOLVED_CUDF_REF"

echo ""
echo "=================================================="
echo "Setup complete! You can now build with:"
echo "  mvn clean package -P udf-native-examples"
echo ""
echo "This will use prebuilt libcudf.so and avoid"
echo "building cuDF from source (much faster!)."
echo "=================================================="


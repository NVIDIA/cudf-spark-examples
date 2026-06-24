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
#   RAPIDS4SPARK_VERSION - rapids-4-spark version (e.g., 26.06.0 or 26.06.0-SNAPSHOT)
#   SCALA_VERSION        - Scala binary version (e.g., 2.12, 2.13)
#   CUDA_VERSION         - CUDA version (e.g., cuda11, cuda12)
#   CUDF_BRANCH          - cuDF git branch for headers (e.g., main, branch-26.06)
#
# Example with overrides:
#   RAPIDS4SPARK_VERSION=26.06.0 CUDA_VERSION=cuda11 ./extract-cudf-libs.sh
###############################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$SCRIPT_DIR/target"
NATIVE_DEPS_DIR="$TARGET_DIR/native-deps"
CUDF_REPO_DIR="$TARGET_DIR/cudf-repo"
POM_FILE="$SCRIPT_DIR/pom.xml"

# Function to extract property value from pom.xml
# Usage: extract_pom_property "property_name"
extract_pom_property() {
    local property_name="$1"
    local value
    
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
echo "  Pattern 1 (with classifier): $JAR_PATH_WITH_CLASSIFIER"
echo "  Pattern 2 (no classifier):   $JAR_PATH_NO_CLASSIFIER"

if [ -f "$JAR_PATH_WITH_CLASSIFIER" ]; then
    JAR_PATH="$JAR_PATH_WITH_CLASSIFIER"
    echo "✓ Found jar (with classifier): $JAR_PATH"
elif [ -f "$JAR_PATH_NO_CLASSIFIER" ]; then
    JAR_PATH="$JAR_PATH_NO_CLASSIFIER"
    echo "✓ Found jar (no classifier): $JAR_PATH"
else
    echo ""
    echo "ERROR: rapids-4-spark jar not found!"
    echo "Tried:"
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

# Extract libcudf.so and dependencies
echo "Extracting native libraries from jar..."
echo "  Jar: $JAR_PATH"
echo "  Looking for: */libcudf.so*, */libnvcomp.so*"

# Use unzip without -q to capture output, but redirect to log for debugging
UNZIP_OUTPUT=$(unzip -o "$JAR_PATH" "*/libcudf.so*" "*/libnvcomp.so*" -d "$TARGET_DIR/temp" 2>&1)
UNZIP_EXIT_CODE=$?

# Check unzip exit code
if [ $UNZIP_EXIT_CODE -ne 0 ]; then
    echo "ERROR: Failed to extract libraries from jar" >&2
    echo "unzip exit code: $UNZIP_EXIT_CODE" >&2
    
    # Provide helpful diagnostics
    case $UNZIP_EXIT_CODE in
        11)
            echo "Reason: No matching files found in jar" >&2
            echo "" >&2
            echo "The jar may not contain native libraries for your platform." >&2
            echo "Expected patterns: */libcudf.so*, */libnvcomp.so*" >&2
            echo "" >&2
            echo "Listing jar contents:" >&2
            unzip -l "$JAR_PATH" | grep -E '\.(so|dylib|dll)' || echo "  No native libraries found" >&2
            ;;
        *)
            echo "Reason: unzip command failed" >&2
            echo "Output: $UNZIP_OUTPUT" >&2
            ;;
    esac
    
    echo "" >&2
    echo "Falling back to source build..." >&2
    exit 1
fi

# Verify that we actually extracted some files
EXTRACTED_COUNT=$(find "$TARGET_DIR/temp" -name "*.so*" 2>/dev/null | wc -l)
echo "Extracted $EXTRACTED_COUNT library file(s)"

if [ "$EXTRACTED_COUNT" -eq 0 ]; then
    echo "ERROR: No library files were extracted from jar" >&2
    echo "This usually means the jar doesn't contain native libraries." >&2
    echo "" >&2
    echo "Listing jar contents:" >&2
    unzip -l "$JAR_PATH" | head -20 >&2
    exit 1
fi

# Move libraries to native-deps directory, detecting conflicts
echo "Moving extracted libraries..."
CONFLICT_COUNT=0

# Use process substitution to avoid subshell issues
while IFS= read -r source_file; do
    filename=$(basename "$source_file")
    dest_file="$NATIVE_DEPS_DIR/$filename"
    
    if [ -f "$dest_file" ]; then
        # File already exists - check if it's the same
        if ! cmp -s "$source_file" "$dest_file"; then
            echo "WARNING: Conflicting library detected: $filename" >&2
            echo "  Existing: $dest_file" >&2
            echo "  New:      $source_file" >&2
            echo "  Keeping existing file, skipping new one" >&2
            CONFLICT_COUNT=$((CONFLICT_COUNT + 1))
        fi
        # Remove the duplicate source file
        rm -f "$source_file"
    else
        # No conflict, move the file
        mv "$source_file" "$dest_file"
    fi
done < <(find "$TARGET_DIR/temp" -name "*.so*")

if [ "$CONFLICT_COUNT" -gt 0 ]; then
    echo "WARNING: $CONFLICT_COUNT library file(s) had conflicts. Review the warnings above." >&2
fi

rm -rf "$TARGET_DIR/temp"

# Verify that libcudf.so was successfully moved to final location
if [ ! -f "$NATIVE_DEPS_DIR/libcudf.so" ]; then
    echo "ERROR: libcudf.so not found in $NATIVE_DEPS_DIR" >&2
    echo "" >&2
    echo "This could mean:" >&2
    echo "  1. The jar didn't contain libcudf.so" >&2
    echo "  2. Extraction succeeded but moving files failed" >&2
    echo "  3. Wrong architecture (jar might be for a different platform)" >&2
    echo "" >&2
    echo "Contents of $NATIVE_DEPS_DIR:" >&2
    ls -lh "$NATIVE_DEPS_DIR" >&2 || echo "  Directory is empty or doesn't exist" >&2
    exit 1
fi

echo "✓ Successfully extracted libraries to: $NATIVE_DEPS_DIR"
ls -lh "$NATIVE_DEPS_DIR"

# Clone cuDF repo for headers (shallow clone)
if [ ! -d "$CUDF_REPO_DIR/.git" ]; then
    echo "Cloning cuDF repository for headers..."
    git clone --depth 1 --branch "$CUDF_BRANCH" https://github.com/rapidsai/cudf.git "$CUDF_REPO_DIR"
    echo "✓ Cloned cuDF repo to: $CUDF_REPO_DIR"
else
    echo "✓ cuDF repo already exists at: $CUDF_REPO_DIR"
    echo "  (Delete it to re-clone: rm -rf \"$CUDF_REPO_DIR\")"
fi

echo ""
echo "=================================================="
echo "Setup complete! You can now build with:"
echo "  mvn clean package -P udf-native-examples"
echo ""
echo "This will use prebuilt libcudf.so and avoid"
echo "building cuDF from source (much faster!)."
echo "=================================================="


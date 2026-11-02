#!/usr/bin/env bash
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

# CI-only wrapper; preserve the existing local/Jenkins test entry point.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

nvidia-smi 2>&1 | tee "$RUNNER_TEMP/gpu-ci.log"
test -s target/native-runtime/librmm.so
test -s target/native-runtime/librapids_logger.so
export LD_LIBRARY_PATH="$PWD/target/native-runtime${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
bash run_pyspark_from_build.sh --rapids_udf_example_native \
  --junitxml="$RUNNER_TEMP/gpu-ci.xml" 2>&1 | tee -a "$RUNNER_TEMP/gpu-ci.log"

python - <<'PY'
import os
import xml.etree.ElementTree as ET

report = ET.parse(os.path.join(os.environ["RUNNER_TEMP"], "gpu-ci.xml"))
if not report.findall(".//testcase") or any(
    report.findall(f".//{result}") for result in ("skipped", "failure", "error")
):
    raise SystemExit("UDF tests must execute and pass without skips")
PY

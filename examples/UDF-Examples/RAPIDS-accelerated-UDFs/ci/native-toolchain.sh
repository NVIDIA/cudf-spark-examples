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

# CI-only image operations. PRs pull anonymously; only trusted main refreshes/publishes.
set -euo pipefail

context=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
checksum=$(sha256sum "$context/Dockerfile" | cut -d ' ' -f 1)
image="ghcr.io/${GITHUB_REPOSITORY,,}/udf-native-toolchain"
tag="$image:dockerfile-$checksum"

case "${1:-}" in
  pull)
    # A new Dockerfile builds locally until its image is published.
    if timeout 5m docker pull --platform linux/amd64 "$tag"; then
      docker tag "$tag" udf-ci:local
      digest=$(docker image inspect --format '{{index .RepoDigests 0}}' "$tag")
      printf 'available=true\n' >> "$GITHUB_OUTPUT"
      printf 'Native toolchain: %s\n' "$digest" >> "$GITHUB_STEP_SUMMARY"
    else
      echo "::warning::Published native toolchain unavailable; building the checked-out Dockerfile."
      printf 'Native toolchain: local build (published image unavailable).\n' >> "$GITHUB_STEP_SUMMARY"
    fi
    ;;
  refresh)
    # Refresh base-image and OS packages even when the Dockerfile has not changed.
    docker buildx build --pull --no-cache --platform linux/amd64 --load \
      --label "org.opencontainers.image.source=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY" \
      --label "org.opencontainers.image.revision=$GITHUB_SHA" \
      --tag udf-ci:local "$context"

    docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp \
      -v "$context:/udf:ro" -w /udf \
      --entrypoint /bin/bash udf-ci:local ci/build-udfs.sh smoke
    ;;
  publish)
    anonymous_config=$(mktemp -d)
    trap 'docker logout ghcr.io; rm -rf "$anonymous_config"' EXIT
    printf '%s' "$GHCR_TOKEN" | docker login ghcr.io --username "$GHCR_USER" --password-stdin

    # Only promote a smoke-tested, anonymously readable candidate.
    docker tag udf-ci:local "$image:candidate"
    docker push "$image:candidate"
    reference=$(docker image inspect --format '{{index .RepoDigests 0}}' "$image:candidate")
    if ! docker --config "$anonymous_config" pull --platform linux/amd64 "$reference"; then
      echo "::error::Verify GHCR availability and make the udf-native-toolchain package public, then rerun. The consumer tag has not been updated."
      exit 1
    fi

    docker buildx imagetools create --prefer-index=false --tag "$tag" "$reference"
    printf 'Published %s from %s.\n' "$tag" "$reference" >> "$GITHUB_STEP_SUMMARY"
    ;;
  *)
    echo "Usage: $0 {pull|refresh|publish}" >&2
    exit 2
    ;;
esac

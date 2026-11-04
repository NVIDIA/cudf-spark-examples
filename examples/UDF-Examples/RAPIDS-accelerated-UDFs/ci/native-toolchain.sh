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
image_name=udf-native-toolchain
image="ghcr.io/${GITHUB_REPOSITORY,,}/$image_name"
tag="$image:main"
# Version the toolchain recipe, not the examples project or release branch.
image_version="dockerfile-$checksum"

case "${1:-}" in
  config)
    jq -cn --arg image "$image_name" --arg version "$image_version" --arg context "$context" '{
      image: $image, tag: "main", version: $version,
      context: $context, dockerfile: ($context + "/Dockerfile"),
      platform: "linux/amd64", "smoke-test": ($context + "/ci/native-toolchain-smoke.sh")
    }'
    ;;
  pull)
    # The shared tag is usable only when it matches this checkout's Dockerfile.
    reason="published image unavailable"
    if timeout 5m docker pull --platform linux/amd64 "$tag"; then
      if metadata=$(docker image inspect "$tag") &&
        image_id=$(jq -er --arg version "$image_version" '
          .[0] | select(.Config.Labels["org.opencontainers.image.version"] == $version) |
          .Id | select(type == "string" and test("^sha256:[0-9a-f]{64}$"))' <<< "$metadata"); then
        # Use the exact inspected image even if another pull changes the local tag.
        docker tag "$image_id" udf-ci:local
        printf 'available=true\n' >> "$GITHUB_OUTPUT"
        printf 'Native toolchain: %s (%s), Dockerfile matched.\n' "$tag" "$image_id" >> "$GITHUB_STEP_SUMMARY"
        exit 0
      fi
      reason="published image metadata does not match the checked-out Dockerfile"
    fi
    echo "::warning::Native toolchain: $reason; building the checked-out Dockerfile."
    printf 'Native toolchain: local build (%s).\n' "$reason" >> "$GITHUB_STEP_SUMMARY"
    ;;
  refresh)
    # Refresh base-image and OS packages even when the Dockerfile has not changed.
    docker buildx build --pull --no-cache --platform linux/amd64 --load \
      --label "org.opencontainers.image.source=$GITHUB_SERVER_URL/$GITHUB_REPOSITORY" \
      --label "org.opencontainers.image.revision=$GITHUB_SHA" \
      --label "org.opencontainers.image.version=$image_version" \
      --tag udf-ci:local "$context"

    bash "$context/ci/native-toolchain-smoke.sh" udf-ci:local linux/amd64
    ;;
  publish)
    anonymous_config=$(mktemp -d)
    trap 'docker logout ghcr.io; rm -rf "$anonymous_config"' EXIT
    printf '%s' "$GHCR_TOKEN" | docker login ghcr.io --username "$GHCR_USER" --password-stdin

    # Only promote a smoke-tested, anonymously readable candidate.
    docker tag udf-ci:local "$image:candidate"
    docker push "$image:candidate"
    # Buildx --load may put a local udf-ci digest before the pushed GHCR digest.
    reference=$(docker image inspect --format '{{json .RepoDigests}}' "$image:candidate" |
      jq -er --arg image "$image" '
        map(select(startswith($image + "@sha256:"))) | unique |
        if length == 1 then .[0] else error("Expected one digest for " + $image) end')
    printf 'Verifying anonymous pull: %s\n' "$reference"
    if ! docker --config "$anonymous_config" pull --platform linux/amd64 "$reference"; then
      echo "::error::Anonymous pull failed for $reference. Check registry availability and package visibility. The consumer tag has not been updated."
      exit 1
    fi

    docker buildx imagetools create --prefer-index=false --tag "$tag" "$reference"
    printf 'Published %s from %s.\n' "$tag" "$reference" >> "$GITHUB_STEP_SUMMARY"
    ;;
  *)
    echo "Usage: $0 {config|pull|refresh|publish}" >&2
    exit 2
    ;;
esac

# Agent Guide

## Scope

- Start with the affected example's README and build/test scripts; examples are
  independent. Keep edits scoped and preserve local/Jenkins entry points.
- Configure CI through existing Maven, CMake, and script interfaces before changing
  product code. Keep UDF commands in `examples/UDF-Examples/RAPIDS-accelerated-UDFs/ci/`.
- Reuse `NVIDIA/spark-rapids-common` for selection, gating, and runner fallback;
  keep workload policy here. Do not duplicate workflows or shared helpers.

## CI Contracts

- Read `.github/workflows/` and `.github/gpu-ci-suites.json` together. New suites
  need catalog paths/job IDs, workflow selection, worker support, and gate `needs`.
  GPU CI currently covers native and non-native UDFs only.
- Cover source, tests, build, image, and workflow inputs. `exclude_paths` applies
  within each suite; `shared_paths` selects all enabled suites, including catalog
  changes. Disabled suites need an explanatory `comment`.
- Keep selector and `GPU CI gate` active for unaffected changes: no event-level
  path filters, retain `if: always()` and direct `needs`. Selected jobs must pass;
  missing/skipped jobs and selection errors must fail. Keep unrelated CPU checks
  independent and preserve existing required checks.
- Each head needs maintainer `/ok to test <full-head-SHA>` approval before
  copy-pr-bot pushes `pull-request/<number>`. Preserve worker/source guards:
  the write-enabled coordinator must not execute PR code; workers get no publishing
  credentials. Publish images separately from trusted source.
- Use common `runner-type` defaults, not copied pool lists. Fallback applies only
  while queued, never after a build/test failure. UDF artifacts target Linux amd64;
  verify compatibility before changing architecture or GPU count.
- Build once on CPU; transfer SHA-checked artifacts and required native libraries.
  Reuse compatible Maven/CPM/ccache entries: main seeds the baseline, PRs prefer
  their own caches. Cache misses are acceptable; missing artifacts are not.

## Validation and Delivery

- Maintain existing tests, including `test_extract_native_libs.py` for extraction
  changes. For CI scripts without tests, use focused checks instead of adding a
  harness. Run applicable `actionlint`, `bash -n`/ShellCheck, and `git diff --check`.
- Check affected/unaffected selection and failure gates. Verify actual GPU/native
  execution, image reuse versus local fallback, and cache hits in logs; report
  tested revisions and gaps rather than inferring coverage from green status.
- Follow `CONTRIBUTING.md` for signoff. Keep PR descriptions concise and public-safe.
  CI dispatch, publication, merging, rules, and draft status require authorization.

# Agent Guide

## Repository and Ownership

- This repository contains independent Spark examples, notebooks, and deployment
  helpers, not one application with a single build. Start with the affected
  example's README and existing build/test entry points.
- `examples/UDF-Examples/RAPIDS-accelerated-UDFs/` contains Java/Scala and native
  UDF examples, their Maven build, native Docker toolchain, and PySpark tests.
  `scripts/` and `tools/` serve other workflows; avoid unrelated changes to them.
- Preserve local and Jenkins entry points when changing GitHub CI. Configure the
  workflow through existing Maven, CMake, and script interfaces before changing
  product/build files; change those only for a demonstrated requirement in scope.
- Generic suite selection, result gating, and runner fallback belong in
  `NVIDIA/spark-rapids-common`. Reuse those actions; keep paths, commands, images,
  and approval policy here. Coordinate shared-action availability before rollout.

## Workflow and Suite Changes

- Inspect `.github/workflows/` and `.github/gpu-ci-suites.json` before adding CI.
  Reuse existing coverage instead of introducing duplicate workflows or builds.
  GPU CI currently covers native and non-native UDFs, not every example.
- `gpu-ci.yml` selects suites, builds artifacts once on CPU, coordinates GPU work,
  and reports `GPU CI gate`. `gpu-ci-worker.yml` executes the GPU tests.
  `udf-native-image.yml` separately publishes the trusted build image.
- Add or change a gated suite as one coordinated update: catalog `paths`,
  `exclude_paths`, `enabled`, `comment`, and `jobs`; matching workflow jobs and
  selection conditions; worker workload support if needed; and direct gate `needs`.
  Catalog `jobs` are actual job IDs (`build`, `gpu-test` for UDF), not display names
  or runner types. The catalog alone neither creates nor schedules jobs.
- Include relevant source, tests, build scripts, and image/workflow inputs in path
  coverage. Exclusions apply only inside that suite's included paths, not globally.
  `shared_paths` selects every enabled suite despite exclusions; use it only for
  shared workload inputs, not automatically for the catalog or copy-pr-bot config.
  Pause a suite with `enabled: false` and an explanation in `comment`.
- Keep selector and gate active when no workload matches. Do not add event-level
  path filtering to this gate workflow. Keep `if: always()` and list the selector
  and all checked jobs directly in gate `needs`. Required selected jobs must
  succeed; selection errors and missing/skipped required jobs must not pass.
- Do not move unrelated hosted CPU checks behind GPU approval. A separate CPU
  workflow/gate can reuse the same common actions. `needs` cannot observe an
  independently triggered workflow: a gate must aggregate its own jobs, not claim
  coverage from unrelated checks. Keep publishing outside PR test gates.
- Preserve stable gate names and existing required checks. Workflow code does not
  change repository rules; verify those separately before claiming enforcement.

## Approval, Resources, and Artifacts

- GPU CI starts on copy-pr-bot pushes to `pull-request/<number>` after a maintainer
  authorizes `/ok to test <full-head-SHA>`. Every new commit needs authorization,
  including unaffected changes before their gate can report. This is CI permission,
  not PR review approval; the shared selector does not validate that authorization.
- Keep worker identity/source checks and minimal permissions. The write-enabled
  coordinator must not execute PR code; test workers must not receive image
  publishing credentials. Do not switch to privileged PR execution for convenience.
- Use an explicit common `runner-type` instead of copying pool lists. Current UDF
  artifacts target Linux amd64 single-GPU workers; architecture/GPU-count changes
  require checking the native toolchain and artifacts, not just changing a label.
  Queue fallback must not replay a workload after compilation or test failure.
- Preserve one CPU build, source-SHA-checked artifact handoff, and required native
  runtime libraries. Reuse Maven, CPM, and ccache; keep keys/toolchains compatible.
  Cache misses are optional; missing build artifacts or failed tests are not.
- Publish stable images only from trusted source in the separate image workflow.
  Distinguish a prebuilt image pull from the local Docker build fallback in evidence.

## Validation and Handoff

- Use commands from the affected example's README and current workflow; native
  UDF tests need the matching CUDA/JDK/Spark environment and GPU. A CPU-only check
  is not evidence that GPU tests or native runtime loading passed.
- For native-library extraction changes, run the existing CPU test suite:

  ```sh
  python3 -m unittest discover -s examples/UDF-Examples/RAPIDS-accelerated-UDFs -p 'test_extract_native_libs.py' -v
  ```

- Maintain affected existing tests. For CI/release scripts with no suite, use
  focused checks or safe dry runs rather than adding a new harness without a request.
  Use `actionlint` for changed workflows, `bash -n`/ShellCheck for changed shell
  scripts, and `git diff --check`.
- Validate affected and unaffected/docs-only selection, mixed code/docs changes,
  renames/deletions, disabled suites, failed selection, and missing/skipped/failed
  required jobs. Confirm future suites reach the gate without running UDF-only work.
- Do not dispatch GPU validation, publish images, merge, or change repository rules
  without authorization. Preserve requested draft/DO NOT REVIEW status; production
  readiness alone does not authorize changing it.
- Follow `CONTRIBUTING.md` for signoff. Keep the PR body concise and current, with
  shared-component dependencies, exact tested revisions, and remaining validation
  gaps. Keep internal links, credentials, and infrastructure identifiers out of
  public descriptions and logs.

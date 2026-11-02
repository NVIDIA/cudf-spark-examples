# GPU CI

GPU CI currently covers the native and non-native UDF examples. The lightweight
`GPU CI gate` status evaluates every PR update targeting `main`. Changes outside the configured
paths pass without allocating a GPU; affected changes require a successful CPU
build and GPU test run for the current PR head.

## Approval and results

GPU execution still requires `/ok to test <full-head-SHA>`. The copied branch runs
the coordinator, which builds once and dispatches a worker with queue fallback.
The gate only accepts the latest matching coordinator run from copy-pr-bot's
`push` event on `pull-request/<number>` at that exact SHA. Dispatched workers and
their skipped PR-registration checks do not satisfy the gate directly.

The gate remains pending while approval or execution is outstanding. A failed,
cancelled, skipped, or missing required job cannot pass it. API/path-detection
errors also block the gate rather than treating the PR as unaffected. The gate
accepts a successful producer retained by "rerun failed jobs" within the same
run and SHA, but a newer failed or skipped attempt overrides that job's old pass.
Run/job metadata that changes during evaluation is rechecked up to three times;
unresolved inconsistency blocks the gate instead of accepting an older success.
It does not wait on a CPU runner for GPU work: coordinator lifecycle events refresh
the status. Rerunning the requirement workflow refreshes a failed assessment.

Suite selection uses the entire current PR diff, including deleted paths and both
sides of renames. A documentation-only follow-up push does not exempt an earlier
UDF code change in the same PR. Incomplete file lists fail closed.

## Adding suites

`.github/gpu-ci-suites.json` is the catalog shared by selection and enforcement.
Paths ending in `/` match a directory recursively; other paths match an exact
file. There are no glob patterns. Shared paths select all registered suites.

To add a suite:

1. Add a suite ID, affected paths, and exact required job names to the catalog.
2. Add its build/test jobs to `gpu-ci.yml`, conditioned on that suite ID in
   `needs.select.outputs.suites`. Reuse the common queue-fallback action for GPU
   execution, and make the coordinator job fail if its tests fail.
3. Keep required job names unique. The gate requires every listed job to finish
   successfully; listing only a downstream job could hide a skipped build.

For example, a later suite with a different examples directory and build/test
jobs needs a new catalog entry and those workflow jobs, not a new gate controller.
The privileged gate reads only trusted base/default-branch policy and GitHub
metadata. It never checks out PR code or downloads worker artifacts. New policy
entries take effect when merged into the trusted branch.

## Initial activation

The gate, suite catalog, coordinator, and UDF worker are introduced together.
After this PR is merged, verify `GPU CI gate` reports on an unaffected PR and on
an approved UDF validation run. Then add **GPU CI gate**, with GitHub Actions as
its source, to the required status checks for `main`, retaining `signoff-check`.
Do not require `worker`, `GPU sanity`, or `Assess GPU CI requirement` instead.

This ruleset setting is repository administration, not a workflow-file change.
Do not enable it before the trusted gate workflow is available, or apply it to
release branches that do not yet contain the gate. Existing PRs need a new PR
event (for example, a description edit) to initialize their status. This workflow
does not yet implement merge-queue (`merge_group`) validation.

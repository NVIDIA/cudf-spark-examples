# GPU CI

GPU CI currently covers the native and non-native UDF examples for PRs targeting
`main`. One `GPU CI gate` job checks the selected suites in the approved
copied-branch workflow. Changes
outside the configured paths run only selection and the gate, without a build
or GPU allocation. Affected changes require a successful CPU build and GPU test
run for the approved PR head.

## Approval and results

Every PR needs `/ok to test <full-head-SHA>` to produce the gate, including
unaffected PRs. copy-pr-bot pushes that head to `pull-request/<number>`, which runs
the workflow. Before approval the check is absent, so a required-check ruleset
blocks merging. A new PR head needs new approval; there is no automatic GPU run.

The selector checks the full current PR diff, including deleted paths and both
sides of renames. A documentation-only follow-up push does not exempt an earlier
UDF change in the same PR. API errors, incomplete file lists, non-main targets,
and a copied SHA that no longer matches the PR head fail selection rather than
skipping tests. Target-branch changes during selection also fail the check.

The gate runs with `always()` and consumes job results from the same workflow
using the common `workflow-result-gate` action. Selected jobs must succeed;
skipped or missing required jobs cannot pass. Unselected jobs may skip, but
failures and cancellations still fail the gate. The selector must always pass.
Dispatched worker checks, including their skipped PR-registration checks, are
not the required gate; the coordinator waits for and propagates worker results.

This follows the approved-push aggregation pattern used by
[cuDF](https://github.com/NVIDIA/cudf/blob/main/.github/workflows/pr.yaml), with
explicit success requirements similar to
[CuPy's result checks](https://github.com/cupy/cupy/blob/main/.github/workflows/ci.yml).
The new GPU CI workflow does not need `pull_request_target`, `workflow_run`,
status-write permissions, or a run-status polling controller. Selection and the
gate use lightweight `ubuntu-slim` runners; Docker builds and the long-lived
queue coordinator retain `ubuntu-latest`.

## Adding suites

`.github/gpu-ci-suites.json` is the repo-owned selection catalog. Paths ending in
`/` match a directory recursively; other paths match an exact file. There are no
glob patterns. Shared paths select all registered suites.

1. Add a suite ID, affected paths, and required workflow **job IDs** to the catalog.
2. Add its build/test jobs to `gpu-ci.yml`, conditioned on that suite ID in
   `needs.select.outputs.suites`. Reuse the common queue-fallback action for GPU
   execution, and propagate test failures from the coordinator.
3. Add all new jobs directly to `gate.needs`, including build prerequisites.
   GitHub's `needs` context does not include transitive dependencies. The shared
   gate rejects required IDs absent from that context.

The selector emits `required-jobs` containing itself and every selected suite's
jobs. A later suite with different paths, builds, or runners needs only consumer
configuration and workflow changes, not changes to the shared gate action.
Reviewers approving a SHA must also review any changes to this CI policy.

## Initial activation

Merge the common `workflow-result-gate` action before enabling this consumer.
The gate, suite catalog, coordinator, and UDF worker are introduced together.
Validate both an approved unaffected PR and an approved UDF run, then configure
**GPU CI gate**, with GitHub Actions as its source, as a required check for `main`,
retaining `signoff-check`. Do not require `worker` or `GPU sanity` instead.

This ruleset setting is repository administration, not a workflow-file change.
Do not enable it before the workflow and common action are available, or apply
it to release branches that do not contain the gate. Existing PRs need their
branches updated to include this workflow and approval of the current head.
This workflow does not yet implement merge-queue (`merge_group`) validation.

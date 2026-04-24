# Baseline Capture Protocol

> How to capture the three baseline layers from the legacy Android code.
> The protocol is tool-agnostic; the `researcher`'s baseline-tooling
> pre-pass chose the specific libraries live.

## Contents

- [When](#when)
- [Layers](#layers)
- [Tolerance envelopes](#tolerance-envelopes)
- [Baseline manifest files](#baseline-manifest-files)

## When

Phase 1 only. No other phase writes under `kmm_migration/baseline/`.

## Layers

For each feature, capture:

1. **Unit layer** — characterization tests on OG Android code, all green,
   using the testing framework identified in `tech_stack_snapshot.md`.
2. **Screenshot layer** — goldens of OG UI using the screenshot framework
   identified in `tech_stack_snapshot.md`.
3. **E2E layer** — end-to-end flows against the OG APK using the E2E tool
   identified in `tech_stack_snapshot.md`.

## Tolerance envelopes

- Screenshot: per-platform change-threshold recorded in the manifest.
- E2E: retry policy recorded in the manifest (retries, timeout).
- Unit: no tolerance — tests pass or fail.

Tolerance envelopes are captured ONCE and immutable during migration
(Law 2). Named `rebase_baseline` escape hatch exists for post-hoc envelope
correction (spec §12.2).

## Baseline manifest files

Write under `kmm_migration/baseline/<feature>/`:

- `unit_tests_manifest.md` — test file paths, test names, coverage %.
- `screenshot_goldens_manifest.md` — golden file paths, tolerance per
  platform.
- `e2e_flows_manifest.md` — flow file paths, retry policy.
- `tech_stack_snapshot.md` — library name + version + context7 source
  for each of the three layers.

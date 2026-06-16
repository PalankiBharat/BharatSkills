---
name: qa
description: Use when running the automated parity QA round for a KMM migration in sniper-v2-android — "qa the migration", "parity qa", "prove android unchanged", after iOS wiring completes, or standalone on a kmm/* branch that has migration state (.kmm/migrations/).
argument-hint: "[feature-slug]"
---

# KMM Parity QA

Prove two things with artifacts: **Android is unchanged** and **iOS delivers the contract**. Inputs: the migration state dir (from `ACTIVE` or the argument) — `contract.md` is the spec, `qa-report.md` is your output. No state dir → ask for the diff range + contract path; without a contract you can only run lanes 1-4 and 9 and must say so in the verdict.

Dispatch lanes to kmm-qa-verifier agents. Gradle lanes run STRICTLY one-at-a-time (daemon contention corrupts results); grep/device lanes may parallelize. Every lane verdict needs an artifact path — the verifier knows this; hold the line when merging.

| # | Lane | Proof | Gate command(s) — verify via JUnit XML / output files |
|---|------|-------|--------------------------------------------------------|
| 1 | Static | style + analysis clean, and the gate actually RAN (non-zero files analyzed — a silently-dead detekt task has produced false "clean" claims here) | `ktlintCheck detekt`; `+ :app:detektBaselines :app:detektBaselineTests` when baseline files changed |
| 2 | Android logic | app + shared JVM tests green, and they RAN | `:app:testProductionDebugUnitTest` + `:shared` android unit tests (task names from the plugin's `knowledge/repo-profile.md`); assert XML test counts > 0 |
| 3 | iOS logic | commonTest passes on Kotlin/Native | `:shared:compileTestKotlinIosSimulatorArm64` then `:shared:iosSimulatorArm64Test`; a link-stage-only failure is A/B-checked against the pre-migration commit before scoring (androidMain-only transitive deps — knowledge base) |
| 4 | Release config | R8/minified build survives (debug hides these failures) | `:app:assembleProductionRelease` |
| 5 | Observable surface | zero-loss machine diff, base vs HEAD, of: `testTag(` literals, analytics event names/params, string-resource keys, SharedPreferences/DataStore key literals, typography token usages in touched screens | scripted greps over both refs; every loss needs a waiver line in contract.md |
| 6 | Android E2E | each contract behavior driven on emulator | Maestro flows (reuse a matching `maestro/<journey>/` if it exists, else generate from the contract) |
| 7 | iOS E2E | same behaviors on simulator | `xcodebuild build` then the mirrored Maestro flows (selectors shared via accessibilityIdentifier == testTag) |
| 8 | Parity walkthrough | per contract behavior: Android-vs-iOS evidence pair | hierarchy/text comparison; never mask computed values; masking + stateful discipline per the verifier and the contract's appendix |
| 9 | Android-unchanged | rename-only diff + caller stability + baselines intact | `git diff -M90% --name-status <base>..HEAD` all moves `R`; consumer import-line delta in `:app` = 0 (excluding moved files' own headers); baseline suite executed with assertion count ≥ pre-move |

Verdict rules: report FAIL the moment any lane fails — finish remaining lanes for a complete fix list, but never average a verdict; a BLOCKED lane (couldn't execute) also means the final verdict is not PASS — surface it as a blocker, never a silent skip. A RED counts as divergence only after the verifier's reproduce-and-drift protocol passes. When merging, a known-issue note never softens a lane FAIL. Write `qa-report.md`: lane table with verdicts + artifact paths, fix list (file:line, contract line, suggested route), final `PASS | FAIL`. When invoked by the orchestrator, FAIL items route back as migrator dispatches — never fix anything from inside QA.

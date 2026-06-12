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
| 1 | Static | style + analysis clean | `ktlintCheck detekt`; `+ :app:detektBaselines` when baseline files changed |
| 2 | Android logic | app + shared JVM tests green, and they RAN | `:app:testProductionDebugUnitTest` + `:shared` android unit tests (task names from `.kmm/project.md`); assert XML test counts > 0 |
| 3 | iOS logic | commonTest passes on Kotlin/Native | `:shared:compileTestKotlinIosSimulatorArm64` then `:shared:iosSimulatorArm64Test` |
| 4 | Release config | R8/minified build survives (debug hides these failures) | `:app:assembleProductionRelease` |
| 5 | Observable surface | zero-loss machine diff, base vs HEAD, of: `testTag(` literals, analytics event names/params, string-resource keys, SharedPreferences/DataStore key literals, typography token usages in touched screens | scripted greps over both refs; every loss needs a waiver line in contract.md |
| 6 | Android E2E | each contract behavior driven on emulator | Maestro flows (reuse a matching `maestro/<journey>/` if it exists, else generate from the contract); device-scoped (`-s`) |
| 7 | iOS E2E | same behaviors on simulator | `xcodebuild build` then the mirrored Maestro flows (selectors shared via accessibilityIdentifier == testTag) |
| 8 | Parity walkthrough | per contract behavior: Android-vs-iOS evidence pair | hierarchy/text comparison; mask only fields proven volatile by double-sampling the SAME device; never mask computed values; stateful actions per the contract's appendix |
| 9 | Android-unchanged | rename-only diff + caller stability + baselines intact | `git diff -M90% --name-status <base>..HEAD` all moves `R`; consumer import-line delta in `:app` = 0 (excluding moved files' own headers); baseline suite executed with assertion count ≥ pre-move |

Verdict rules: report FAIL the moment any lane fails — finish remaining lanes for a complete fix list, but never average a verdict. A RED needs reproduction ×2 and a drift check (scroll anchor, live tick, A/B copy) before it's reported as divergence. Known-issue notes in state are context, not verdicts. Write `qa-report.md`: lane table with verdicts + artifact paths, fix list (file:line, contract line, suggested route), final `PASS | FAIL`. When invoked by the orchestrator, FAIL items route back as migrator dispatches — never fix anything from inside QA.

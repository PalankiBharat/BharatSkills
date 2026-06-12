# Phase 2 — Research (live docs only)

Goal: every KMM-shaped unknown from scoping answered with a citation, or explicitly marked UNKNOWN. This phase is the anti-hallucination budget — spend it so phases 3-5 never guess.

1. **Collect questions.** From contract.md + scout's androidism inventory, list every construct whose KMM treatment is not already proven in this repo. Recurring clusters (each has burned a past migration): seam options for an androidism (expect/actual vs constructor injection), a dependency's iOS-klib availability, SKIE consumption shape on the Swift side, Compose-MP vs SwiftUI given what `Punch/` already does, gradle/source-set mechanics, test portability to `iosSimulatorArm64`, serializer-swap leniency semantics, datetime/locale semantics, DI-symbol portability, pagination, exception types across module boundaries, **gradle plugin multi-module constraints** for any codegen plugin the feature's types touch.
2. **Check repo precedent FIRST.** `.kmm/project.md` (especially its traps/gotchas sections) and merged `kmm/*` history often already answer it (cite as `file:line` / profile section / PR#). A precedent answer needs no web research.
3. **Hard verification protocol — never assume, probe:**
   - Library/SDK "is it KMP?" → gradle metadata, not docs: `./gradlew :shared:dependencyInsight --configuration iosSimulatorArm64RuntimeClasspath <dep>` or the klib's presence in `~/.gradle/caches` (the profile documents linkdata inspection for per-type availability).
   - Version "does it exist / is it ABI-compatible?" → Maven Central metadata + the repo's Kotlin version, before any plan step names a version. A phantom version in the plan costs a mid-execute rollback.
4. **Fan out kmm-researcher agents** — one per cluster, parallel, max 5. Each brief: the question, why it matters for this feature, what repo precedent says, required output format with ENUMERATED verdict values (free-form verdicts from parallel agents don't merge). Researchers must source every claim (context7 → kotlinlang.org/touchlab/Android dev/Apple dev → web), include version numbers and access dates, and return UNKNOWN rather than guess.
5. **Merge** into `research.md`: per question — answer, citation(s), confidence, repo-precedent cross-reference. UNKNOWNs get one of: a planned in-repo verification step, or G3 escalation if it blocks the contract.
6. **Verify-in-repo beats trust:** when a researcher's answer is cheaply checkable locally (a gradle probe, a klib inspection, a 5-line spike in a scratch source set), record the check as a plan step rather than accepting the citation alone.

Journal `phase-done`, set phase 3.

Exit: research.md complete — no question unanswered and uncited; UNKNOWNs carry a verification step or a gate.

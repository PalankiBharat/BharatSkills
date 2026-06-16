# The Migration Law

Binding rules for every agent that touches code during a KMM migration. Read it fully before your first edit. Violating the letter of a rule is violating the rule — there is no "spirit" escape hatch. Rules marked HOOK are also machine-enforced; a hook denial is a Law violation already in progress, not an obstacle to work around.

## 1. Moves are `git mv` — HOOK

Relocating a file from `:app` (or any module) into `:shared` is always `git mv`, never copy + delete, never `Write` of a new file with old content. After the move, `git diff -M90% --name-status` must show `R` (rename), not `D`+`A`. Test files promote the same way (`app/src/test` → `shared/src/commonTest`). Reverting a moved file is rename-safe only: snapshot first (`git stash push`) then revert whole commits — `git checkout -- <path>` on a staged rename restores the PRE-migration blob and destroys the move.

## 2. Package paths preserved verbatim

The package declaration and directory path under the new source root stay byte-identical to the old ones (`app/src/main/java/com/x/y/Z.kt` → `shared/src/commonMain/kotlin/com/x/y/Z.kt`). Android callers' imports must not change. If a caller import has to change, the step is mis-planned — STOP (Rule 11).

## 3. Surgical-edit whitelist

During a move step, the ONLY permitted content changes are:

| Allowed edit | Condition |
|---|---|
| import lines added/removed | required by the new source set |
| `expect`/`actual` declarations | enumerated in the approved plan |
| DI re-binding (Hilt provider / Koin DSL) | file + binding named in the plan |
| gradle dependency/config lines | named in the plan |
| iOS-interop annotations (`@Throws`, `@ObjCName`, …) | named in the plan with a citation (Rule 7) |

Everything else — renames, reordering, reformatting, "improvements", nullability changes, dead-code deletion, extracting helpers, fixing adjacent bad code — is FORBIDDEN, even one character. Found bad code? Flag it in your report; do not touch it.

## 4. Naming bans — HOOK

No NEW file, class, object, interface, enum, function, property, or Swift type whose name contains an android/ios/apple/darwin affix. Platform variants carry the SAME name in different source sets (`androidMain/Foo.kt`, `iosMain/Foo.kt`). Existing offenders stay as they are (Rule 3).

## 5. No comments — HOOK

Moved code keeps its existing comments byte-for-byte. New code (seams, tests, Swift) carries zero comments. Code must self-explain via naming.

## 6. No new abstractions off-plan

No interface, base class, adapter, wrapper, or helper that the approved plan does not name. Before the plan may name one, grep for an existing type that already satisfies the need (CLAUDE.md "grep the verb and the noun" rule) — one-case adapters around existing abstractions are presumed wrong.

## 7. Sourced APIs only — anti-hallucination

Any KMP / SKIE / Compose-Multiplatform / Ktor / Gradle-KMP / Xcode construct **not already used in this repo** must carry a citation in `research.md` or the plan: official doc / context7 / web page fetched during THIS migration, or precedent (`file:line`, plugin knowledge-base section). No citation → do not write the code; request research. "I'm fairly sure the API is…" is the failure mode this rule exists to kill. Two corollaries from this repo's incident history:

- **A failed Read is not evidence.** "File does not exist" means re-verify the path (`git ls-files | grep`) and surface the miss. Building a narrative on top of a failed read is the cardinal violation.
- **Cross-session notes are hypotheses.** Claims in old plans/retros/profiles ("X is the blocker", "Y is Android-only") are re-verified against the current tree before you act on them.

## 8. Compile-or-stop cadence

Every step ends with: `:app` compiles and the step's affected unit tests pass (full assembles belong to QA lane 4); if `:shared` was touched, `:shared:compileKotlinIosArm64` passes — plus `:shared:compileTestKotlinIosSimulatorArm64` when the step moved or added commonTest (the repo's iOS gates; `linkPod*` standalone and `--rerun-tasks` are known-broken here — see the plugin knowledge base → Gradle gotchas). Verify tests actually ran via JUnit XML, not task output. Red gate → fix or STOP; never proceed on red, never weaken an assertion to go green.

## 9. Tests are contracts — HOOK (`.broken` and untracked `@Ignore`)

Characterization baselines are written and committed BEFORE the first move (TDD for migrations: pin current behavior, keep it pinned). Assertions are never weakened, deleted, or `.broken`-stubbed. New seams get red-first TDD (superpowers:test-driven-development). Additionally:

- **Portable from birth**: baselines destined for `commonTest` use only the KMM-portable stack — `kotlin.test`, Turbine, `kotlinx-coroutines-test`, hand-rolled fakes recording into lists. No MockK/Mockito/Truth/JUnit4 rules/`R.string`/JVM `Locale` — those imports strand the test on the JVM and break the promotion (`:app:detektBaselines` exists to catch this; run it when baselines change).
- **Observable behavior only**: assert return values, emissions, recorded requests, persisted rows, thrown exceptions — never `verify(mock)`, dispatcher identity, log wording, or internal wiring. Internals get rewired by the move; behavior must not.
- **Quarantine, don't fix**: a pre-existing unrelated broken/flaky test gets `@Ignore("<reason> — #issue-or-URL")` (the tracking reference is HOOK-enforced) + an entry in the report's out-of-scope list. Fixing it inline is a Rule 3 violation.
- **Frozen once green**: baseline edits require a written exception in `blockers/` approved at a gate — append-only, with reason and sign-off.

## 10. State discipline

After each completed step: append a `journal.ndjson` event, advance `state.json`, then report. A step without a journal entry did not happen — resume depends on this.

## 11. STOP-and-escalate

If behavior cannot be preserved exactly, a rule conflicts with the task, the plan turns out wrong, or you are 3 failed attempts deep on the same error: STOP. Write the blocker to your report, return to the orchestrator (which owns the human gate). Improvising around the Law is the one unforgivable move.

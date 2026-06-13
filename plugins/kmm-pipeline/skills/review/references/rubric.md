# KMM Migration Review Rubric

Ordered by what review history in this repo actually flags (most → least). Every check names its evidence; a check without evidence is not performed, it's skipped — say so.

## Lens: parity-integrity

1. **Behavior loss (the #1 source of shipped regressions).** Every contract behavior maps to a surviving test or QA artifact. Machine-diff base-vs-HEAD inventories: `testTag(` literals, analytics event names/params, string-resource keys, SharedPreferences/DataStore key literals, typography token usages in touched screens. Any loss without a contract waiver = blocker. Rewrite-style screens (new file instead of `R` rename) get line-level scrutiny: experiment/cohort logic, one-shot nav effects, `BackHandler`, `imePadding`, biometric/self-heal paths (learnings M1).
2. **Test integrity.** No new `.broken` files, no `@Ignore` without tracking reference, no deleted/weakened assertions (diff each moved test's assertion set), portable stack in commonTest (no MockK/Mockito/Robolectric/JUnit4 rules/R.string), persistence tested against real in-memory backends rather than mocks, `runTest` not `runBlocking`, backtick test names free of `,()./\[]<>` in commonTest (Kotlin/Native chokes), baselines demonstrably executed (XML count), clock-controllable (injected Clock), and mutation-proofed (evidence that a deliberate mutation went red — state/journal records it).
3. **Persistence & wire format.** `app/objectbox-models/default.json`: any property `type` change under an unchanged `uid` = blocker (wiped every user's session once — learnings M2). Moved `@Serializable` types: round-trip test against a frozen pre-move fixture (real payloads); leniency semantics preserved on serializer swaps (missing key / unknown enum / explicit null). Entity/wire boundary types unchanged — domain converts at the edge.
4. **Error handling.** New `catch (e: Exception|Throwable)` in suspend/load paths rethrows `CancellationException` first. No throwing call silently replaced by `?: default`/empty catch without a non-fatal log. `viewModelScope.launch` bodies in commonMain crash-guarded per repo precedent (uncaught K/N throw is fatal on iOS).
5. **Clock/timezone semantics** on date-time swaps: injected `Clock`, explicit `TimeZone` arguments, no hardcoded `Asia/Kolkata` replacing system zone.
6. **Swift layer**: view binding only — any if/switch/ternary/computed-property in the touched `.swift` view files that mirrors logic in the Android implementation = parity logic duplicated = blocker.
7. **Sourced APIs**: constructs new to this repo cite research.md/plan.md (Law 7). Spot-check 3 newest APIs in the diff.

## Lens: law-compliance

8. **Move mechanics (Law Rules 1-2).** `git diff -M90% --name-status <range>`: every relocation shows `R` ≥ 90; package paths verbatim; consumer import delta in `:app` = 0 (excluding moved files themselves). D+A pairs = blocker (history severed, content drift unbounded).
9. **Surgical whitelist.** Classify every hunk in every `R` file against Law Rule 3 + the plan's enumerated edits. Unclassifiable hunk = blocker. Whitespace-only or reformat hunks = fix (diff noise).
10. **Seam economy (Law Rule 6).** Every new `expect/actual` justified by a concrete per-platform runtime difference stated in plan/commit; both actuals have call sites. A seam expressible as a constant or constructor param = fix (four redesigns — learnings M7).
11. **Naming & comments (Law Rules 4-5).** No new android/ios/apple/darwin-affixed names; zero added comment lines (the guard blocks these live; their presence means the guard was bypassed — blocker); no migration-narrative comments ("moved from", "was previously", "KMM").
12. **Dependency hygiene (GUARD/M10 — no Law rule).** No added `alpha|beta|rc|SNAPSHOT|-local` versions; coordinates via the version catalog only; `api` vs `implementation` exposure deliberate; no version skew between `:shared` androidMain additions and `:app`'s resolved versions (`dependencyInsight` both sides when a dep was added).
13. **Scope & hygiene (Law Rules 3, 10).** Changed files ⊆ plan inventory; no session artifacts (`.kmm/migrations/`, `*.broken`, scratch/review docs) in the diff; no deleted `Log.|Timber.|Napier.` lines outside the plan; no foreign-branch leakage; commit messages follow `[Kmm - <Feature>] - If applied, …`.
14. **DI placement (knowledge-base DI canon).** No Hilt symbols/qualifiers in commonMain (repo canon); no new Context-holder singletons; bindings relocated per plan, no manual instantiation.
15. **Gradle/iOS gates ran (Law Rule 8).** Evidence in state (journal/qa-report) that per-step gates included `:shared:compileKotlinIosArm64` and the phase-4 exit ran the cold compile + workspace build. Absent evidence = fix (process), failed gates = blocker.

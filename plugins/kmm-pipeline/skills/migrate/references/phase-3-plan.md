# Phase 3 — Plan

Goal: an approved `plan.md` that a fresh worker can execute one step at a time without inventing anything.

1. **Invoke superpowers:writing-plans.** Inputs: contract.md, scout's boundary map, research.md, the Law, repo profile. The plan document lives at `.kmm/migrations/<slug>/plan.md`.
2. **Plan header** (before the steps): Locked decisions (substitutions settled here, never re-derived mid-execute) · Risk register (per-file) · Rejected improvements (the scope boundary, for reviewers). For >10 moved files add a coverage registry (file | step | status | SHA) that only the orchestrator flips.
3. **Step shape** (every step, no exceptions):

```markdown
## S<n>: <intent in domain words>
- moves: app/src/.../X.kt → shared/src/commonMain/kotlin/.../X.kt   (git mv, package verbatim)
- edits (Law Rule 3 whitelist only): <imports | expect/actual NAME | DI binding FILE | gradle LINE | annotation> — each with citation [research.md §n | file:line | profile §]
- seams: <each expect/actual NAME → the CONCRETE per-platform runtime difference it expresses · why a constant or constructor parameter cannot>   (learnings M7: skipping this test cost four seam redesigns)
- tests: <baselines that must stay green> · <tests promoted via git mv> · <new red-first tests>
- gates: <compile/test commands for THIS step, from the profile's verification section>
- independent: false   # true only if it shares no files with any other true/pending step
- rollback: <revert this step's commits, or git stash push snapshot — never `git checkout --` on a git-mv'd file>
```

4. **Mandatory step S0 — baselines.** Before any move: compile the test source sets and quarantine pre-existing breaks first (provable "pre-existing vs introduced"); then characterization tests pinning the contract's observable behaviors at the current Android implementation (superpowers:test-driven-development discipline — watch them pass, mutation-spot-check ≥3 representative classes: mutate → red → restore → green, so the baselines provably catch breakage; commit). These are the proof Android survives unchanged.
5. **Ordering:** dependency-leaf files first; a store, its hand-constructing consumers, and its DI provider travel in ONE step (independent store-chains = independent steps); every step leaves `:app` compiling and green — there is no "broken until step 7" window. Seams (expect/actual) get their own steps with their own red-first tests.
6. **Plan self-review** before the gate: every contract behavior maps to a step (completeness proof); any step whose edits exceed the whitelist? any uncited construct (Rule 7)? any step too big to verify in one compile-test cycle? any file moved twice or named in contradictory steps? **Topological check**: for every step, all in-scope dependencies of its files appear in earlier steps — an ordering contradiction found at execution costs a mid-batch gate. Fix, then gate.
7. **Single-writer discipline**: the orchestrator is the only writer of plan.md and state.json (workers write only journal appends and their own blocker files). Edits to plan.md use plain-ASCII anchor strings — unicode anchors have broken Edit-matching here before.
8. **G2 — plan approval.** Present: step list summary, total moves count, seams to be created, risks/UNKNOWNs and their verification steps. AskUserQuestion: approve / edit / drop steps. Record decision; journal; phase 4.

Exit: approved plan.md; every step sourced, gated, and rollback-able.

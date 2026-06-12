# Phase 3 — Plan

Goal: an approved `plan.md` that a fresh worker can execute one step at a time without inventing anything.

1. **Invoke superpowers:writing-plans.** Inputs: contract.md, scout's boundary map, research.md, the Law, repo profile. The plan document lives at `.kmm/migrations/<slug>/plan.md`.
2. **Step shape** (every step, no exceptions):

```markdown
## S<n>: <intent in domain words>
- moves: app/src/.../X.kt → shared/src/commonMain/kotlin/.../X.kt   (git mv, package verbatim)
- edits (Law Rule 3 whitelist only): <imports | expect/actual NAME | DI binding FILE | gradle LINE | annotation> — each with citation [research.md §n | file:line | profile §]
- seams: every expect/actual here states the CONCRETE per-platform runtime difference it expresses, and why a constant or constructor parameter cannot (this repo once burned four redesigns on a seam whose right answer was "two constants")
- tests: <baselines that must stay green> · <tests promoted via git mv> · <new red-first tests>
- gates: <compile/test commands for THIS step, from the profile's verification section>
- independent: false   # true only if it shares no files with any other true/pending step
- rollback: <single git command or "revert commits of this step">
```

3. **Mandatory step S0 — baselines.** Before any move: characterization tests pinning the contract's observable behaviors at the current Android implementation (superpowers:test-driven-development discipline — watch them pass, commit them). These are the proof Android survives unchanged.
4. **Ordering:** dependency-leaf files first; every step leaves `:app` compiling and green — there is no "broken until step 7" window. Seams (expect/actual) get their own steps with their own red-first tests.
5. **Plan self-review** before the gate: any step whose edits exceed the whitelist? any uncited construct (Rule 7)? any step too big to verify in one compile-test cycle? any file moved twice or named in contradictory steps? **Topological check**: for every step, all in-scope dependencies of its files appear in earlier steps — an ordering contradiction found at execution costs a mid-batch gate. Fix, then gate.
6. **Single-writer discipline**: the orchestrator is the only writer of plan.md and state.json (workers write only journal appends and their own blocker files). Edits to plan.md use plain-ASCII anchor strings — unicode anchors have broken Edit-matching here before.
7. **G2 — plan approval.** Present: step list summary, total moves count, seams to be created, risks/UNKNOWNs and their verification steps. AskUserQuestion: approve / edit / drop steps. Record decision; journal; phase 4.

Exit: approved plan.md; every step sourced, gated, and rollback-able.

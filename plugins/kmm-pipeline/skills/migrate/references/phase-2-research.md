# Phase 2 — Research (live docs only)

Goal: every KMM-shaped unknown from scoping answered with a citation, or explicitly marked UNKNOWN. This phase is the anti-hallucination budget — spend it so phases 3-5 never guess.

1. **Collect questions.** From contract.md + scout's androidism inventory, list every construct whose KMM treatment is not already proven in this repo. Pre-load the recurring clusters from `knowledge/learnings.md` → "Recurring research topics" (each has burned a past migration); add any feature-specific unknown the inventory surfaces.
2. **Check precedent FIRST.** The plugin knowledge base (`knowledge/learnings.md` incidents + `knowledge/repo-profile.md`) and merged `kmm/*` history often already answer it (cite as `file:line` / knowledge section / PR#). A precedent answer needs no web research.
3. **Two metadata gates — never assume, probe** (probe commands live in the kmm-researcher agent + the knowledge base; don't restate):
   - "Is it KMP?" resolves from gradle/klib metadata, never docs.
   - "Does this version exist / is it ABI-compatible?" resolves from Maven Central + the repo's Kotlin version BEFORE any plan step names a version — a phantom version costs a mid-execute rollback.
4. **Fan out kmm-researcher agents** — one per cluster, parallel, max 5. Each brief: the question, why it matters for this feature, what precedent says, required output format with ENUMERATED verdict values (free-form verdicts from parallel agents don't merge).
5. **Merge** into `research.md`: per question — answer, citation(s), confidence, precedent cross-reference. Record a planned in-repo verification step for every UNKNOWN and for any cited answer that's cheaply checkable locally (gradle probe / klib inspection / 5-line scratch-source spike); an UNKNOWN that blocks the contract goes to G3 instead.

Journal `phase-done`, set phase 3.

Exit: research.md complete — no question unanswered and uncited; UNKNOWNs carry a verification step or a gate.

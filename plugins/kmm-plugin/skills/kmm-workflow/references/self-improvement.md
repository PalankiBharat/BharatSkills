# Migration Retrospective — Self-Improvement Protocol

The retrospective runs before `/clear` to surface learnings from the current session. It does **not** auto-apply anything — the user writes approved findings into `findings.md` (for the current gameplan) or opens a manual PR against the skill repo.

## When to trigger

Run **automatically** at these points — do NOT wait for the user to ask:
- After Phase 1 (PLAN) is approved — capture planning-phase learnings before /clear
- After Phase 3 (SHARED CODE MIGRATION) completes — capture execution-phase learnings before /clear
- After all phases complete
- On any REQUIRES_APPROVAL that the user had to manually resolve

The retrospective MUST complete BEFORE the orchestrator instructs `/clear`. Context is erased on clear — if the retrospective hasn't run, all session learnings are permanently lost.

## What to scan for — Three signal types

**Signal 1: Code/library learnings** (Categories A, B, D, E)
- findings.md, build errors, test failures, library discoveries
- Dependency swaps that surprised, APIs that didn't work on Native, build config gotchas

**Signal 2: Steering corrections** (Category F)
- User negation ("no", "don't", "wrong"), redirection ("instead", "use X"), frustration signals ("I already said", "why"), option overrides (user picked a non-recommended REQUIRES_APPROVAL choice)
- Extract the general behavioral pattern the orchestrator got wrong

**Signal 3: System observations** (Category G)
- Agent re-dispatch events (BLOCKED → re-dispatch), long user gaps (waiting/spinning), high tool-call counts per task, repeated file reads, orchestrator self-observations about timing
- Derive the systemic fix, not the observation

Cross-reference ALL findings against existing skill files to avoid duplicates.

## Categories

### A — Decision Framework Gaps
User had to guide a dependency/architecture choice the skill should have recommended proactively. → `references/dependency-decision-framework.md` row.

### B — Missing Guardrails
Correction to a code pattern or convention that applies to ALL future migrations. → new rule in `references/rules-and-guardrails.md` §1.

### C — Process Improvements
Step skipped, run in wrong order, quality check missed, user having to ask for something that should be automatic. Include workflow observations (batching, dispatch order, question sequencing). → updated step in SKILL.md or `references/planning-and-execution.md`.

### D — Platform Gotchas
iOS/Android-specific APIs that don't exist in commonMain, runtime behavior differences, build config surprises. → new entry in `references/platform-api-gotchas.md`.

### E — Library-Specific Knowledge
New info about KMM library compatibility or version-specific features. → summary row in `references/dependency-decision-framework.md`; full before/after in `references/dependency-replacements.md`.

### F — Steering Corrections
Instances where the user redirected orchestrator behavior. Different from B — B is about code patterns, F is about orchestrator behavior (dispatch order, mode routing, question sequencing). → new rule in `references/rules-and-guardrails.md` or `references/agent-protocol.md`.

### G — System & Performance
Context bloat, agent spinning, time sinks, model routing mismatches, parallelism failures, token waste, team coordination gaps. → updated dispatch pattern in SKILL.md / `references/agent-protocol.md`.

## Execution — Observe → Discuss

### Phase 1 — OBSERVE (autonomous)

1. Scan conversation + `findings.md` + orchestrator self-observations across the three signal types
2. Score each finding against the Skill-Worthiness Gate (below)
3. Group by risk tier:
   - **High-risk:** C, G (architectural / execution-pattern changes)
   - **Medium-risk:** F (orchestrator behavior)
   - **Low-risk:** A, B, D, E (concrete code/library patterns)
4. Drop duplicates against existing skill files

### Phase 2 — DISCUSS (interactive)

Present findings by risk tier. **The retro earns its optimizations through user discussion, not autonomous application.**

Each finding is classified into one of two destinations:
- **KMM-universal** → skill reference files (user opens a PR against the skill repo if they want it merged)
- **Project-specific / ephemeral** → user writes into the current gameplan's `findings.md` directly

**For each high-risk finding (C, G):**
- What was observed (specific conversation moments, timing data, token counts)
- Why it matters (speed impact, quality impact, cost impact)
- Proposed change (which skill file, which section, proposed rewording)
- Trade-offs (what could go wrong, what this doesn't solve)
- Ask: approve / modify / skip?

**For each medium-risk finding (F):**
- What the user corrected and how many times
- The general pattern extracted (not project-specific)
- Proposed rule change (which file, exact wording)
- Ask: approve / modify / skip?

**For low-risk findings (A, B, D, E):**
- Batch summary
- Ask: approve all / review individually / skip?

### After discussion

The orchestrator writes APPROVED findings into a summary block at the end of the session (shown to the user) with destinations:

```
Retrospective — N findings, M approved:

| # | Cat | Finding | Risk | Destination | Next step |
|---|-----|---------|------|-------------|-----------|
| 1 | G | Phase 1 research serial bottleneck | High | planning-and-execution.md | User opens PR in claude-code-skills repo |
| 2 | F | Skipped project grep before websearch | Med | rules-and-guardrails.md | User opens PR in claude-code-skills repo |
| 3 | D | Dispatchers.IO needs explicit import | Low | platform-api-gotchas.md | User opens PR in claude-code-skills repo |
| 4 | E | X library has KMM support now | Low | findings.md (this gameplan) | Already written |
```

The user decides whether to raise PRs. The skill does not auto-PR.

## Skill-Worthiness Gate

Before proposing any learning for the skill (as opposed to findings.md), score it:

| Criterion | Points |
|-----------|--------|
| Specific to KMM migration (not generic programming) | +30 |
| Non-obvious (would surprise a senior KMM developer) | +25 |
| Hard-won (required debugging, caused a real failure) | +25 |
| Not already covered by existing skill rules | +20 |
| Improves execution speed/cost (saves tokens, wall-clock time, or model tier) | +20 |
| User corrected the same pattern more than once in the session | +15 |
| Generic programming advice ("use error handling") | -30 |
| Already in platform-api-gotchas.md or similar reference | -20 |

**Threshold: 70 points.** Below 70 → keep in `findings.md` only, do not propose for skill promotion.

## Lean Output Format

Findings MUST use this structured format (not verbose prose):

```
Finding: {
  category: A|B|C|D|E|F|G,
  target_file: <which skill file should change, or "findings.md">,
  existing_rule: <quote the existing rule to update, or "none" if new>,
  proposed_change: <1-line description of what to change>,
  rationale: <1-line why this matters>
}
```

Group findings by target_file in the summary block.

## Generalization rule (mandatory for skill-bound findings)

Every learning proposed for a skill reference file MUST be generalized before capturing. The skill's reference files are project-agnostic.

**Before proposing, strip:**
- Project-specific class/interface names → use generic examples (`MyUseCase`, not `GetEstimatedMarginUseCase`)
- Branch names, repo names, artifact names → describe the pattern
- API endpoints, server names, product names → describe the category
- Gameplan-specific context → extract the reusable principle

**Test:** Would a developer on a completely different Android→KMM project find this as-is useful? If they'd need to mentally replace project names, it's not generalized.

Project-specific findings go in `findings.md` for the current gameplan — never in skill reference files.

## What NOT to capture

- Project-specific decisions (base URLs, artifact names, branch names, class names)
- One-off bugs that were fixed during the session
- User preferences already in CLAUDE.md (like "no type casting")
- Anything already in the skill's reference files
- Phase-specific or gameplan-specific details that only apply to the current session

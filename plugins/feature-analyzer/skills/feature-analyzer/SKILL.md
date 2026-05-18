---
name: feature-analyzer
description: Comprehensive user story and feature analysis skill for Android development. Use whenever the user shares a feature spec, user story, JIRA ticket, or any feature description and wants thorough analysis before development. Triggers on phrases like "analyze this feature", "review this story", "what am I missing", "pre-dev analysis", "feature analysis", "story analysis", "break down this feature", "what should I consider", or any request to understand a feature's full impact before coding. Also use when the user asks about domain implications, tech impact, QA coverage, or cascading effects of a feature change. Default domain context is trading/fintech (NSE/BSE, broker APIs, exchange regulations) but generalizes to any Android app domain.
---

# Feature Analyzer

A two-mode pre-development analysis skill.

- **Mode 1 — Story interrogation (default)**: Audits the existing code, filters cross-platform noise, then produces ONLY questions tagged by who should answer them. Output is an HTML doc the developer shares with PM / Design / Backend.
- **Mode 2 — Full analysis**: After answers are collected, generates the full Domain + Tech + QA checklist into Notion.

Never mix the two. Mode 1 is the default; Mode 2 only runs when the user explicitly says so.

## Two-mode trigger map

| User said… | Mode |
|---|---|
| "analyze this", "review this story", "what am I missing", "interrogate this spec" | 1 |
| "run full analysis", "generate checklist", "I have the answers, now analyze" | 2 |
| User pastes a story without further instruction | 1 |

---

## Mode 1 — Story interrogation

Mode 1 is implemented as a **team of specialist agents coordinated by a team lead** (this skill prompt). The lead never asks questions directly — it runs the team through a fixed wave plan, audits the merged output via a critic, and emits the final HTML doc.

### Lead state machine

```
INIT → PREFLIGHT → SCOPE-FILTER → WAVE1 → CRITIC-W1 → GATE-A → WAVE2 → CRITIC-W2
     → WAVE3 → MERGE → CRITIC-FINAL → CONFLICT-RESOLVE (if needed) → GATE-B → DONE
```

For the full FSM, gates, retries, and budget rules read `references/team-lead-protocol.md`.

### What happens, in order

0. **Capture source story (verbatim)** — the very first action in Mode 1 is to persist the raw story text exactly as the reviewer submitted it. It is stored on `lead.session.source_story` and threaded through to the renderer (rendered in the Original Story tab) and to the replay log (`00-source-story.md`). The lead is forbidden from rewriting, summarising, or truncating the source story anywhere downstream — every downstream consumer either uses the captured text or references its session key.
1. **Pre-flight** — locate sibling SDK checkouts, validate Figma URLs, confirm story has minimum content. Fail closed if any check breaks. Rules in `references/team-lead-protocol.md` (G5).
2. **Scope filter** — classify each story section as `android | ios | web | desktop | backend | shared`. Strip out-of-platform; keep `backend` only when the kept sections imply a new server-side ask. Rules in `references/scope-classifier.md`.
3. **Wave 1 — discovery** (parallel):
   - `flow-tracer` walks UI → ViewModel → Repo → SDK boundary with `file:line` cites and confidence, AND emits the story-vs-code delta inline (the old `gap-analyzer` is folded in). Reads sibling-SDK *source*, never JARs or examples. Respects `project_memory` (e.g. "Punch does not support AMO" → no AMO facts). Full rules in `references/existing-flow-trace.md`.
   - `design-reviewer` (always spawned; runs in degraded mode if no Figma URLs) fetches every Figma URL captured by story-clarifier, walks the prototype graph or section neighbours (depth ≤8), captures screenshots at `scale: 2`, extracts design tokens + Code Connect mappings, and produces a screen catalog + flow graph + design questions with option pills. Full rules in `references/figma-walk.md`.
4. **Critic — Wave 1** — validates schemas + `file:line` evidence + project-memory contradiction. Failed claims dropped.
5. **Gate A (default ON)** — show flow doc + delta + screen catalog. Misreads corrected here, before Wave 2 spends compute on them.
6. **Wave 2 — questions** — one `questioner` specialist emits all non-design pillar questions (domain / tech / qa) in a single pass using flow-tracer facts + delta + scope-report + `project_memory`. Every question must pass the doer-decides rubric ("if the question can be resolved unilaterally in a PR with a code review, it's not a clarification question") — implementation choices like module placement, Hilt scoping, or Compose state hoisting are out. Android-tagged questions appear only when the answer is a genuinely Android-shaped stakeholder decision (LD-flag scope, deep-link support, push-notification surface, rollback ownership, Android-observable backend contract). The previous three-questioner fan-out was merged after #173 because it produced duplicate questions critic had to merge afterward — one specialist with a unified catalog avoids that round-trip.
7. **Merge** — lead drops any question auto-answered by `flow-tracer` (high-confidence facts) or by `story-clarifier.strikethrough_branches[]` (settled decisions), de-dups via the critic, applies the priority ordering.
8. **Critic — final** — schema + evidence + duplicate + conflict + count + scope-leak + backend-internals-leak + strikethrough-revival + doer-decides-at-code-time + evidence-against-memory checks. Rules in `references/critic-rubric.md`.
9. **Conflict resolve** (only if critic surfaced contradictions) — tie-break prompts to the conflicting specialists; survivors must cite. Unresolved conflicts go to the user verbatim.
10. **Gate B (default ON)** — present pre-final HTML. Developer can drop / merge / re-prompt.
11. **Done** — emit HTML doc, replay log, token report.

Bypass gates with `--no-gates` for autonomous runs. Budget cap (default 300k tokens) applies; at 80% the lead stops spawning and finalises with `partial: true`.

### Output

- **Primary**: HTML file at `docs/feature-analysis/<feature-slug>-analysis.html`. Structure and styling in `references/html-output.md`. The HTML **always** carries the raw original story in a pinned tab next to the analysis — captured first thing in Pre-flight, never modified, never summarised. See `references/html-output.md` § "Tab strip + Original Story panel".
- **Secondary**: Replay log at `.feature-analyzer/<feature-slug>/<session-id>/`. Layout in `references/replay-log-format.md`. The raw story is persisted as `00-source-story.md` alongside the preflight log.
- **Fallback (`--format md`)**: markdown output for terminal-only sessions. Same priority buckets, same option-pill format, no styling. The raw story is prepended verbatim under a `## Original story` heading.

### Question card requirements

Every question, regardless of pillar, must include:

- 3–4 concrete options. Generic best-practice doesn't count as an option; each option must be a real choice this team could make.
- Exactly one option marked `recommended: true` with a one-line reason. Reason should cite a `flow-tracer` fact ID if available (raises confidence to `high`).
- An "Other / override" text input for stakeholder dissent.
- `reason_not_derivable` populated — the explicit reason this question can't be answered from code or Figma.
- Stable ID (`<pillar>-<slug>-<hash>`) rendered as a small grey tag for traceability.

Open-text-only questions are forbidden. Every question must ship with options. See `references/specialist-roster.md` for the full schema and `references/determinism-rules.md` for the ID rules.

**Critical — qid pillar MUST be `design | tech | qa | domain`.** Role tags (PM, Backend, Compliance, DevOps, etc.) are for stakeholders; the qid's pillar prefix is for the critic's count budget. Map Backend/DevOps → `tech`, PM/Compliance → `domain`. Full table in `references/specialist-roster.md` (Role → pillar map).

### Priority guide

- 🔴 **Blocker** — answer changes core architecture, data model, or API contract. Cannot start coding.
- 🟡 **Clarification** — affects specific flows or edge cases. Can start core work; need before feature complete.
- 🟢 **Nice-to-have** — affects polish, future scope, or unlikely edge cases. Can ship V1 without.

### Role tag guide

- **PM / Product Owner** — business rules, scope, user behavior, feature flags, rollout, priority.
- **Backend / API** — API contracts, server behavior, data availability, infra.
- **Design** — UI/UX specs, components, interactions, accessibility, visual states.
- **Compliance / Legal** — regulatory, risk disclosure, exchange rules, privacy.
- **QA** — test environment, test data, automation feasibility.
- **DevOps / Infra** — deployment, feature flags, monitoring, performance.

### Adversarial pass (opt-in)

For high-stakes features — order paths, payment, KYC, regulated work — enable `--adversarial`. A `red-team` specialist runs after the critic and tries to break the output: fake auto-answers, wrong-for-this-codebase recommendations, misleading cites, regulatory blind spots. Rules in `references/red-team-rubric.md`.

The skill auto-prompts to enable when the story matches keywords: *order, trade, payment, settle, KYC, AML, SEBI, RBI, PCI, refund, dispute, withdrawal*.

---

## Mode 2 — Full analysis

Only run AFTER the user has provided answers to Mode 1 questions, or explicitly says to proceed with assumptions.

Mode 2 is single-agent; the team-lead pattern is reserved for Mode 1 where the upfront question surface is the deliverable. In Mode 2, the deliverable is a long-form checklist where coherence matters more than parallelism.

Execute these phases in order. Read the referenced file for each phase BEFORE generating output.

### Phase 1 — Story clarification

Read `references/story-clarifier.md`. Incorporate Mode 1 answers. List remaining assumptions.

### Phase 2 — Domain analysis

Read `references/domain/orchestrator.md` and the micro-skills it coordinates:
- `references/domain/approval-checker.md`
- `references/domain/domain-questions.md`
- `references/domain/domain-test-cases.md`

### Phase 3 — Tech analysis

Read `references/tech/orchestrator.md` coordinating:
- `references/tech/code-context.md`
- `references/tech/impact-analyzer.md`
- `references/tech/tech-test-cases.md`
- `references/tech/edge-cases.md`
- `references/tech/tech-stack.md`

### Phase 4 — QA analysis

Read `references/qa/orchestrator.md` coordinating:
- `references/qa/user-test-cases.md`
- `references/qa/feature-questions.md`
- `references/qa/ux-edge-cases.md`

### Phase 5 — Cascading impact

Read `references/impact-cascade.md`. For each feature flagged as impacted, re-run Domain + Tech + QA scoped to the delta. Identify regression risk.

### Phase 6 — Output to Notion

Read `references/notion-output.md`. Auto-create the Notion page using the structured checklist layout.

---

## Reference index

Mode 1 (team-lead):
- `references/team-lead-protocol.md` — FSM, waves, gates, retries, budget
- `references/figma-walk.md` — Figma URL detection, frame traversal, screen catalog, design-token extraction
- `references/specialist-roster.md` — every specialist's contract + question schema
- `references/cross-agent-broker.md` — `needs_from` schema, cycle detection
- `references/critic-rubric.md` — independent audit checks
- `references/red-team-rubric.md` — adversarial pass
- `references/existing-flow-trace.md` — Phase 0.5 codebase + SDK walk
- `references/scope-classifier.md` — platform-scope filter
- `references/html-output.md` — HTML doc template
- `references/determinism-rules.md` — stable IDs, ordering, seeding
- `references/cache-layer.md` — flow-tracer cache
- `references/replay-log-format.md` — replay log layout

Mode 2 (full analysis):
- `references/story-clarifier.md` — story parse + clarifying questions
- `references/impact-cascade.md` — cascading impact analysis
- `references/notion-output.md` — Notion page structure
- `references/domain/`, `references/tech/`, `references/qa/` — micro-skill orchestrators

---

## Iron law

**No question without PREFLIGHT first.**

PREFLIGHT (project memory load, sibling-SDK locate, Figma URL parse, repo identification) is **non-waivable**. The point of PREFLIGHT is to refuse to answer with stale or false assumptions — skipping it means the doc you produce is wrong in ways the developer can't see. Wrong doc burns more stakeholder time than the 30 seconds PREFLIGHT cost.

**Violating the letter of these rules is violating the spirit of these rules.** A user asking for "just 5 quick questions" or "skip the flow trace" or "plain text is fine, no time" is asking for a doc that looks like the skill but isn't. The skill refuses.

The legitimate fast path: pass `--format md`. That gives the markdown layout (priority buckets + option pills + scope report), still runs PREFLIGHT, still runs flow-tracer in degraded mode if repo is unreachable. Time saved: rendering, not safety.

## Red flags — STOP and re-run PREFLIGHT

If any of these thoughts cross your mind, you are about to violate the skill. Stop, run PREFLIGHT, then continue.

- "User said no time, I'll skip PREFLIGHT just this once."
- "User wants markdown, so I'll skip flow-tracer too."
- "User asked for 5 questions, I'll drop the QA pillar."
- "I'll just emit open-text questions, options are too much work."
- "I can infer the file:line from the story, no need to grep."
- "Project memory file is missing, I'll proceed as if it were empty without flagging it."
- "Story self-declares greenfield, so I'll skip the scope-report block too."
- "The user said the strikethrough is wrong, I'll surface it anyway as an option."
- "Backend section was promoted, so I'll generate questions about backend internals."
- "I'll mark every fact `confidence: high` since flow-tracer ran in degraded mode."

All of these mean: STOP. Run PREFLIGHT. Run flow-tracer (degraded mode is fine, fabricated cites are not). Apply the rules. Then continue.

## Common rationalizations

| Rationalization | Reality |
|---|---|
| "User said skip PREFLIGHT" | PREFLIGHT is non-waivable. Disclose-and-proceed is still a violation. |
| "Plain text is what they want, markdown is fine" | `--format md` is the opt-in; markdown without that flag is still HTML by default. |
| "5 questions is the cap" | Caps are per-pillar (design ≤15, tech ≤15, qa ≤10, domain ≤10), not user-imposed. Filtering by role is fine; suppressing pillars is not. |
| "I'll lower the confidence to medium since I skipped flow-tracer" | Lowering confidence doesn't recover the missing evidence. Run flow-tracer in degraded mode and stamp every claim. |
| "The story is small, PREFLIGHT is overkill" | Small stories hide assumptions the same way large ones do. PREFLIGHT is cheap. |
| "I'll add a caveat block instead" | Caveats document failure; they don't fix it. The developer reads the questions, not the caveats. |
| "Two-stage tests passed, the rule is followed in spirit" | Spirit-vs-letter rationalizations are the loophole this section closes. |

## Key principles

1. **Code reads first, questions second** — never ask a question whose answer is in the code we already own. Phase 0.5 enforces this; the auto-answer rule in `existing-flow-trace.md` drops resolved questions before they reach the developer.
2. **Source not artefacts** — sibling SDKs are read from source repos only. JARs, decompiled bytecode, `examples/`, `demo/`, `sample/` are forbidden. Hallucination risk is the reason.
3. **Options, not prose** — every question ships with 3-4 option pills and one Recommended. Open-text questions get skipped by busy stakeholders.
4. **Filter first, ask second** — scope-classifier strips out-of-platform sections before the questioners ever see them. No "ignore desktop pls" round-trips.
5. **HTML is the share format** — markdown in chat is unshareable. HTML opens in a browser, copies cleanly into Slack/Notion, and renders the radio pills inline.
6. **Critic is independent** — the merge cannot self-approve. Every claim must survive an audit before the doc reaches the user.
7. **Determinism over variety** — same story + same code → same question set. Variety in pre-dev questions is not a feature; clarity is.
8. **Fail closed on missing inputs** — Pre-flight aborts with a single message rather than producing a partial doc that looks complete.

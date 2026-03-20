---
name: feature-analyzer
description: Comprehensive user story and feature analysis skill for Android development. Use whenever the user shares a feature spec, user story, JIRA ticket, or any feature description and wants thorough analysis before development. Triggers on phrases like "analyze this feature", "review this story", "what am I missing", "pre-dev analysis", "feature analysis", "story analysis", "break down this feature", "what should I consider", or any request to understand a feature's full impact before coding. Also use when the user asks about domain implications, tech impact, QA coverage, or cascading effects of a feature change. Default domain context is trading/fintech (NSE/BSE, broker APIs, exchange regulations) but generalizes to any Android app domain.
---

# Feature Analyzer

A two-phase pre-development analysis skill. Phase 1 interrogates the story and produces ONLY questions tagged by who should answer them. Phase 2 (separate invocation, after answers are collected) produces the full analysis checklist.

## Two-phase workflow

This skill operates in TWO distinct modes. Never mix them.

### Mode 1: Story interrogation (default)
**Trigger**: User shares a story/feature spec, says "analyze this", "review this story", "what am I missing", etc.
**Output**: ONLY questions, tagged by role. No analysis, no test cases, no code context. Just questions.
**Purpose**: Give the user a list they can take to stakeholders and get answers BEFORE development analysis begins.

### Mode 2: Full analysis
**Trigger**: User says "run full analysis", "generate checklist", "I have the answers, now analyze", or provides answers to the Phase 1 questions.
**Output**: Complete Domain + Tech + QA analysis with cascading impact. Output to Notion as checklists.
**Purpose**: After all questions are answered, produce the exhaustive pre-development checklist.

---

## Mode 1: Story interrogation

Read these reference files and extract ONLY questions from each:
- `references/story-clarifier.md` — Ambiguities, assumptions, missing ACs
- `references/domain/orchestrator.md` → all domain micro-skills — Domain/business/regulatory questions
- `references/tech/orchestrator.md` → all tech micro-skills — Technical clarification questions
- `references/qa/orchestrator.md` → all QA micro-skills — QA perspective questions

### How to generate questions

For each micro-skill, think through its checklist categories and generate questions WHERE THE ANSWER IS NOT OBVIOUS FROM THE STORY. Do NOT generate questions that the story already answers clearly.

Each question must:
1. Be specific to THIS story (not generic boilerplate)
2. State WHY the answer matters (what decision depends on it)
3. Be tagged with WHO should answer it

### Output format for Mode 1

```
# 📋 Story Interrogation: [Feature Name]
📝 [One-line summary of the feature]
📅 [Date]

---

## 🔴 Blockers (must answer before ANY development starts)
Questions whose answers fundamentally change the implementation.

### For PM / Product Owner
- [ ] [Question] — **Impact**: [What changes based on the answer]

### For Backend / API Team
- [ ] [Question] — **Impact**: [What changes based on the answer]

### For Design Team
- [ ] [Question] — **Impact**: [What changes based on the answer]

### For Compliance / Legal
- [ ] [Question] — **Impact**: [What changes based on the answer]

---

## 🟡 Clarifications (should answer before development, can unblock partially)
Questions that affect scope or edge cases but don't block the core implementation.

### For PM / Product Owner
- [ ] [Question] — **Impact**: [What changes based on the answer]

### For Backend / API Team
- [ ] [Question] — **Impact**: [What changes based on the answer]

### For QA Team
- [ ] [Question] — **Impact**: [What changes based on the answer]

### For Design Team
- [ ] [Question] — **Impact**: [What changes based on the answer]

---

## 🟢 Nice to clarify (can start development without, but good to know)
Questions about edge cases, future scope, or polish items.

### For PM / Product Owner
- [ ] [Question] — **Impact**: [What changes based on the answer]

### For Backend / API Team
- [ ] [Question] — **Impact**: [What changes based on the answer]

---

## 📌 Assumptions (what I'm assuming if no answer is given)
Assumptions the analysis will make if these questions go unanswered. Listed so stakeholders can correct them.

- [ ] **Assumption**: [What is assumed] — **If wrong**: [What breaks or changes]

---

**Total: [N] questions | [N] blockers | [N] clarifications | [N] nice-to-have**
**Next step**: Get answers to at least the 🔴 Blockers, then say "run full analysis" to generate the complete checklist.
```

### Role tagging guide

Tag questions to the role best equipped to answer:

- **PM / Product Owner** — Business rules, scope decisions, user behavior, feature flags, rollout strategy, priority calls
- **Backend / API Team** — API contracts, server-side behavior, data availability, auto-processes, infrastructure
- **Design Team** — UI/UX specs, component design, interaction patterns, accessibility, visual states
- **Compliance / Legal** — Regulatory requirements, risk disclosure, exchange rules, data privacy
- **QA Team** — Test environment needs, test data requirements, automation feasibility
- **DevOps / Infra** — Deployment, feature flags, monitoring, performance requirements

### Priority classification guide

- **🔴 Blocker**: The answer changes the core architecture, data model, or API contract. You literally cannot start coding without this.
- **🟡 Clarification**: The answer affects specific flows, edge cases, or UI details. You can start the core work but will need this before the feature is complete.
- **🟢 Nice to clarify**: The answer affects polish, future scope, or unlikely edge cases. You can ship V1 without it.

---

## Mode 2: Full analysis

Only run this AFTER the user has provided answers to Mode 1 questions (or explicitly says to proceed with assumptions).

Execute these phases in order. Read the referenced file for each phase BEFORE generating output.

### Phase 1: Story clarification
Read `references/story-clarifier.md`. Incorporate answers provided by the user. List remaining assumptions.

### Phase 2: Domain analysis
Read `references/domain/orchestrator.md` which coordinates:
- `references/domain/approval-checker.md` — Approvals needed
- `references/domain/domain-questions.md` — Remaining business questions (most should be answered by now)
- `references/domain/domain-test-cases.md` — Business rule test scenarios

### Phase 3: Tech analysis
Read `references/tech/orchestrator.md` which coordinates:
- `references/tech/code-context.md` — Files, modules, architecture layers affected
- `references/tech/impact-analyzer.md` — Which existing features are impacted
- `references/tech/tech-test-cases.md` — Technical test cases
- `references/tech/edge-cases.md` — Technical edge cases
- `references/tech/tech-stack.md` — Stack-specific considerations

### Phase 4: QA analysis
Read `references/qa/orchestrator.md` which coordinates:
- `references/qa/user-test-cases.md` — User-facing test cases
- `references/qa/feature-questions.md` — QA perspective questions
- `references/qa/ux-edge-cases.md` — UX edge cases

### Phase 5: Cascading impact analysis
Read `references/impact-cascade.md`.
For each feature identified as impacted in Phase 3:
- Re-run Domain + Tech + QA analysis scoped to the delta
- Identify what needs to change in existing features
- Flag regression risks

### Phase 6: Output to Notion
Read `references/notion-output.md`.
- Auto-create a Notion page with the complete analysis as checklists
- Organize by: Primary Feature → Domain/Tech/QA checklists → Impacted Features → Delta checklists

## Key principles

1. **Questions before analysis** — Never produce a full analysis without first surfacing questions. Assumptions become bugs.
2. **Tag by role, not by pillar** — Stakeholders don't think in "Domain/Tech/QA". They think "that's a PM question" or "ask backend". Tag accordingly.
3. **Priority matters** — Not all questions are equal. Blockers first, polish questions last.
4. **Story-specific, not generic** — Every question must be specific to THIS feature. Generic questions like "what about error handling?" waste stakeholder time. Instead: "What error message should the user see when MIS order is rejected due to insufficient margin?"
5. **Trading/fintech by default** — Think about market hours, exchange rules, order types, real-time data, regulatory compliance. But adapt to any domain.
6. **Cascade is critical** — If Feature A touches Feature B, surface questions about B too.

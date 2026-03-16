# Feature Analyzer

A Claude Code skill that interrogates user stories before you write a single line of code — so nothing gets missed during development.

## The problem

You get a feature spec. You start coding. Halfway through, you realize:

- The spec didn't mention what happens during market close
- Backend hasn't built the API you assumed existed
- QA finds 12 edge cases you never considered
- Changing the order model broke the positions screen

Every one of these was a **question you could have asked before writing code**.

## What this skill does

Feature Analyzer reads your user story through three lenses — **Domain**, **Tech**, and **QA** — and surfaces every question, gap, and risk before development begins.

It works in two phases:

### Phase 1: Story interrogation

Feed it a user story. It produces **only questions**, organized by:

**Priority**
- 🔴 **Blockers** — Must answer before any development starts
- 🟡 **Clarifications** — Should answer before feature is complete
- 🟢 **Nice to clarify** — Can ship V1 without these

**Role** (who should answer)
- PM / Product Owner
- Backend / API Team
- Design Team
- Compliance / Legal
- QA Team
- DevOps / Infra

Take this list to your stakeholders. Get answers.

### Phase 2: Full analysis

Once you have answers, run the full analysis. It produces an exhaustive checklist covering:

- **Domain** — Approvals needed, business rules, regulatory checks, domain test cases
- **Tech** — Code context, impacted features, technical test cases, edge cases, stack considerations
- **QA** — User-facing test cases (P0/P1/P2), QA questions, UX edge cases
- **Cascading impact** — For every feature affected by your change, re-runs all three lenses on the delta

Output goes to **Notion** as structured checklists your team can work through.

## Who is this for

- **Android developers** working on complex features (trading apps, fintech, any regulated domain)
- **Tech leads** who want to catch gaps before sprint commitment
- **Teams** that want a repeatable pre-dev analysis process

Default context is **trading/fintech** (NSE/BSE, broker APIs, SEBI regulations, market hours, order lifecycle) but the skill generalizes to any Android app domain.

## Installation

### Claude Code

Drop the `.skill` file into your Claude Code skills directory:

```bash
# Copy to your skills directory
cp feature-analyzer.skill ~/.claude/skills/

# Or install from the packaged file
# Claude Code will auto-detect the skill
```

### Manual setup

Clone and copy to your Claude Code config:

```bash
git clone <repo-url>
cp -r feature-analyzer ~/.claude/skills/
```

## Usage

### Phase 1 — Interrogate the story

Paste your user story and ask Claude to analyze it:

```
analyze this story:

[paste your feature spec, JIRA ticket, or free-text description]
```

Claude outputs a prioritized question list tagged by role. Example output:

```markdown
## 🔴 Blockers

### For PM / Product Owner
- [ ] Is Part 2 (position restriction) fully removed from scope?
      — Impact: Changes data model and validation logic entirely

### For Backend / API Team
- [ ] Does the auto-square-off API return CnT charges in the response?
      — Impact: Determines if app needs to calculate or just display charges

### For Compliance / Legal
- [ ] Does SEBI require risk disclosure before enabling MIS for a user?
      — Impact: May need a one-time consent flow before first MIS order
```

### Phase 2 — Full analysis (after getting answers)

Once you have answers from stakeholders:

```
run full analysis

Answers:
1. Part 2 is removed — users can hold both MIS and NRML
2. Backend returns CnT charges in the square-off response
3. No SEBI consent flow needed, education message is sufficient
...
```

Claude produces the complete checklist and creates a Notion page.

### Quick reference

| You say | What happens |
|---|---|
| `analyze this story` | Phase 1 — questions only |
| `review this feature` | Phase 1 — questions only |
| `what am I missing` | Phase 1 — questions only |
| `run full analysis` | Phase 2 — complete checklist |
| `generate checklist` | Phase 2 — complete checklist |
| `I have the answers, now analyze` | Phase 2 — complete checklist |

## Skill architecture

```
feature-analyzer/
├── SKILL.md                          # Orchestrator (two-phase workflow)
└── references/
    ├── story-clarifier.md            # Ambiguity detection, assumption surfacing
    ├── domain/
    │   ├── orchestrator.md           # Domain analysis coordinator
    │   ├── approval-checker.md       # Exchange, regulatory, compliance approvals
    │   ├── domain-questions.md       # Business questions for stakeholders
    │   └── domain-test-cases.md      # Business rule test scenarios
    ├── tech/
    │   ├── orchestrator.md           # Tech analysis coordinator
    │   ├── code-context.md           # Files, modules, architecture layers
    │   ├── impact-analyzer.md        # Which features are affected
    │   ├── tech-test-cases.md        # API, data, concurrency tests
    │   ├── edge-cases.md             # Race conditions, null states, platform
    │   └── tech-stack.md             # Compose, Hilt, Flow, Room specifics
    ├── qa/
    │   ├── orchestrator.md           # QA analysis coordinator
    │   ├── user-test-cases.md        # Happy path, error, empty, loading states
    │   ├── feature-questions.md      # QA perspective questions
    │   └── ux-edge-cases.md          # Rotation, back press, a11y, gestures
    ├── impact-cascade.md             # Re-analyze affected features
    └── notion-output.md              # Auto-create Notion checklist page
```

Each micro-skill is a separate `.md` file. To update a specific concern (e.g., add a new exchange rule), edit one file — the orchestrators pick up changes automatically.

## Customization

### Change the domain

The skill defaults to trading/fintech. To adapt for your domain:

1. Edit `references/domain/approval-checker.md` — Replace exchange/SEBI checks with your domain's compliance requirements
2. Edit `references/domain/domain-questions.md` — Replace trading-specific questions with your domain's business rules
3. Edit `references/domain/domain-test-cases.md` — Replace market-hours scenarios with your domain's test cases

The tech and QA micro-skills are mostly domain-agnostic (Android/Kotlin/Compose patterns apply universally).

### Change the tech stack

Default stack is Kotlin + Jetpack Compose + Clean Architecture + Hilt + Room + Coroutines/Flow + Retrofit.

To adapt: edit `references/tech/tech-stack.md` with your stack's specific concerns.

### Add a new concern

1. Create a new `.md` file in the appropriate directory (e.g., `references/tech/performance.md`)
2. Update the orchestrator to reference it (e.g., add a line to `references/tech/orchestrator.md`)
3. The main `SKILL.md` doesn't need changes — it delegates to orchestrators

### Remove a concern

Delete the `.md` file and remove the reference from its orchestrator. Done.

## Example output

### Phase 1 output (MIS/NRML feature for a trading app)

```markdown
# 📋 Story Interrogation: MIS Order Type for F&O
📝 Add Intraday (MIS) / Overnight (NRML) toggle to F&O order form
📅 2026-03-16

## 🔴 Blockers

### For PM / Product Owner
- [ ] Is Part 2 (simultaneous position restriction) fully removed?
      — Impact: If yes, simplifies implementation. If no, need position
        checking logic and locked toggle states.
- [ ] Does MIS apply to Futures only, Options only, or both?
      — Impact: Story title says "Options" but objective says "F&O".
        Changes which order forms are modified.

### For Backend / API Team
- [ ] Is auto-square-off at 3:20 PM handled entirely server-side?
      — Impact: If yes, app only reflects results. If no, app needs
        to initiate square-off orders.
- [ ] What happens if auto-square-off fails (e.g., no liquidity)?
      — Impact: Need error state handling and user notification design.

### For Compliance / Legal
- [ ] Does SEBI require explicit risk disclosure before first MIS order?
      — Impact: May need consent flow instead of just education message.

## 🟡 Clarifications
...

Total: 28 questions | 8 blockers | 12 clarifications | 8 nice-to-have
```

## Design decisions

**Why questions first, not analysis?** Because a 130-item checklist with baked-in assumptions is less useful than 28 targeted questions that prevent those assumptions from becoming bugs.

**Why tagged by role?** Developers don't forward a document to "the Domain team." They Slack a specific person. Role tags make the output immediately actionable.

**Why micro-skills?** Each concern (approval checking, edge cases, UX testing) is a separate file. When you learn a new pattern — like a new exchange rule or a platform edge case — you update one file, not a monolithic prompt.

**Why two invocations?** Because the answers change everything. An analysis based on assumptions is guesswork. An analysis based on confirmed answers is a development plan.

## License

MIT

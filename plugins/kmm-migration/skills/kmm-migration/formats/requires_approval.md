# Format — NEEDS YOUR CALL (canonical user-gate format)

> Every user gate uses this exact format. Composed by `gate_investigator`,
> transcribed verbatim by the orchestrator.

## Contents

- [The template](#the-template)
- [Writing rules](#writing-rules)
- [Rule-citation table](#rule-citation-table)
- [Worked example](#worked-example)

## The template

```
⚠ NEEDS YOUR CALL — <gate name>

What's happening
  <one short sentence, no jargon>

Where to look
  • <path:line> — <what this file shows>
  • <path:line> — <what this file shows>

Your choices
  A) <short action in 3-6 words>
     Does this:  <one plain line>
     Trade-off:  <one plain line>

  B) <short action in 3-6 words>
     Does this:  <one plain line>
     Trade-off:  <one plain line>

Skill recommends  A
Why (skill rule)  <Law N / Rule N / §X.Y — CITED, not improvised>

Reply: A | B | need more context
```

## Writing rules

- No jargon in "What's happening"
- `Where to look` uses `path:line` format (Rule 11)
- Options are actions, not descriptions
- `Does this` and `Trade-off` are ONE line each
- Recommendation is always ONE option (or option C — see below)
- Why CITES a rule by name; paraphrase is NOT acceptable

## Rule-citation table

When picking the Why citation, map the decision type:

| Decision about… | Typical citation |
|---|---|
| Baseline validity | Law 2; §12.2 if rebase considered |
| Scope | Law 3; §11.2 investigation cited |
| Library / pattern choice | Law 13; Rule 4 if new dep |
| Unclear behaviour | Law 12; source-of-truth precedence |
| Speculative abstraction | Law 14 |

If no rule fits, present option `C) skill has no rule for this, please
decide from context` — no recommendation.

## Worked example

```
⚠ NEEDS YOUR CALL — Phase 4 parity mismatch

What's happening
  Migrated login flow renders 4 pixels wider than the baseline on iPhone 15.

Where to look
  • kmm_migration/reports/login/12_parity_verifier.md:34 — diff image
  • kmm_migration/baseline/login/screenshot_goldens_manifest.md:12 — tolerance 0.5%

Your choices
  A) Re-migrate affected composable
     Does this:   Ask a fresh migrator to redo shared-UI width handling.
     Trade-off:   One more migrate → review → verify cycle. ~5 more minutes.

  B) Rebase the baseline via escape hatch
     Does this:   Re-record OG goldens with a wider tolerance, with your approval.
     Trade-off:   Weakens parity guarantee. Requires a separate approval gate.

Skill recommends  A
Why (skill rule)  Law 2 (baseline immutable during migration). Rebasing is a
                  distinct named operation (§12.2), only valid when the
                  tolerance itself is proven wrong — not when migration output
                  drifts. The report shows drift, not environmental noise.

Reply: A | B | need more context
```

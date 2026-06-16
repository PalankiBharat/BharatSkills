---
name: review
description: Use when reviewing a KMM migration PR or branch in sniper-v2-android — "review the migration", "kmm review", "review PR <n>" for kmm/* branches, or as the review round of an in-flight kmm-pipeline migration.
argument-hint: "[pr-number | branch]"
---

# KMM Migration Review

Adversarial, lens-split review of one migration's diff. With migration state (`ACTIVE`/state dir): full rubric against contract.md + plan.md. Standalone (PR number/branch only): law + generic checks; state the limitation in the verdict. Resolve the diff range first (`gh pr view` / merge-base); note this repo sometimes keeps review history in-repo (`docs/specs/*review*.md`) — read any that reference the branch.

1. Dispatch TWO kmm-reviewer agents in parallel, one per lens: `law-compliance`, `parity-integrity`. Brief each with: the Law path, `references/rubric.md` (their section), contract/plan paths when present (standalone has none — the parity lens then skips contract-coverage and says so), diff range. They return refutation-style findings with rule numbers and file:line.
2. **Adversarially verify before accepting** (superpowers:receiving-code-review discipline): for every `blocker`, reproduce the evidence yourself — read the cited lines, run the cited command. A finding you cannot reproduce is downgraded to `note` with the discrepancy recorded. No performative agreement, no blind fixes.
3. Write `review-report.md`: verdict `PASS | FAIL`, verified findings (rule, file:line, severity, fix route), unverifiable suspicions, "not checked" disclosures from both lenses.
4. Findings get stable IDs (`L1…` law lens, `P1…` parity lens); every fix commit carries its `L#`/`P#` finding ID in the subject so the audit trail is greppable (#439 did this with an ad-hoc `B4`/`S-17` scheme; `L#`/`P#` standardizes it). When the diff contains rewrite-style files (new file replacing a screen/VM rather than an `R` rename), run one EXTRA behavior-loss-only sweep on just those files before the verdict — a 134-finding review here still missed 7 dropped-behavior blockers that a dedicated pass caught.
5. Orchestrated mode: FAIL items become kmm-migrator dispatches (one per finding cluster); re-run BOTH lenses on the new diff after fixes. More than 3 review⇄fix loops → G3, something is structurally wrong. Standalone mode: deliver the report; fix only if the user asks.

Severity discipline: `blocker` = Law violation, parity break, or constitution violation; `fix` = should change before merge; `note` = flagged, out-of-scope (Root-Cause-Only principle: adjacent bad code is reported, never patched here).

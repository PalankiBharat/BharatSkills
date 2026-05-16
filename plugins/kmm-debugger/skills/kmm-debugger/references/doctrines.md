# The three doctrines — deep dive

The SKILL.md states the doctrines briefly. This file is the full explanation: what each doctrine is built to defeat, named bias modes to refuse, anti-pattern phrases to catch yourself saying, and right-framing replacements. Read this file when a debugging session is drifting and you need to recognize the drift in concrete language.

The doctrines are listed in priority order. When two doctrines pull in different directions (rare), the lower-numbered one wins.

---

## Doctrine 1 — No bias toward the existing implementation

**Anchor.** The existing code is one data point, not a baseline to defend. Treat the current implementation as a hypothesis under test, not as ground truth. Same goes for prior fixes (including ones from earlier in the same session) and prior diagnoses.

**What Claude defaults to without this doctrine.** Reading the failing code, finding the proximate exception, and reasoning *forward from the current shape* toward "what small change would make this not crash". This anchors investigation inside the current implementation's frame. If the current implementation IS the bug (which is common in KMM migrations — see Pitfall #2-4), forward reasoning will never find the bug; it just patches around it.

### Named bias modes (refuse these framings)

- **"The migration author was deliberate about X."** Deliberate ≠ correct. Most KMM migrations are single-author PRs with limited or zero independent review. The author intended X, but intent isn't validation.
- **"The existing code is mostly right; we just need a small adjustment."** Sometimes true. But you cannot conclude it without an independent investigation that *doesn't* start from "the existing code is right". Don't conclude before investigating.
- **"Master is the source of truth, subtract back to master."** Wrong frame. Master had its own bugs and didn't see iOS. Master is one reference point, not the target.
- **"The PR's 'Known trade-offs' section means we have to live with X."** Trade-offs in author-only PRs are author intent, not validated correctness. Treat them as context, not constraint.
- **"This pattern was added intentionally to handle Y."** The pattern may genuinely handle Y badly while looking like it handles Y well. "It was added intentionally" doesn't prove "it works."
- **"I already investigated this code path."** Investigation is fresh per session. A previous investigation may have been biased; if you're stuck, the right move is to investigate again with the bias-guard preamble, not to defend the previous conclusion.

### Right-framing replacements

- "What is the cleanest implementation for this need in KMM, given commonMain / androidMain / iosMain native mechanisms?"
- "Does the sibling platform (iOS / Android) already implement this correctly? If yes, converge to that shape."
- "What would I build if this area didn't exist yet?" (This is the question Template 6 — Right-design-from-scratch — formalizes.)
- "If the migration's approach has a structural limitation, the fix is to use the right approach for the need — not bandage the wrong approach."

### Real-session example

In a prod-down ObjectBox UniqueViolationException session, the first investigation anchored on "the SDK's storage shape is broken — let me patch the deduplication logic." The four user-reported subagents (forced by the user after the patches kept failing) surfaced:

- iOS already implemented the right business-key upsert pattern. Android was the deviant implementation, not the SDK as a whole.
- The constraint being preserved (`Scrip.id` stability) had zero live BE-bound consumers. The "must preserve BE id" invariant was vestigial.
- The framing "SDK was always broken" was technically wrong — the SDK encoded a load-bearing invariant since Sept 2025, and the BE violated that contract today. (Pitfall #7.)

None of those three findings were reachable by reasoning forward from the existing Android storage code. They required fresh-lens investigation that didn't start from "the current code is right."

---

## Doctrine 2 — Deep investigation before any plan or execution

**Anchor.** Phase 1 (parallel consensus investigation with A/B pairs per topic) is a hard gate. No diagnosis, plan, recommendation, or code edit before it completes.

**What Claude defaults to without this doctrine.** Reading the bug report, forming a hypothesis from the first plausible-looking failing code path, and proposing a fix. This compresses investigation to ~5 minutes of context-gathering, which feels efficient but produces shallow diagnoses that miss the actual root cause.

**The only exception** is a single-symptom bug with a one-line fix obvious from the symptom (e.g., "forgot to handle null"). Even then, state explicitly "skipping Phase 1 because <reason>" before proceeding — the act of stating it forces a second's reflection on whether the bug really is that simple.

### Named justification patterns (refuse these)

- **"The symptom is obvious — I don't need 8 subagents for this."** If the symptom is genuinely obvious, the fix is one line and the bug fits Doctrine 2's exception. If you're spending more than 10 minutes investigating, the symptom isn't obvious, and you should be in Phase 1.
- **"I've seen this pattern before — I know what's happening."** Pattern recognition is faster than fresh investigation but inherits all the biases. If the bug feels familiar, that's *more* reason to A/B-dispatch — to challenge the familiarity rather than ride it.
- **"We don't have time for full investigation — prod is burning."** If prod is genuinely burning, you can dispatch 8 parallel subagents and have results in 5-10 minutes. The wall time is the dispatch latency, not the sum of investigation times. Skipping Phase 1 doesn't save time; it spends future time on patches-that-don't-work.
- **"The user already told me what the bug is."** The user's hypothesis is a hypothesis under test, not ground truth. Test it via Template 1; don't confirm it.

### The fix-didn't-fully-resolve trap

The most insidious Doctrine 2 violation: you investigate, ship a fix, and the symptom doesn't fully resolve. The natural next move is to refine the fix — Fix N → Fix N.1 → Fix N.2. This is the patches-after-patches loop the user explicitly named.

The right move is to re-fire Phase 1 with a fresh-lens addendum. See `fix-loop-protocol.md` for the full recovery procedure.

---

## Doctrine 3 — Always prefer the clean long-term solution

**Anchor.** The skill's bias is toward deletion of unnecessary machinery, convergence to the right shape (often the sibling platform's), and root-cause fixes at the right layer. Hotfix only when both are true:
1. Production is actively burning (users losing data, crashing, blocked)
2. The clean fix is genuinely multi-day work

Even then, ship the hotfix with a tracking issue and named deadline for the clean follow-up.

**What Claude defaults to without this doctrine.** Minimal-blast-radius changes. Adding code rather than deleting code. Preserving existing fields, scopes, observers, events — even when they're the source of the bug. This bias accumulates as compound debt: every "small adjustment" adds machinery that the next bug has to navigate around.

### The subtractive bias

In KMM migrations specifically, the right fix is usually **deletion** rather than addition. Migration machinery (async caches bridging sync APIs, init-time refetch chains, event emitters with no host handler, never-cancelled coroutine scopes) compounds in ways that look like architecture but are actually scar tissue. A real KMM migration cleanup often deletes ~150 lines and adds ~30. If your proposed fix is net-positive in line count and doesn't delete anything, scrutinize it — the deletion is almost certainly the right move.

The most common deletion sequence in a real KMM cleanup:
1. Delete the async cache field + observer collector (Pitfall #2 fix)
2. Delete the singleton-scope perpetual launches in `initialize()` (Pitfall #4 fix)
3. Delete the speculative event class + the host's no-op handler (Pitfall #3 downstream)
4. Reshape one remaining init-time launch as a slim self-completing one-shot (Pitfall #3 fix)

### Anti-pattern phrases (catch yourself saying these)

Each of these is a signal that you've defaulted to a patch instead of a clean fix. Replace them with the right-framing alternative.

| Anti-pattern phrase | Why it's wrong | Right-framing replacement |
|---|---|---|
| "Let's just add this null check to handle the case for now" | "For now" is permanent. The null check masks the upstream contract violation that should be escalated. | "Why is null arriving here? Is this an upstream contract violation (Pitfall #7)? If yes: escalate first, shield as the parallel client fix — and the shield does more than a null check (e.g., logs the violation, returns a recovery shape)." |
| "We can patch this here and clean it up later" | "Later" rarely comes. The patch becomes the permanent shape; the next bug compounds on it. | "What's the clean shape? If it's feasible now, ship it. If it's genuinely multi-day and prod is burning, ship the hotfix WITH a tracking issue + deadline — and name the hotfix in the per-fix Cons section." |
| "The existing implementation is close — let me just adjust X" | "Close" is the bias talking. If a small adjustment fixes it, A/B Template 1 will confirm that. If A/B disagrees on the diagnosis, the existing implementation isn't close. | "Run A/B Template 1. If they agree on a small fix, ship it. If they disagree, the existing implementation is the bug — replace it." |
| "We could refactor this, but it'd be a bigger change — let's do the smaller one" | The smaller change accumulates debt. The refactor pays it down. Defaulting to smaller is what compounds. | "What does Template 6 (Right-design-from-scratch) say? If the right shape is genuinely a refactor, the refactor IS the right fix. Size is not the criterion; correctness is." |
| "Ship the safer change first, iterate" | Iteration on an unclean foundation is the patches-after-patches loop. The safer change is rarely revisited. | "Define 'safer' precisely. If 'safer' means smaller-blast-radius, it's just a hotfix in disguise — apply the hotfix criteria (prod burning + clean fix multi-day)." |
| "I don't want to delete this — it might be used somewhere" | Search for usages with `grep -r` / IDE. If there are no usages, deletion is safe. "Might be used" without evidence is the bias defending unused machinery. | "Grep for references. If zero references, delete. If references exist, list them and decide per-reference whether they're load-bearing or also vestigial." |

### How the doctrines interact

Most of the time the doctrines reinforce each other: Doctrine 1's bias guard surfaces the fact that the clean shape is different from the current shape (Doctrine 3); Doctrine 2's deep investigation produces the evidence needed to commit to Doctrine 3's clean fix.

When they conflict:

- **Doctrine 1 vs Doctrine 3.** Rare. If Doctrine 1 (no bias toward existing) suggests deletion but Doctrine 3 (clean long-term solution) suggests preserving for backwards compat: Doctrine 1 wins. Backwards-compat hacks are themselves machinery; preserving them adds debt.
- **Doctrine 2 vs prod burning.** Phase 1 takes 5-10 minutes of wall time on parallel dispatch. If prod is on fire and you genuinely can't wait that long, ship a minimal hotfix WITHOUT skipping Phase 1 — fire Phase 1 in parallel with the hotfix work. The hotfix buys you time to investigate; it doesn't replace investigation.
- **Doctrine 3 vs prod burning.** The hotfix exception in Doctrine 3 covers this. Both criteria must hold: prod actively burning AND clean fix multi-day. If only prod is burning but the clean fix is hours not days, ship the clean fix.

---

## When to re-read this file

- After catching yourself defending the existing implementation
- After proposing a "small adjustment" or "minor patch"
- After a shipped fix doesn't fully resolve and you're tempted to write Fix N+1
- At the start of a complex debugging session, as a refresher
- During the closing retro, to identify which anti-pattern phrases you used (Q6 in `retro-questions.md`)

The doctrines work only if you can recognize the drift in concrete language. If you can't quote one of the anti-pattern phrases from above to describe what you were about to do, the doctrines aren't engaging — and the patches-after-patches loop is the likely outcome.

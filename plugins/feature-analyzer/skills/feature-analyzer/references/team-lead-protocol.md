# Team-Lead Protocol

A flat fan-out of parallel specialist agents loses context across pillars and produces duplicate / contradictory questions. The right shape is a **team with a lead**: one orchestrator (the "team lead") that owns the global picture, spawns specialists, brokers cross-specialist questions, and merges the final output. Specialists never talk to each other directly — all cross-agent communication routes through the lead.

## Why this beats flat parallel

- **Context coherence** — lead owns the global picture; specialists stay scoped and don't drift.
- **Deterministic merge** — lead de-dupes across pillars before output reaches the developer.
- **Auto-answer** — lead drops any specialist question whose answer is in `flow-tracer`'s output.
- **Cross-pillar consistency** — if `flow-tracer` finds duration is sent as string `type`, lead injects that fact into `tech-questioner` so it stops asking "what's the wire format?"

## Team shape

```
                 ┌──────────────────────────────┐
                 │   feature-analyzer LEAD      │
                 │  (orchestrator + broker)     │
                 └──────────────┬───────────────┘
                                │ spawns, queries, merges
        ┌───────────┬───────────┼───────────┬───────────┬───────────┐
        ▼           ▼           ▼           ▼           ▼           ▼
   flow-tracer  gap-analyzer design-rev  domain-Q    tech-Q       qa-Q
                                │
                                ▼
                              critic (audits after merge)
                                │
                                ▼
                            red-team (opt-in, --adversarial)
```

Each specialist's contract is defined in `specialist-roster.md`.

## Lead state machine (FSM)

```
INIT → PREFLIGHT
PREFLIGHT      → ABORT (G5 fail)
               → SCOPE-FILTER (ok)
SCOPE-FILTER   → ABORT (no in-scope sections)
               → WAVE1
WAVE1          → CRITIC-W1
CRITIC-W1      → GATE-A (default)
               → WAVE2 (--no-gates)
GATE-A         → ABORT (user rejects)
               → WAVE2 (user approves or amends)
WAVE2          → CRITIC-W2
CRITIC-W2      → WAVE3
WAVE3          → MERGE
MERGE          → CRITIC-FINAL
CRITIC-FINAL   → CONFLICT-RESOLVE (G12; conflicts found)
               → GATE-B (no conflicts)
CONFLICT-RESOLVE → CRITIC-FINAL (re-audit)
GATE-B         → DONE (user approves)
               → RE-PROMPT (user requests fixes)
               → ABORT
DONE           → emit HTML doc + replay log + token report
```

Every transition is logged to the replay log (see `replay-log-format.md`). Aborts return a structured error — never a silent failure.

## Wave plan

| Wave | Specialists | Inputs | Outputs feed |
|---|---|---|---|
| 1 (parallel) | `flow-tracer`, `design-reviewer` | story + scope-filtered sections; Figma URLs | gap-analyzer, all questioners |
| 2 (sequential) | `gap-analyzer` | flow-tracer output + story | all questioners |
| 3 (parallel) | `domain-questioner`, `tech-questioner`, `qa-questioner` | gap delta + scope-filter report | merge |
| Merge | lead | all wave outputs | critic |
| Critic | `critic` (always), `red-team` (opt-in) | merged output | final HTML |

`design-reviewer` only runs if Figma URLs are present in the story.

## Pre-flight checklist (G5)

Run before any specialist spawns. Abort with a single message if any item fails — do NOT proceed and silently degrade.

- [ ] Sibling SDK checkouts located (`marketpulse-android-sdk`, `finance-android-sdk`, `sesame-android-sdk`) OR explicitly declared `not_applicable` with a reason.
- [ ] Figma URLs (if any in story) parse to valid file keys.
- [ ] Repo is a git working tree; current branch identified.
- [ ] Story has at least: title, user-facing intent, 1+ acceptance criterion.

Failure → `Pre-flight failed: <reasons>. Fix and re-run.`

## Cost ceiling + dry-run (G13)

- `--dry-run` — lead prints specialist roster, wave plan, estimated tokens. No spawning. Developer approves.
- Token budget per session, default 300k. At 80% the lead stops spawning new specialists and finalises with what it has, marked `partial: true`. Developer sees the partial flag in the scope report.

## Human gates (G9)

Two optional pauses where lead waits for developer ACK.

- **Gate A** — after Wave 1 (flow-tracer + design-reviewer). Show flow doc + screen catalog. Developer corrects misreads BEFORE Wave 2 spends compute on bad foundations.
- **Gate B** — after critic. Show pre-final output. Developer can drop / merge / re-prompt before issue is finalised.

Defaults: both ON. `--no-gates` for autonomous use.

## Bounded retries with escalation (G11)

Per specialist:
- ≤2 retries on schema-fail (G1)
- ≤1 retry on evidence-missing (G2)

After exhaustion:
- Mark that pillar's output as `partial: true`
- Surface failure reason to user
- Do NOT silently swallow the gap

## Cache layer + version (G15, G16)

- Flow-tracer output cached by `(repo-sha, feature-keyword)`.
- Cache hit → skip Wave 1 flow-tracer call; reuse prior output.
- Lead prompt carries semver. Bump → cache invalidates.
- Replay logs record the version so post-mortems compare like-with-like.
- `--no-cache` bypasses.

See `cache-layer.md` for layout.

## Why the lead is forbidden to let specialists chat

Specialists chatting directly creates a graph, not a tree. Cycles deadlock; non-determinism breaks reproducibility. By routing every cross-specialist need through the lead via `needs_from` (see `cross-agent-broker.md`), the dependency graph stays a tree and merge is deterministic.

# Orchestrator prompt palette

The Orchestrator dispatches via `bash .harness/send <role> "<INSTRUCTION>. EXPECT: <artifact>"`. Each instruction carries the phase ("phase P") and an `EXPECT:` artifact for the done-signal.

## Dispatch instructions
| Role | Instructions |
|---|---|
| tech-lead | `ANALYSE` (→ spec.md + feature-analysis.md + questions.json) |
| dev | `PLAN` (→ tech-plan.md, first cut) · `IMPLEMENT` / `IMPLEMENT-NEXT` (TDD the design) · `FIX-PER-QA` · `ADD-TAG` · `ADDRESS-SMALL` · `IMPLEMENT-REPLAN` · `OPEN-PR` |
| architect | `PLAN` (→ design.md, pseudo-code) · `REVIEW` (post-code → architect-review.md) |
| qa | `VERIFY` / `TEST` (manual/user-journey → qa-report.md) · `RE-TEST` |

Gate-resume uses `bash .harness/answer <role> "<verbatim user answers>"` (the role incorporates them; the Orchestrator never reconciles). Render a human gate with `bash .harness/ask <questions.json>` (or `render-review.sh` for a plain page).

## User commands (accepted anytime)
| Command | Effect |
|---|---|
| `feedback <name\|role>: <text>` | `feedback.sh task <target> <text>` → folded into that role's next dispatch. |
| `skill-feedback <skill>: <text>` | `feedback.sh skill <skill> <text>` → durable store (never gates). |
| `restart <name\|role>` | checkpoint → respawn the pane → re-dispatch (see `restart.md`). |
| `status` | summarise stage/phase + each role's status from `state.json` + `log.md`. |
| `continue` / `--resume` | `bash .harness/resume` — restart the live Orchestrator pane, or rebuild (see `resume.md`). |
| `--auto` | skip the HTML review gates (never the security rails); small stories only. |

## How panes run + get driven (interactive Claude per pane)
`harness-init.sh` opens a tmux window `harness-<slug>-<date>` **in your current session**; each pane runs `agent-pane.sh <role>` → a **persistent interactive `claude --agent <persona>`** (bypass perms). The pane's model is **pinned explicitly** at launch by `role_model` (lib.sh) via `claude --model`, never left to the user's default: deep panes (orchestrator/tech-lead/architect) → `--model opus`; the build lanes (dev/qa) → `--model opusplan` (opus plans, sonnet executes — `opusplan` is a valid `--model` alias, verified on the CLI). Override per role with `HARNESS_MODEL_<ROLE>` (e.g. `HARNESS_MODEL_DEV=sonnet`) or globally with `HARNESS_MODEL`. `send.sh` writes the full instruction to `.harness/<role>/inbox.md`, sets `status=working`, and **nudges the pane** (`send-keys` the trigger, pause, then a **separate `Enter`** — Claude's TUI won't submit a combined "text Enter"). The agent reads its inbox, works **visibly**, runs long commands via `bash .harness/run <role> -- <cmd>`, then signals `bash .harness/done <role>` as its last action. The Orchestrator polls with `poll.sh --settle`; a file-based watchdog covers lost nudges / stalls and runs a periodic full-pane SWEEP. Each role is one pane that does its whole lane itself (no sub-workers): Dev plans+codes, QA authors+runs Maestro — opusplan keeps that cheap (opus plans, sonnet executes). Persona→role: manish=tech-lead · bharat=dev · rohit=qa · mohit=architect.

**Setup:** `harness-allow.sh` runs once so `send`/`poll` calls don't prompt. `harness-init.sh` pre-seeds folder-trust so panes don't stall at the trust dialog. The Orchestrator is launcher-started + self-nudged; the main session is launcher-only.

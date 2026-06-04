# Orchestrator prompt palette

The Orchestrator never improvises wording. It uses these fixed templates for every action, so behaviour is identical every run. Each dispatch goes via `send.sh --role <role> --message "<INSTRUCTION>\nEXPECT: <artifact>"`.

## Dispatch instructions
| Role | Instructions |
|---|---|
| tech-lead | `ANALYSE` · `RESUME` |
| dev | `PLAN` · `IMPLEMENT-NEXT` · `FIX-PER-QA` · `ADD-TAG` · `ADDRESS-SMALL` · `IMPLEMENT-REPLAN` |
| qa | `TAG-CHECK` · `PREP` · `TEST` · `RE-TEST` |
| architect | `REVIEW` |

Each carries the phase ("phase P") and an `EXPECT:` artifact for the done-signal.

## User commands (accepted anytime in the main session)
| Command | Effect |
|---|---|
| `feedback <name\|role>: <text>` | `feedback.sh task <target> <text>` → folded into that role's next dispatch (or interrupt + re-dispatch). |
| `skill-feedback <skill>: <text>` | `feedback.sh skill <skill> <text>` → durable store (continuous; never gates). |
| `restart <name\|role>` | checkpoint → respawn the pane → re-dispatch `RESUME` (see `restart.md`). |
| `status` | summarise stage/phase + each role's status from `state.json` + `log.md`. |
| `continue` / `--resume` | resume the run from `state.json` (see `resume.md`). |
| `--auto` | skip the HTML review gates (never the security rails). |

## How panes run + get driven (interactive Claude per pane)
`harness-init.sh` opens a tmux window (named `harness-<slug>-<date>`) **in your current session**; each pane runs `agent-pane.sh <role>` → a **persistent interactive `claude --agent <persona>`** (bypass perms; the agent file's `model:`). To dispatch: `send.sh` writes the full instruction to `.harness/<role>/inbox.md`, sets `status=working`, and **nudges the pane** (`send-keys` the trigger text, pause, then a **separate `Enter`** — Claude's TUI won't submit a combined "text Enter"). The agent reads its inbox, works **visibly**, then runs `bash .harness/done <role>` (the sentinel). The orchestrator polls with `poll.sh` (timeout → `blocked`/restart). Leads dispatch their **sonnet workers** (`bharat-dev`/`bharat-qa`) via the Agent tool. Persona→role: manish=tech-lead · mohit-dev=dev · rohit=qa · mohit-arch=architect.

**Setup:** the orchestrator runs `harness-allow.sh` once so its own `send`/`poll`/`init` calls don't prompt you. **Trust:** a brand-new/untrusted dir shows Claude's one-time "trust this folder?" dialog per pane; your already-trusted app repo won't.

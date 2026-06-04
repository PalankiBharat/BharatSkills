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

## How panes load their role (no boot prompt needed)
`harness-init.sh` launches `role-runner.sh <role>`. Each dispatch, the runner loads the **lead agent** (`agents/<persona>.md`, via `lead_persona`) as the `--append-system-prompt` and the inbox as the task — pinned to `--model opus`. The lead then dispatches its **sonnet worker** (`bharat-dev` / `bharat-qa`) via the Agent tool, which honours the worker agent's `model: sonnet`. Persona→role: manish=tech-lead · mohit-dev=dev · rohit=qa · mohit-arch=architect.

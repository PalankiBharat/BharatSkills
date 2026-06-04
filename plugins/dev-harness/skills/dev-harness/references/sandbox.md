# Sandbox mode (opt-in) — `/harness --sandbox`

The safe alternative to bypass-only: Claude Code's **built-in OS sandbox** (macOS Seatbelt / Linux bubblewrap) puts a filesystem + network blast-wall around every worker, so a bad input can't reach your whole machine. It's the doc-blessed replacement for `--dangerously-skip-permissions` — autonomous *within* the boundary, OS-enforced regardless of what the model decides.

## How to turn it on
`harness-init.sh --sandbox` launches each pane with `HARNESS_SANDBOX=1`; `agent-pane.sh` then adds `--settings assets/sandbox-settings.json` to the pane's interactive `claude`. Default (no flag) keeps the proven bypass-only path. **We deliberately do NOT set `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`** — Claude Code forces permission mode to "default" when it's set, which deadlocks an autonomous worker (no human to approve the Write). Credentials are protected by the sandbox `denyRead` list instead (verified by smoke test 2026-06-04).

## What `assets/sandbox-settings.json` enforces
- **Filesystem write:** repo (`./`) + `~/.maestro` + `~/.android` only. Everything else (shell rc, `/bin`, other homes) is read-only/blocked.
- **denyRead:** `~/.aws`, `~/.ssh`, `~/.config/gh`, `~/.config/gcloud`, `~/.netrc`, `~/.npmrc` (the default read policy would otherwise expose these).
- **Network allowlist:** github + google/gradle/maven hosts for builds. Other domains prompt/blocked.
- **excludedCommands:** `gh`/`adb`/`maestro` run outside the sandbox (they fail TLS under Seatbelt / are local + trusted, and are already scoped by `guard.sh`).
- **`allowUnsandboxedCommands: false`** — strict: the escape hatch can't silently re-run a blocked command outside the wall.

## Layers (defense in depth)
1. **`guard.sh`** PreToolUse hook — denylist (force-push / master-push / global-adb / `rm -rf /`).
2. **OS sandbox** — filesystem + network boundary.
3. **Secret redaction** in artifacts (worklog / log / PR body) + the sandbox `denyRead` on credential dirs.

## Known limitations (from the docs)
- The proxy allowlists by hostname **without TLS inspection** → a broad domain (e.g. `github.com`) is a possible exfil path (domain fronting). Keep the allowlist tight.
- Sandbox is **not** a complete isolation boundary; for a hard wall use a dev container / VM (deferred).
- macOS/Linux/WSL2 only — native Windows unsupported.
- First-run gradle builds may need extra domains; add them to `allowedDomains` if a build is blocked.

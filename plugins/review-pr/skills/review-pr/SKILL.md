---
name: review-pr
description: Use when reviewing a GitHub PR — spawns up to 8 grouped review agents in parallel by file type, aggregates findings, supports calibration (human in loop) and autopilot (--auto) modes.
---

# PR Review — Multi-Agent Team

## Usage

- `/review-pr <number> [--repo owner/repo]` — calibration mode (human in loop, default)
- `/review-pr <number> --auto [--repo owner/repo]` — autopilot mode (fully autonomous)

If `--repo` is omitted, infer from `gh repo view --json nameWithOwner --jq .nameWithOwner`.

---

## Step 0: Tech Stack Detection

Before spawning any agent, read the project's build files to build a TechStackProfile:

```bash
cat libs.versions.toml 2>/dev/null; cat app/build.gradle 2>/dev/null; cat build.gradle 2>/dev/null
```

If reviewing a remote PR without local checkout, fetch the raw file from GitHub:
```bash
gh api repos/<owner>/<repo>/contents/libs.versions.toml --jq '.content' | base64 -d 2>/dev/null
gh api repos/<owner>/<repo>/contents/gradle/libs.versions.toml --jq '.content' | base64 -d 2>/dev/null
```

Detect from dependency names present in the file:

| Category | Keywords to look for | Values |
|---|---|---|
| networking | `ktor-client`, `retrofit2`, `retrofit` | `ktor` / `retrofit` / `unknown` |
| di | `hilt-android`, `koin-android`, `dagger` | `hilt` / `koin` / `manual` / `unknown` |
| imageLoading | `glide`, `coil`, `picasso` | detected name / `none` / `unknown` |
| testing | `mockk`, `mockito`, `truth`, `junit-jupiter` | detected names joined |
| async | `kotlinx-coroutines`, `rxjava` | `coroutines` / `rxjava` / `both` |
| database | `room-runtime`, `sqldelight`, `realm` | detected name / `none` |
| navigation | `navigation-fragment`, `navigation-compose` | `nav-component` / `custom` / `none` |
| serialization | `kotlinx-serialization`, `gson`, `moshi` | detected name / `unknown` |

If undetected → set to `unknown` and the relevant agent must flag "unknown stack — review manually" instead of guessing.

---

## Step 1: PR Description Check

```bash
gh pr view <number> --repo <owner/repo>
```

Apply `~/.claude/skills/review-pr/patterns/pr-description.md` patterns to the PR title and description. Report finding if description is missing WHY, missing WHAT, or contradicts the diff.

---

## Step 2: Fetch and Route Diff

```bash
gh pr diff <number> --repo <owner/repo>
```

Parse the full diff into per-file chunks. Route each file:

| File path pattern | Agent group |
|---|---|
| `**/src/main/**`, `**/src/commonMain/**` | prod (3–6 agents) |
| `**/src/test/**`, `**/src/androidTest/**` | test (1 agent) |
| `*.gradle`, `*.toml`, `libs.versions.toml`, root `*.xml` (not `AndroidManifest.xml`) | config (1 agent) |
| `releasenotes*`, `CHANGELOG*`, `*.txt` at root | **skip** |
| anything else | **skip and log** |

State total routed file count upfront: "N files to review (X prod, Y test, Z config)."

---

## Step 3: Group Selection Then Spawn

Patterns are grouped into 6 themed review agents for prod files. **Always read all pattern files for each group before spawning** — inject their full text into the agent prompt.

### Agent Groups

**Always-run (3 — spawn for every prod file):**

| Group | Patterns covered |
|---|---|
| `code-quality` | naming, readability, code-smell, comments |
| `design` | oop, solid, design-patterns |
| `safety` | bug-detection, error-handling, null-safety, blast-radius |

**Conditional (spawn only when triggers match in the diff):**

| Group | Patterns covered | Trigger keywords in diff |
|---|---|---|
| `runtime` | concurrency, performance, scalability, immutability | `suspend`, `Flow`, `Channel`, `launch`, `async`, `Dispatchers`, `coroutineScope`, `var ` (shared state) |
| `android` | android-lifecycle, android-guidelines, compose | `Activity`, `Fragment`, `@Composable`, `ViewModel`, `onResume`, `onCreate`, `WorkManager`, `repeatOnLifecycle`, `LaunchedEffect` |
| `security-arch` | security, architecture, logging | `Log.`, `Timber.`, `http://`, `SharedPreferences`, `Repository`, `UseCase`, token, secret, password, credential |

State upfront: "Spawning N agents for `<filename>`: always(3) + conditional([groups])."

### Step 3b: Spawn Selected Agents

Read all pattern files for each selected group in parallel, then spawn all selected agents simultaneously — one agent per group. Each agent receives:
1. The file diff (trimmed to `+` lines with hunk context)
2. The TechStackProfile as a structured block
3. All pattern checklists for its group, clearly labelled by sub-pattern name

### Agent Prompt Template

```
You are the <GROUP_NAME> reviewer for a code review. You cover: <list of sub-patterns>.

## Tech Stack
networking: <value>
di: <value>
imageLoading: <value>
testing: <value>
async: <value>
database: <value>
navigation: <value>
serialization: <value>

## Your Pattern Checklists

### <sub-pattern-1>
<full content of ~/.claude/skills/review-pr/patterns/<sub-pattern-1>.md>

### <sub-pattern-2>
<full content of ~/.claude/skills/review-pr/patterns/<sub-pattern-2>.md>

... (repeat for each sub-pattern in the group)

## Instructions
Review ONLY the diff below. Report findings that match any checklist above.
For each finding:
  - path: <file path>
  - line: <line number from + side of hunk header>
  - severity: blocker | non-blocking | nit
  - agent: <sub-pattern name that owns this finding, e.g. "null-safety" not "safety">
  - finding: <concise description>

If no findings, respond with exactly: NO_FINDINGS

Do NOT report findings outside your checklist scopes.

## Diff
<file diff>
```

### Prod file agents (3–6, based on trigger matching):
code-quality, design, safety (always) + runtime, android, security-arch (conditional)

### Test file agent (1 per test file — always):
Merge test-coverage and test-patterns into a single `test` agent using both pattern files.

### Config agent (1 per config file):
versions

---

## Step 4a: Calibration Mode (default)

After all agents for a file complete, present:

```
── <filename> ──────────────────────────────────────────

DIFF (show all hunk content — context lines without prefix, added lines with +, removed lines with -):
- <line N>: <removed code>
  <line N>: <context code>
+ <line N>: <added code>
  ...

FINDINGS:
  [<agent>] line <N> — <finding>  [<severity>]
  ...

> raise / skip <N> / edit <N> "<text>" / next
  or describe what was missed: "you missed X on line Y"
```

**STOP here. Present the block above and wait for user response before doing anything else.**

Feedback handling:
- `raise` or `raise all` → post all findings for this file as inline GitHub comments (use Step 5 format)
- `skip <N>` → discard finding N, ask "should I weaken this pattern?" (y/n)
- `edit <N> "<text>"` → post finding N with the provided text instead
- `next` → move to next file without posting any comments
- Natural language miss:
  1. Post the described finding as an inline comment immediately
  2. Determine which agent owns this pattern (ask user if not clear)
  3. Append a new rule to `~/.claude/skills/review-pr/patterns/<agent>.md`
  4. Confirm: "Added to <agent>.md — will catch this next time."

Repeat for each file. After all files: go to Step 5.

---

## Step 4b: Autopilot Mode (--auto)

**When intent is ambiguous** (e.g. a variable name that could mean "attempted" or "succeeded", a behavior change that could be intentional or a bug), do NOT guess — post an inline question comment on GitHub asking the author to clarify:

```
[question] Is `firstFetchAttempted` intended to retry on failure (flag means "succeeded"),
or load-once regardless of failure (flag means "was attempted")? The current placement
inside `.onSuccess {}` means failures trigger a retry on every subsequent call.
```

Only skip or raise a finding after the intent is clear. In autopilot mode, ambiguous findings become questions posted inline — they do not block the verdict unless they reveal a definite bug.

Collect all findings from all agents across all files. Post in one or a few API calls:

```bash
gh api repos/<owner>/<repo>/pulls/<number>/reviews \
  --method POST \
  --input - <<'EOF'
{
  "body": "<summary of all findings grouped by category>",
  "event": "COMMENT",
  "comments": [
    { "path": "<file>", "line": <N>, "side": "RIGHT", "body": "[<agent>] <finding>" }
  ]
}
EOF
```

Then go to Step 5.

---

## Step 5: Verdict

Verdict logic:
- Any `blocker` finding → REQUEST_CHANGES
- Only `non-blocking`/`nit` findings → APPROVE with findings noted in body
- No findings → APPROVE

```bash
# REQUEST_CHANGES (blockers present)
gh api repos/<owner>/<repo>/pulls/<number>/reviews \
  --method POST \
  --input - <<'EOF'
{
  "body": "**Blockers** (must fix)\n1. <finding>\n\n**Non-blocking**\n- <finding>\n\n**Nits**\n- <finding>",
  "event": "REQUEST_CHANGES"
}
EOF

# APPROVE (no blockers)
gh api repos/<owner>/<repo>/pulls/<number>/reviews \
  --method POST \
  --input - <<'EOF'
{
  "body": "**Non-blocking**\n- <finding>\n\n**Nits**\n- <finding>",
  "event": "APPROVE"
}
EOF
```

---

## Common Mistakes

- `--field comments=...` → GitHub rejects array as string. Always use `--input -` with raw JSON.
- Wrong line number → count from `+` side of hunk header (e.g. `@@ -34,11 +36,28 @@` → new file starts at line 36).
- Reviewing releasenotes/changelogs → skip by default.
- Guessing tech stack → always detect from build files in Step 0.
- Moving to next file without waiting (calibration mode) → always pause after findings.
- Spawning groups sequentially → spawn all selected groups for a file simultaneously in one message.
- Labelling findings with group name → always use the sub-pattern name (e.g. `null-safety`, not `safety`).
- Skipping trigger check → always scan the diff for conditional group keywords before deciding which groups to spawn.

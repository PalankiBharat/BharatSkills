---
name: review-pr
description: Use when reviewing a GitHub PR — spawns 25 focused single-responsibility agents in parallel by file type, aggregates findings, supports calibration (human in loop) and autopilot (--auto) modes.
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
| `**/src/main/**`, `**/src/commonMain/**` | prod (21 agents) |
| `**/src/test/**`, `**/src/androidTest/**` | test (2 agents) |
| `*.gradle`, `*.toml`, `libs.versions.toml`, root `*.xml` (not `AndroidManifest.xml`) | config (1 agent) |
| `releasenotes*`, `CHANGELOG*`, `*.txt` at root | **skip** |
| anything else | **skip and log** |

State total routed file count upfront: "N files to review (X prod, Y test, Z config)."

---

## Step 3: Triage Then Spawn

### Step 3a: Decider Agent (which agents to spawn)

Spawn one lightweight decider agent per file **before** any review agents. The decider reads the full diff and reasons about which specialized agents are genuinely needed — not just keyword presence, but whether the concerns actually apply to this code.

**Core agents — always spawn, no decision needed (7):**
`naming`, `oop`, `readability`, `code-smell`, `bug-detection`, `solid`, `design-patterns`

**Decider agent prompt:**
```
Read the diff below line by line. Decide which specialized review agents to spawn beyond the 7 core agents (naming, oop, readability, code-smell, bug-detection, solid, design-patterns — always spawned separately).

For each specialized agent, spawn it only if the diff contains code where those concerns GENUINELY apply — not just because a keyword appears. Examples of when NOT to spawn:
- Don't spawn concurrency just because `suspend` appears on a trivial delegating function
- Don't spawn performance just because `.map {}` appears in a one-shot setup path
- Don't spawn comments just because `//` appears in an import block
- Don't spawn blast-radius for a private helper nobody calls

## Specialized agents and what they cover:
- error-handling: try/catch blocks, when/else exhaustiveness on sealed classes or enums, exception swallowing, CancellationException propagation
- null-safety: force-unwrap (!!), unsafe collection access (.first() / [0] without guard), nullable returned but used without check
- concurrency: coroutines (launch/async/Flow/Channel), shared mutable state across coroutines, Dispatchers, suspend functions with side effects
- logging: Log.* / Timber.* calls, TAG consistency, PII in log messages, log level appropriateness
- immutability: var fields that could be val, MutableList/MutableMap exposed, state mutation patterns
- performance: N+1 queries, allocations in hot paths (onDraw / mapIndexed on every frame), wrong data structure for access pattern
- comments: non-obvious WHY comments present or missing; misleading/outdated docstrings
- blast-radius: public/internal API signature or semantic changes, silent failure regressions (throws → returns default), data loss paths
- security: credentials/tokens hardcoded, PII in logs, unencrypted SharedPreferences, WebView JS, exported components, cleartext URLs
- architecture: layer boundary violations (network calls in UI, business logic in data layer), Repository/ViewModel dependency direction
- scalability: pagination, caching strategy, debounce/throttle for user input, SSOT violations
- compose: @Composable, remember/derivedStateOf, side-effect APIs (LaunchedEffect/DisposableEffect), collectAsState lifecycle, LazyColumn keys
- android-lifecycle: Activity/Fragment lifecycle, wrong coroutine scope, listener registration without cleanup, StateFlow without repeatOnLifecycle
- android-guidelines: Android framework usage patterns, WorkManager, DataStore, Ktor networking, DI scoping, permissions, notifications

## Output format — respond with ONLY a JSON array, no explanation:
["error-handling", "null-safety"]
```

The decider output drives Step 3b. State the result: "Spawning N agents for `<filename>`: core(7) + [decider output]"

### Step 3b: Spawn Selected Agents

For each file group, spawn all selected agents simultaneously. Each agent receives:
1. The file diff (trimmed to `+` lines with hunk context)
2. The TechStackProfile as a structured block
3. The content of its dedicated pattern file — **read the file with the Read tool first, then inject its full text into the prompt**

### Agent Prompt Template

```
You are the <AGENT_NAME> for a code review. Your single job: <JOB>.

## Tech Stack
networking: <value>
di: <value>
imageLoading: <value>
testing: <value>
async: <value>
database: <value>
navigation: <value>
serialization: <value>

## Your Pattern Checklist
<full content of ~/.claude/skills/review-pr/patterns/<agent>.md>

## Instructions
Review ONLY the diff below. Report findings that match your checklist.
For each finding:
  - path: <file path>
  - line: <line number from + side of hunk header>
  - severity: blocker | non-blocking | nit
  - agent: <your agent name>
  - finding: <concise description>

If no findings, respond with exactly: NO_FINDINGS

Do NOT report findings outside your checklist scope.

## Diff
<file diff>
```

### Prod file agents (up to 21, selected by triage in Step 3a):
naming, oop, solid, error-handling, design-patterns, code-smell, comments,
security, concurrency, performance, scalability, null-safety, architecture,
immutability, readability, logging, android-lifecycle, compose,
android-guidelines, bug-detection, blast-radius

### Test file agents (spawn both in parallel per test file):
test-coverage, test-patterns

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
- Spawning agents sequentially → spawn all agents for a file simultaneously in one message.

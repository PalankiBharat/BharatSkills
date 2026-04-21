# Verify Protocol

Unified 3-layer verification for migrated KMM modules. Replaces the old audit mode.
Invoked via `/kmm-workflow verify <module>`.

### Team Structure

Verify mode uses a `verify-team` created by the orchestrator:
- **Orchestrator (Opus):** Creates team, handles fix-or-escalate decisions, performs 3-build comparison (Vision), generates unified report
- **"verifier" teammate (Sonnet, tmux pane):** Owns all 3 layers, fires sub-agents per layer, collects results, reports summaries to orchestrator
- **Sub-agents (Sonnet/Haiku, in-process):** Each handles one check or one device E2E

Layers execute in order (1 → 2 → 3) enforced by task dependencies. Within each layer, sub-agents run in parallel.

## Entry Point

On `verify` invocation:
1. Ask: which module? which branch?
2. Detect gameplan state (see Gameplan Detection below)
3. Create worktree for verification work

## Gameplan Detection

Check `~/dev/gameplans/<module-name>/` for an existing gameplan.

### Path A: Gameplan exists with v6 fields (19 fields in migration-guide.md)

Verify by checking if migration-guide.md contains `Platform APIs:` and `Expected tests:` fields.

→ Skip directly to Layer 1 (run verification pipeline directly).

### Path B: Gameplan exists with pre-v6 fields (9 fields)

Verify by checking if migration-guide.md exists but lacks `Platform APIs:` field.

→ Proceed to Step 2a (upgrade gameplan), then run verification pipeline.

### Path C: No gameplan exists

→ Proceed to Step 2b (reverse-engineer gameplan), then run verification pipeline.

---

## Step 2a: Upgrade Existing Gameplan to v6

For each file entry in the existing migration-guide.md, enrich with the 6 missing fields by reading the actual migrated source code:

1. **Platform APIs** — grep the migrated file in commonMain for any remaining Android-only APIs (android.util.Log, System.currentTimeMillis, java.util.Date, Dispatchers.IO without import, etc.). List any found + their expected replacements.
2. **Breaking changes** — diff the original Android file (if still in git history) against the migrated file. Note any public API signature changes.
3. **Callbacks** — scan the migrated file for callback/lambda parameters. For composables: find every `() -> Unit` parameter. Trace each to its call site.
4. **Expected tests** — count public methods in the migrated file. Set minimum = 1 per public method.
5. **Serialization** — scan for @Serializable, @SerialName, JsonElement usage. Note wire format requirements.
6. **Decisions** — read findings.md if it exists. Extract any decision rationale. If not available, mark as "pre-v6 migration, rationale not recorded."

Also generate:
- `parity-check.sh` if it doesn't exist (using the module's actual file paths and structure)
- Decisions section in findings.md if it doesn't exist

→ Proceed to Layer 1.

---

## Step 2b: Reverse-Engineer Gameplan from Code

Create `~/dev/gameplans/<module-name>/` with:

1. **Identify migrated files** — scan `shared/src/commonMain/` for the module. List every file that was migrated.
2. **Identify consumers** — grep the Android and iOS app code for imports from the shared module. Map which consumers use which shared files.
3. **Build migration-guide.md** — one entry per migrated file, all 19 fields populated using the same enrichment logic as Step 2a (infer from code, git history, and import statements)
4. **Write PLAN.md** — verify mode header, module context, verification-only phases
5. **Write findings.md** — empty Decisions table, Known Fixes from git blame if available
6. **Generate parity-check.sh** — from actual module structure

→ Proceed to Layer 1.

---

## Layer 1: Static Checks (no devices needed)

Fast, deterministic checks that catch structural issues.

### Verify-Team Parallel Dispatch

The orchestrator creates a verify-team. The "verifier" team member (Sonnet, tmux pane) owns all 3 layers and fires sub-agents per layer.

**Layer 1 — fire 3 sub-agents simultaneously:**

| Sub-agent | Model | Checks | Output |
|-----------|-------|--------|--------|
| static-scripts | Haiku | 1.2 (parity-check.sh) + 1.4 (phase checklists) | PASS/FAIL per check |
| auditor | Sonnet | 1.1 (anti-pattern scan) — can fire its own sub-agents per module | AUDIT_COMPLETE with severity counts |
| parity-reviewer | Haiku | 1.3 (cross-platform parity) + 1.5 (behavioral diff) | Checklist results + diff findings |

All 3 run in parallel. The verifier team member collects results from all 3 before reporting Layer 1 output.

### 1.1 Anti-Pattern Scan
Dispatch auditor agent (agent-prompts/auditor.md) — scans for:
- CRITICAL: runBlocking on main, TODO() in production, type casts, hardcoded secrets, connections in `LaunchedEffect(Unit)` or `onCreate` without lifecycle-aware reconnect (if original had lifecycle handling and migration removed it)
- HIGH: leaked CoroutineScopes, force unwraps, redundant Flow wrappers, wrong Koin scopes, connections in `LaunchedEffect(Unit)` or `onCreate` without lifecycle-aware reconnect (if original had same pattern — PRE-EXISTING)
- MEDIUM: dual base classes, duplicated patterns, hardcoded strings
Auto-fix CRITICAL and straightforward HIGH. Escalate non-trivial items.

### 1.2 parity-check.sh
Run the project's generated parity-check.sh (10 static checks). All must pass.

### 1.3 Cross-Platform Parity
Run the full checklist from `references/cross-platform-parity.md` (SDK init, routing, strings, callbacks, session persistence).

### 1.4 Phase Checklists
Run Phase 4 + Phase 5 checklists from `references/phase-checklists.md`. All items must pass.
Skip items that are build/commit related (those are for active migration, not verification).

### 1.5 Behavioral Diff Review
For each RENAMED or MODIFIED file in the migration diff (`git diff master...HEAD --name-status`):
- Compare old vs new behavior: proto/JSON parsing, date conversions, concurrency model, error handling, dispatch context
- Flag any observable behavioral difference as BUG (logic changes are not pattern violations — anti-pattern scan won't catch them)
- Auto-classify: was the behavioral change intentional (documented in findings.md Decisions section) or accidental?

**Layer 1 output:** `LAYER_1: passed: N/N | blockers: N | high: N`

---

## Layer 2: Completeness Checks (no devices needed)

Code analysis that catches feature gaps. Runs deterministic scripts + AI-powered analysis.

### Layer 2 Parallel Dispatch

**Layer 2 — fire 2 sub-agents simultaneously:**

| Sub-agent | Model | Checks | Output |
|-----------|-------|--------|--------|
| script-runner | Haiku | 2.1 (flow-collector-check.sh) + 2.2 (koin-binding-check.py) | PASS/FAIL per script |
| completeness-auditor | Sonnet | 2.3 (callback completeness trace) + 2.4 (UI branch audit) | Findings with file:line references |

Deterministic scripts (Haiku) run parallel with AI-powered analysis (Sonnet). The verifier team member collects both results before reporting Layer 2 output.

### 2.1 Flow Collector Check (deterministic)
Run `flow-collector-check.sh`:
- Greps shared ViewModels for StateFlow/SharedFlow/Channel declarations
- Greps iOS views for corresponding .task {} / .collect blocks
- Cross-references: every ViewModel emission must have exactly one iOS collector
- Missing collector → BLOCKER (silent feature loss)

### 2.2 Koin Binding Check (deterministic)
Run `koin-binding-check.py`:
- Parses Koin module files for all bindings (single/factory/viewModel)
- Parses constructor-injected classes for required dependencies
- Traces one level of transitive deps
- Missing binding → BLOCKER (runtime crash)

### 2.3 Callback Completeness Trace (AI-powered)
For each onClick/onAction/callback parameter in Android UI code:
- Trace to the shared ViewModel action it invokes
- Verify iOS view has equivalent handler invoking the same action
- Dead-end callback (no-op closure = {} or missing) → BLOCKER

### 2.4 UI Branch Audit (AI-powered)
For every if/when/switch in Android UI that controls visibility/rendering:
- Verify iOS view has equivalent conditional branch
- Missing branch → HIGH (conditional content not rendered on iOS)

**Layer 2 output:** `LAYER_2: passed: N/N | blockers: N | high: N`

---

## Layer 3: Device Testing (needs emulator/simulator)

Runtime verification using appium-mcp.

### Layer 3 Parallel Dispatch

**Layer 3 — fire 2 sub-agents simultaneously (when both devices available):**

| Sub-agent | Model | Device | Checks |
|-----------|-------|--------|--------|
| device-android | Sonnet | Android emulator ($ANDROID_SERIAL) | 3-build comparison (Build 1: master, Build 2: migrated), functional verification |
| device-ios | Sonnet | iOS simulator ($IOS_UDID) | 3-build comparison (Build 3: iOS), functional verification |

Both agents capture screenshots independently. After both complete, the **orchestrator** (not the verifier team member) performs the 3-build cross-platform comparison using Claude Vision — this requires judgment-tier (Opus) analysis.

If only one device is available: run that platform's E2E only. Report the other as skipped.

### 3.0 Environment & Device Selection
Check prerequisites:
- `which appium` → installed?
- `npx appium-mcp@latest --version` → appium-mcp available?
- `appium driver list --installed` → uiautomator2, xcuitest present?
If any missing → **skip Layer 3 with explicit warning**, report Layers 1-2 results only.

**Device targeting (mandatory):**
1. List available devices: `adb devices` (Android), `xcrun simctl list devices available` (iOS)
2. Present the list to the user — ask which device(s) to target
3. Use ONLY the selected device(s) for all subsequent appium-mcp sessions
4. Never assume physical vs emulator — always ask

### 3.0.1 Manual Test Checklist Generation
Before device testing begins, auto-generate a structured manual test checklist:
1. Extract breaking changes from migration-guide.md
2. Extract SDK API surface changes from findings.md
3. Present the checklist to the user — ask which items they will test manually vs which automation should cover
4. Exclude user-claimed items from automated verification to avoid redundant work

### 3.1 Session Setup
Boot emulator and/or simulator, create appium-mcp sessions (Android + iOS), record device identifiers per `references/appium-mcp-testing.md` Section 3.

### 3.2 3-Build Comparison
Run 3-build comparison per `references/appium-mcp-testing.md` Section 4.

### 3.3 Functional Verification
Run per-screen functional verification per `references/appium-mcp-testing.md` Section 5.

### 3.4 Cleanup
- Delete all appium-mcp sessions (`delete_session`)

**Layer 3 output:** `LAYER_3: screens_passed: N/N | regressions: N | parity_gaps: N | skipped: true/false`

---

## Unified Report

After all layers complete, **auto-classify each finding** before presenting:
1. For each finding, run `git show master:<path>` to check if the issue existed pre-migration
2. Classify as:
   - **NEW** — introduced by the migration (blocks merge)
   - **PRE-EXISTING** — existed before migration (document, don't block)
   - **INTENTIONAL** — deliberate change documented in findings.md Decisions section (document rationale)

Present findings grouped by severity, with classification on each:

```
## Verify Report: <module>

### Summary
- Layer 1 (Static): X/Y passed
- Layer 2 (Completeness): X/Y passed
- Layer 3 (Device): X/Y screens passed [or SKIPPED — devices unavailable]

### BLOCKERS (must fix before handoff)
- [NEW/PRE-EXISTING] file:line — description — suggested fix

### HIGH (should fix before handoff)
- [NEW/PRE-EXISTING] file:line — description

### MEDIUM (consider fixing)
- [NEW/PRE-EXISTING/INTENTIONAL] file:line — description

### PASS
- [list what passed]
```

Only NEW findings block merge. PRE-EXISTING findings are documented for future cleanup.

Wait for user approval before proceeding to fixes.

---

## Fix Protocol (invoked ONLY after user approval)

Verify mode's primary output is the findings report. Fixing is a separate phase the orchestrator enters ONLY when the user explicitly says "fix" (or equivalent) after reviewing the report. The verifier agent itself never writes code — it reports. If the user approves fixes, the orchestrator dispatches a fresh fix-team (migrator / debugger sub-agents) and follows this protocol:

1. Read master (original Android code) — `git show master:<path>` to check original patterns (dispatchers, concurrency, error handling)
2. Read current migrated implementation
3. Identify the specific delta — fix must match original behavioral intent, not just compile
4. Fix the root cause (e.g., for Dispatchers.IO in commonMain: `import kotlinx.coroutines.IO`, not a custom wrapper)
5. Re-run the failing check to verify

Max 3 fix attempts per finding. After 3 failures → REQUIRES_APPROVAL.

After all fixes: re-run ALL layers (not just the failing ones) to catch regressions.

Commit all fixes in one commit:
```
fix: resolve N verify issues in <module-name>

<one-line per issue>
```

---

## Rules

- Verify mode creates a worktree for fixes (never edit on the base branch directly)
- All agent fixes follow understand-first protocol — no blind patching
- parity-check.sh must pass clean before committing
- If verify finds issues that require re-migration of a file, escalate to user — verify mode fixes wiring/parity gaps, not fundamental migration errors
- Never skip a layer (except Layer 3 when devices unavailable — report as skipped, not passed)
- Run layers in order: 1 → 2 → 3
- If Layer 1 has BLOCKERs, still run Layer 2 and 3 — report all findings

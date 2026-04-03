# Audit Protocol

Use this when a module is already migrated but has issues. Audit runs the full v6.0.0 verification pipeline against existing code and fixes gaps.

## Invocation

```
/kmm-workflow audit <module-name>
```

Ask ONE question: "Which branch has the migrated code?" (or auto-detect if worktree exists in PLAN.md).

---

## Step 1: Detect Gameplan State

Check `~/dev/gameplans/<module-name>/` for an existing gameplan.

### Path A: Gameplan exists with v6 fields (15 fields in migration-guide.md)

Verify by checking if migration-guide.md contains `Platform APIs:` and `Expected tests:` fields.

→ Skip to Step 3 (run verification pipeline directly).

### Path B: Gameplan exists with pre-v6 fields (9 fields)

Verify by checking if migration-guide.md exists but lacks `Platform APIs:` field.

→ Proceed to Step 2a (upgrade gameplan).

### Path C: No gameplan exists

→ Proceed to Step 2b (reverse-engineer gameplan).

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

→ Proceed to Step 3.

---

## Step 2b: Reverse-Engineer Gameplan from Code

Create `~/dev/gameplans/<module-name>/` with:

1. **Identify migrated files** — scan `shared/src/commonMain/` for the module. List every file that was migrated.
2. **Identify consumers** — grep the Android and iOS app code for imports from the shared module. Map which consumers use which shared files.
3. **Build migration-guide.md** — one entry per migrated file, all 15 fields populated by reading the current code:
   - Source: reconstruct from git history or package structure
   - Target: current path in commonMain
   - Classification: infer from file type and location
   - Public API: read current public methods
   - Platform APIs: grep for remaining Android-only APIs
   - Swaps: infer from import statements (Ktor = was Retrofit, Koin = was Hilt, etc.)
   - Breaking changes: diff against git history if available
   - Callbacks: scan for lambda params
   - Expected tests: count public methods
   - Serialization: scan for serialization annotations
   - expect/actual: check if file has expect/actual declarations
   - Migrate after: infer from import dependencies
   - Consumers: from Step 2
   - Rules: "none (audit mode)"
   - Decisions: "pre-v6 migration, rationale not recorded"
4. **Write PLAN.md** — audit mode header, module context, verification-only phases
5. **Write findings.md** — empty Decisions table, Known Fixes from git blame if available
6. **Generate parity-check.sh** — from actual module structure

→ Proceed to Step 3.

---

## Step 3: Run Verification Pipeline

Execute in order. Do NOT skip any layer.

### Layer 0: parity-check.sh (static analysis)
Run `<gameplan-dir>/parity-check.sh`. Record all failures.

### Layer 1: Cross-Platform Parity Checklist
Read `references/cross-platform-parity.md`. For each item:
- SDK init parameters: compare Android vs iOS initialization calls
- Lifecycle listeners: compare registrations on both platforms
- Session persistence: verify all fields written on both platforms
- Asset parity: verify all resources exist on both platforms
- Info.plist keys: verify all referenced keys exist
- Route mapping: verify all sealed class variants are explicitly mapped

### Layer 2: Phase Checklists (4 + 5)
Read `references/phase-checklists.md`. Run the Phase 4 and Phase 5 checklists against the current code state. Skip items that are build/commit related (those are for active migration, not audit).

### Layer 3: Visual/Functional (optional, user decides)
Ask: "Run Appium visual verification? (takes ~15-30 min)"
If yes → follow `references/appium-protocol.md`

---

## Step 4: Present Findings

Group by severity:

```
Audit of login-module: N issues found

BLOCKER (N):
| # | File | Issue | Fix |
|---|------|-------|-----|

HIGH (N):
| # | File | Issue | Fix |

MEDIUM (N):
| # | File | Issue | Fix |

Fix all? Or pick specific ones?
```

Wait for user approval.

---

## Step 5: Fix

For each approved fix:
1. Dispatch agent with `references/agent-protocol.md` (understand-first protocol)
2. Agent reads master/original → reads migrated → identifies root cause → fixes
3. After fix: rerun the specific check that failed → verify it passes
4. After all fixes: rerun parity-check.sh to confirm clean

Commit all fixes in one commit:
```
fix: resolve N audit issues in <module-name>

<one-line per issue>
```

---

## Rules

- Audit mode creates a worktree for fixes (never edit on the base branch directly)
- All agent fixes follow understand-first protocol — no blind patching
- parity-check.sh must pass clean before committing
- If audit finds issues that require re-migration of a file, escalate to user — audit mode fixes wiring/parity gaps, not fundamental migration errors

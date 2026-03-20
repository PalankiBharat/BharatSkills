---
name: qa-autopilot
description: Automated QA testing skill that analyzes git branch changes, generates comprehensive test cases like a senior QA engineer, and executes them on a real Android device using the phone-driver skill. Use this skill whenever the user says "test my changes", "run QA", "qa autopilot", "test my branch", "generate test cases for my changes", "run tests on phone", "what should I test", "QA my PR", "regression test", "test the diff", "check performance", "performance test", or any request to analyze code changes and verify them on a real device. Also triggers when the user wants to generate a QA report, check for regressions, detect performance issues like jank or recomposition bloat, or validate a feature branch before merging. Requires the phone-driver skill to be installed for on-device execution. Works without phone-driver too — in that case it generates the test plan only.
---

# QA Autopilot — Branch Change Analysis → Test Generation → On-Device Execution

You are a senior QA engineer with deep Android domain expertise. You analyze code changes in the current git branch, understand every feature affected, generate exhaustive test cases (happy path, edge cases, regression, boundary), and then drive a real Android phone to execute each test — recording pass/fail results in a markdown report.

## Prerequisites

- **Git repo**: Must be inside a git repository with changes vs `master`
- **Phone Driver** (optional but recommended): The `phone-driver` Claude Code command must be installed for on-device test execution. Without it, the skill generates the test plan only.
- **Android device**: Connected via USB with ADB debugging enabled (required for execution)

## Workflow Overview

```
┌─────────────┐    ┌──────────────┐    ┌───────────────┐    ┌──────────────┐
│  Git Diff    │───▶│  Analyze &   │───▶│  Generate     │───▶│  Execute on  │
│  Extraction  │    │  Understand  │    │  Test Cases   │    │  Device      │
└─────────────┘    └──────────────┘    └───────────────┘    └──────────────┘
                                                                    │
                                                             ┌──────▼──────┐
                                                             │  QA Report  │
                                                             │  (pass/fail)│
                                                             └─────────────┘
```

## Phase 0: Environment Setup

Run the git analyzer script to extract the full change context:

```bash
bash /path/to/qa-autopilot/scripts/git-analyzer.sh
```

This outputs structured JSON with: changed files, diff hunks, affected modules, new/modified functions, and UI-related changes.

If the script is not available (e.g., running in Claude.ai), manually run:

```bash
# Get the diff against master
git diff master...HEAD --name-status
git diff master...HEAD --stat
git diff master...HEAD
```

Also gather project context:

```bash
# Understand the project structure
find . -name "AndroidManifest.xml" -not -path "*/build/*" | head -5
find . -name "*.kt" -path "*/ui/*" -not -path "*/build/*" | head -30
find . -name "*.kt" -path "*/feature/*" -not -path "*/build/*" | head -30
```

## Phase 1: Deep Change Analysis

Read `references/change-analysis.md` for the full analysis framework.

For every changed file, understand:

1. **What layer is this?** — UI (Composable/Fragment/Activity), ViewModel, UseCase, Repository, Data/Model, Navigation, DI
2. **What feature does it belong to?** — Map file paths to features using package structure
3. **What is the intent of the change?** — New feature, bug fix, refactor, UI tweak, data model change
4. **What's the blast radius?** — Which other features consume the changed code? Trace dependencies UP from the change.

### Dependency Tracing

For each changed file, trace its consumers:

```bash
# Find who imports/uses this changed class or function
grep -rn "import.*ChangedClassName" --include="*.kt" app/src/
grep -rn "ChangedClassName" --include="*.kt" app/src/ | grep -v "import"
```

Build a **change impact map**:

```
Changed: OrderRepository.kt (data layer)
  └─ Used by: PlaceOrderUseCase.kt (domain)
       └─ Used by: OrderEntryViewModel.kt (presentation)
            └─ Used by: OrderEntryScreen.kt (UI) ← MUST TEST
            └─ Used by: OrderModifyScreen.kt (UI) ← MUST TEST
       └─ Used by: ScalperViewModel.kt (presentation)
            └─ Used by: ScalperScreen.kt (UI) ← MUST TEST
```

## Phase 2: Test Case Generation

Read `references/test-generation.md` for the complete test generation framework.

Think like a QA engineer who has been burned before. For every affected screen/feature, generate test cases across these dimensions:

### Test Categories (generate ALL that apply)

1. **Happy Path** — The golden flow works exactly as designed
2. **Boundary Values** — Min, max, zero, empty, one-off limits
3. **Error States** — Network failure, API error, invalid input, timeout
4. **State Transitions** — Loading → Success, Loading → Error, Empty → Populated
5. **Interruptions** — Back press, app backgrounded, rotation, incoming call
6. **Regression** — Existing flows that TOUCH the changed code still work
7. **Data Edge Cases** — Null fields, missing optional data, very long strings, special characters
8. **Concurrency** — Rapid taps, double-submit, race conditions
9. **Navigation** — Deep links, back stack integrity, screen restoration after process death
10. **Performance** — Screen load time, list scroll jank, memory leaks, ANR, recomposition bloat

### Test Case Format

Each test case MUST follow this structure:

```
### TC-{FEATURE_ID}-{NUMBER}: {Short descriptive title}

**Priority**: P0 (blocker) | P1 (critical) | P2 (major) | P3 (minor)
**Category**: {Happy Path | Boundary | Error | Regression | ...}
**Feature**: {Feature name}
**Screen**: {Screen name}
**Precondition**: {What state the app must be in before starting}

**Steps**:
1. {Action step - written as phone-driver compatible instructions}
2. {Action step}
3. {Action step}

**Expected Result**: {What should happen - be specific and observable}

**Phone Driver Commands** (auto-generated):
- `launch "AppName"`
- `tap-on "ElementText"`
- `verify-text "Expected text on screen"`
```

### Prioritization Rules

- **P0**: Changes to core business logic, payment flows, data persistence, auth
- **P1**: Changes to primary user flows, navigation, state management
- **P2**: Changes to secondary flows, edge cases in UI, error handling
- **P3**: Cosmetic changes, text updates, minor UI adjustments

## Phase 3: Test Execution via Phone Driver

Read `references/fast-execution.md` for the compiled fast execution pipeline.
Read `references/phone-driver-bridge.md` for the fallback natural language interface.

**Default: Fast compiled execution (10-20x faster than interpreted mode)**

### Fast Execution Pipeline

1. **Generate test_cases.json** — During Phase 2, output test cases in both human-readable AND machine-readable JSON format. The JSON follows the schema in `references/fast-execution.md`.

2. **Compile** — Run the test compiler to resolve element coordinates from phone-driver memory:
   ```bash
   python3 scripts/test-compiler.py compile test_cases.json compiled/ \
       --memory ~/.claude/phonedriver/memory.json \
       --device-key "$(~/.claude/phonedriver/scripts/adb-helpers.sh devicekey)"
   ```

3. **Handle unresolved elements** — If the compiler reports unresolved steps (elements not in phone-driver's memory), do a discovery pass first:
   ```
   /phone-driver "Open the app and navigate through each affected screen so I can learn the element positions"
   ```
   Then recompile.

4. **Execute** — Run the orchestrator which pushes scripts to the device and runs them natively:
   ```bash
   bash scripts/fast-test-orchestrator.sh compiled/
   ```

5. **Verify** — Read the checkpoint screenshots and execution logs. For each checkpoint:
   - Read the screenshot image to visually verify the screen state
   - Parse the UI dump XML to check for expected text/elements
   - Check the execution log for timeouts or errors
   - Determine PASS/FAIL

### Why Fast Mode Works

The current phone-driver does 2x `uiautomator dump` per tap (~3s) plus `sleep 1.5`. Fast mode eliminates both:
- **Pre-resolved coordinates** — No UI dump needed to find where to tap
- **`wait_idle` instead of `sleep`** — Uses `dumpsys window animator` (~50ms) to detect when the UI has actually settled, instead of hardcoded 1.5s sleep
- **Checkpoints only at verification points** — One `uiautomator dump` per verification instead of two per action
- **On-device execution** — Zero host-device round-trips between actions

Result: A 10-step test goes from ~54s to ~3s.

### Fallback: Natural Language Mode

For tests that can't be fully compiled (all elements unresolved, dynamic content, complex conditional flows), fall back to phone-driver's natural language mode:

```bash
# Example: Execute a test case
/phone-driver "Open the app, navigate to Order Entry screen, enter quantity 0, tap Place Order, verify error message 'Quantity must be greater than 0' appears"
```

### Execution Strategy

1. **Group by screen** — Minimize navigation overhead. Run all tests for Screen A, then Screen B.
2. **P0 first** — Execute in priority order. If P0 fails, flag immediately.
3. **Screenshot on failure** — When expected result doesn't match, capture the screen state.
4. **Reset between tests** — Force-stop and relaunch the app between unrelated test groups to ensure clean state.

### Pass/Fail Determination

After each phone-driver execution:
- **PASS**: Phone driver reports the expected UI state was reached/verified
- **FAIL**: Expected state not found, wrong screen, error displayed, crash
- **BLOCKED**: Couldn't execute (device issue, app crash on launch, missing test data)
- **SKIP**: Requires manual verification (camera, biometrics, physical sensor)

## Phase 4: QA Report Generation

Generate a comprehensive markdown report. Read `references/report-template.md` for the exact format.

Save the report to the project root:

```
qa-report-{branch-name}-{YYYY-MM-DD}.md
```

### Report Structure

```markdown
# QA Report: {Branch Name}
**Date**: {YYYY-MM-DD HH:MM}
**Branch**: {branch name}
**Base**: master
**Commits**: {count} commits, {files changed} files changed
**Executed by**: QA Autopilot + Phone Driver

## Summary
| Status  | Count |
|---------|-------|
| ✅ PASS  | {n}   |
| ❌ FAIL  | {n}   |
| ⚠️ BLOCKED | {n} |
| ⏭️ SKIP  | {n}   |
| **Total** | {n} |

## Change Impact Analysis
{Summary of what changed and what features are affected}

## Test Results

### Feature: {Feature Name}

#### TC-001: {Title}
- **Status**: ✅ PASS | ❌ FAIL
- **Priority**: P0
- **Steps executed**: {brief summary}
- **Result**: {what happened}
- **Evidence**: {screenshot path if failure}
- **Notes**: {any observations}

...

## Regression Risk Assessment
{Which untested areas pose the highest regression risk}

## Recommendations
{What needs manual testing, what should block the merge}
```

## Modes of Operation

### Fast Auto (default — phone-driver + device + memory populated)
Analyzes changes → Generates test JSON → Compiles to native scripts → Executes on device at ~50ms/action → Checkpoints at verification points → Produces report with pass/fail. **10-20x faster than interpreted mode.**

### Interpreted Auto (phone-driver + device, no memory)
Falls back to phone-driver's natural language mode for execution. Slower but works without pre-learned element positions. Use this for first run on a new app, then switch to fast mode once screens are discovered.

### Plan Only (no phone-driver or no device)
Analyzes changes → Generates tests → Produces report with test plan (all marked PENDING)

### Re-run Failed
If a report already exists, re-run only FAIL and BLOCKED tests:
```bash
# User says: "re-run failed tests" or "retry failures"
# → Read existing report, filter for ❌ and ⚠️, execute only those
```

## Key Principles

1. **Think like a QA who has been burned** — What breaks in production? Test THAT.
2. **Trace dependencies ruthlessly** — A change in the data layer means testing EVERY screen that uses it.
3. **Test the boundaries** — The happy path is easy. Edge cases are where bugs live.
4. **Regression is king** — If existing features touch the changed code, they MUST be tested.
5. **Be specific** — "Check that it works" is not a test case. "Verify the order total shows ₹1,234.56 when quantity is 5 and price is ₹246.91" is.
6. **Evidence everything** — Screenshots on failure. Exact error messages. Reproduce steps.

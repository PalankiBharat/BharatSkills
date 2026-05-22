# QA Report Template

## File Naming

```
qa-report-{branch-name}-{YYYY-MM-DD}.md
```

Place the report in the project root directory. If a report already exists for the same branch, append a run number: `qa-report-feature-xyz-2025-06-15-run2.md`

## Full Report Template

```markdown
# QA Report: {Branch Name}

| Field | Value |
|-------|-------|
| **Date** | {YYYY-MM-DD HH:MM IST} |
| **Branch** | `{branch_name}` |
| **Base** | `master` |
| **Commits** | {N} commits |
| **Files Changed** | {N} files ({additions}+, {deletions}-) |
| **Mode** | Full Auto / Plan Only |
| **Device** | {device model, resolution} or N/A |

---

## Executive Summary

{2-3 sentences: What was changed, how many tests were generated, overall pass rate, critical findings}

### Verdict: 🟢 SAFE TO MERGE | 🟡 MERGE WITH CAUTION | 🔴 DO NOT MERGE

{One sentence justification}

---

## Summary

| Status | Count | Percentage |
|--------|-------|------------|
| ✅ PASS | {n} | {%} |
| ❌ FAIL | {n} | {%} |
| ⚠️ BLOCKED | {n} | {%} |
| ⏭️ SKIP | {n} | {%} |
| 📋 PENDING | {n} | {%} |
| **Total** | **{n}** | **100%** |

### Priority Breakdown

| Priority | Total | Pass | Fail | Other |
|----------|-------|------|------|-------|
| P0 (Blocker) | {n} | {n} | {n} | {n} |
| P1 (Critical) | {n} | {n} | {n} | {n} |
| P2 (Major) | {n} | {n} | {n} | {n} |
| P3 (Minor) | {n} | {n} | {n} | {n} |

---

## Change Impact Analysis

### Changed Files

| File | Layer | Feature | Change Type | Risk |
|------|-------|---------|-------------|------|
| {file_path} | {layer} | {feature} | {type} | {🔴🟠🟡🟢} |

### Impact Graph

```
{Changed File}
  └─ {Consumer 1}
       └─ {UI Screen — TESTED}
  └─ {Consumer 2}
       └─ {UI Screen — TESTED}
```

### Features Affected

1. **{Feature Name}** — {brief description of how it's affected}
2. **{Feature Name}** — {brief description}

---

## Test Results

### Feature: {Feature Name}

#### TC-{FID}-001: {Title}
- **Status**: ✅ PASS | ❌ FAIL | ⚠️ BLOCKED | ⏭️ SKIP | 📋 PENDING
- **Priority**: P{0-3}
- **Category**: {Happy Path | Boundary | Error | Regression | ...}
- **Screen**: {screen name}
- **Precondition**: {precondition}
- **Steps**:
  1. {step}
  2. {step}
- **Expected**: {expected result}
- **Actual**: {actual result — filled after execution}
- **Evidence**: {screenshot path or N/A}
- **Notes**: {observations, if any}
- **Maestro Flow**: `.maestro/edge-cases/{branch}/TC-{ID}.yaml`

---

{Repeat for each test case, grouped by feature}

---

## Failed Tests Detail

{Only if there are failures — expanded detail for each}

### ❌ TC-{ID}: {Title}
- **Severity**: {How bad is this?}
- **Expected**: {detailed expected behavior}
- **Actual**: {detailed actual behavior}
- **Screenshot**: `{path}`
- **Reproduction Command**: 
  ```
  /phone-driver "{exact command to reproduce}"
  ```
- **Maestro Flow**: `.maestro/edge-cases/{branch}/TC-{ID}.yaml`
- **Re-run**: `maestro test .maestro/edge-cases/{branch}/TC-{ID}.yaml`
- **Probable Cause**: {analysis of what went wrong based on the diff}
- **Recommendation**: {fix suggestion}

---

## Regression Risk Assessment

### Tested Regressions
{List of existing features that were tested and passed}

### Untested Risk Areas
{List of areas that COULD be affected but were NOT tested, with reasoning}

| Area | Risk Level | Why Not Tested | Recommendation |
|------|-----------|----------------|----------------|
| {area} | {🟠🟡} | {reason} | {manual test / can skip / need test data} |

---

## Performance Findings

### Detected Performance Risks (from diff analysis)

| Risk | File | Severity | Details |
|------|------|----------|---------|
| {risk type} | {file_path} | {🔴🟠🟡} | {what was found and why it's a risk} |

### Performance Test Results

| Test | Screen | Result | Notes |
|------|--------|--------|-------|
| Screen load time | {screen} | {< 2s ✅ / > 2s ❌} | {timing if available} |
| List scroll smoothness | {screen} | {Smooth ✅ / Jank ❌} | {observation} |
| Memory stability | {screen} | {Stable ✅ / Growing ❌} | {observation} |
| ANR check | {screen} | {None ✅ / ANR ❌} | {dialog seen?} |

### Profiler Recommendations
{List of screens/flows that need manual profiling with Android Studio}

- [ ] Attach profiler to {screen} — check GPU rendering bars
- [ ] Heap dump after {flow} — verify no retained fragments/activities
- [ ] CPU trace during {operation} — check for main thread blocking

---

## Recommendations

### Before Merge
{Action items that must be done before merging}

### After Merge
{Things to monitor after deployment}

### Manual Testing Needed
{Tests that require human verification — biometrics, camera, etc.}

---

## Appendix

### Test Execution Log
{Timestamp and duration for each test execution}

### Environment
- Device: {model}
- Android: {version}  
- App version: {version}
- Build type: {debug/release}
```

## Verdict Criteria

### 🟢 SAFE TO MERGE
- All P0 tests pass
- All P1 tests pass
- P2 failures are cosmetic or have known workarounds
- No regression failures

### 🟡 MERGE WITH CAUTION
- All P0 tests pass
- Some P1 failures exist but are minor or edge-case
- Regression tests pass for core flows
- Manual verification needed for some scenarios

### 🔴 DO NOT MERGE
- ANY P0 test fails
- Multiple P1 tests fail
- Regression failures in core flows
- App crash detected
- Data corruption risk identified

## Updating an Existing Report

When re-running tests (e.g., after a fix):

1. Don't overwrite — create a new run: `qa-report-{branch}-{date}-run{N}.md`
2. Reference the previous run in the header
3. Only include re-run tests, not the full suite
4. Update the verdict based on combined results

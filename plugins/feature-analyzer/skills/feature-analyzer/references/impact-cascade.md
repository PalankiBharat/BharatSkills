# Cascading Impact Analysis

When the tech impact analyzer identifies affected features, this skill re-runs Domain + Tech + QA analysis on each affected feature — scoped to the DELTA (only what changes because of the new feature).

## When to trigger

Run this phase when `tech/impact-analyzer.md` identifies features with **High** or **Medium** severity impact.

## Analysis approach

For each affected feature, ask these questions through each lens:

### Domain delta
- Do any business rules for the affected feature change?
- Are there new approval requirements because of this change?
- Are existing domain test cases for this feature still valid?
- Are there new domain test cases needed for the affected feature?

### Tech delta
- What code in the affected feature needs to change?
- Are there new edge cases introduced in the affected feature?
- Do existing unit/integration tests still pass?
- What new tests are needed for the affected feature?
- Does the affected feature's architecture need refactoring to accommodate the change?

### QA delta
- Do existing QA test cases for the affected feature still pass?
- Are there new user-facing test cases needed?
- Are there new UX edge cases introduced?
- Does the affected feature's error handling still work correctly?
- Are there regression scenarios that need to be added?

## Cascade depth

- **Depth 1**: Features directly affected by the primary feature change — ALWAYS analyze
- **Depth 2**: Features affected by Depth 1 changes — analyze if the Depth 1 change is significant (model change, API contract change, shared state change)
- **Depth 3+**: Flag as potential risk but don't deep-analyze — diminishing returns

## Output format

```
## 🔄 Cascading impact analysis

### [Affected Feature Name] (Severity: High)
**Why affected:** [One-line explanation of the dependency]

#### Domain delta
- [ ] [Business rule change needed]
- [ ] [New domain test case for this feature]

#### Tech delta
- [ ] [Code change needed in this feature]
- [ ] [New test needed]
- [ ] [Existing test that may break]

#### QA delta
- [ ] [New user test case]
- [ ] [Regression scenario to verify]

#### Risk assessment
- Regression risk: [High/Medium/Low]
- Effort to update: [High/Medium/Low]
- Can be deferred: [Yes/No — with justification]
```

## Key principle

The cascade analysis should answer: "If I ONLY implement the primary feature and don't touch the affected features, what breaks?" This tells the developer what MUST be done in the same PR/sprint vs what can be deferred.

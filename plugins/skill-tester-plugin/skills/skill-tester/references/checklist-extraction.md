# Checklist Extraction Framework

## How to extract a validation checklist from a skill's own files

### Step 1: Read SKILL.md

Scan for imperative language:
- **MUST / ALWAYS / REQUIRED / MANDATORY** → Hard requirement (FAIL = blocker)
- **SHOULD / RECOMMENDED** → Soft requirement (FAIL = warning)
- **NEVER / DO NOT / NO** → Prohibition (violation = FAIL)
- **Post-flight Check** items → Direct checklist items

### Step 2: Read reference files

Each reference file may contain:
- Rules with before/after examples → The "after" is the expected behavior
- Anti-patterns → The consumer output must NOT exhibit these
- Litmus tests → Questions to ask about the output

### Step 3: Build the checklist

Format each item as:

```
ID: B01 (Behavioral) or M01 (Mechanical)
Rule: <one-sentence description>
Source: <file:line or section name>
Severity: BLOCKER | WARNING
Check: <how to verify — what to look for in the output>
```

### Step 4: Categorize

**Behavioral checks** (B-series) — observable in consumer output:
- Naming conventions applied
- Function size limits respected
- Organizational rules followed
- Error handling patterns used
- Domain language present

**Mechanical checks** (M-series) — observable in infrastructure:
- Prehook fires and injects content
- Reference files are readable
- Version fields are in sync
- Hook script produces valid JSON
- Plugin cache is current

### Step 5: Present to user

Show the checklist as a table. Ask: "Anything to add or remove?"
The user's domain expertise may catch things the skill files don't
explicitly state.

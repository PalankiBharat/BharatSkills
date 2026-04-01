# Migration Retrospective — Self-Improvement Protocol

## When to trigger

Run automatically at these points:
- After Phase 1 (PLAN) is approved — capture planning-phase learnings before /clear
- After all phases complete — capture execution-phase learnings
- On any REQUIRES_APPROVAL that the user had to manually resolve

## What to scan for

### Category A: Decision Framework Gaps
Scan conversation for patterns where the user had to guide a dependency/architecture choice:
- User said "use X instead" or "what about X?" for a library choice
- User corrected an approach ("no, don't do expect/actual, use multiplatform-settings")
- User asked "what makes more sense?" forcing the orchestrator to analyze options it should have proactively recommended

**Output:** New row in `references/dependency-decision-framework.md` with the library, decision, replacement, and rationale.

### Category B: Missing Guardrails
Scan for corrections to code patterns or conventions:
- "don't add Shared prefix"
- "don't use type casting"
- "keep names natural"
- Any pattern correction that applies to ALL future KMM migrations (not project-specific)

**Output:** New rule in SKILL.md Rules section.

### Category C: Process Improvements
Scan for process friction:
- Steps the orchestrator skipped that should be mandatory
- Steps that ran in wrong order
- Quality checks that should have caught issues earlier
- User having to ask for something that should be automatic (e.g., "can we check it for ambiguity")

**Output:** Updated step in the relevant Phase section of SKILL.md.

### Category D: Platform Gotchas
Scan for iOS/Android-specific issues discovered during migration:
- APIs that don't exist in commonMain (discovered at compile time)
- Runtime behavior differences between platforms
- Build configuration surprises

**Output:** New entry in `references/platform-api-gotchas.md` (for APIs not available on Native) or `references/kmm-architecture.md` gotchas section (for architectural/runtime gotchas).

### Category E: Library-Specific Knowledge
New information about KMM library compatibility:
- "mobilenetworkingsdk is already KMM"
- "ObjectBox doesn't support KMM"
- Version-specific features ("coroutines 1.8.0+ has Dispatchers.IO in commonMain")

**Output:** Summary row (library → decision → replacement → rationale) goes in `references/dependency-decision-framework.md`. Full before/after code examples go in `references/dependency-replacements.md`. If both are needed, update both files.

## How to present

After collecting findings, present to user:

```
Migration Retrospective — Learnings from this session

Found N learnings to embed into the skill:

DECISION FRAMEWORK (N):
  1. <library> → <replacement> (<rationale>)
     File: references/dependency-decision-framework.md

GUARDRAILS (N):
  2. <rule description>
     File: SKILL.md → Rules section

PROCESS (N):
  3. <process improvement>
     File: SKILL.md → Phase N

PLATFORM GOTCHAS (N):
  4. <gotcha description>
     File: references/kmm-architecture.md → Gotchas

→ Create GitHub issue with these improvements? (y/n)
```

If user approves, create the issue with full content for each finding (the actual text to add to each file, not just a description).

## Issue format

Title: `[kmm-retro] <project-name>: <N> learnings from migration`

Body contains for each learning:
- **File to modify:** exact path
- **Section:** where in the file
- **Content to add:** the actual markdown/text to insert (copy-pasteable)
- **Rationale:** why this was learned (what went wrong without it)

Labels: `skill:kmm-workflow`, `type:self-improvement`, `session:<date>`

## What NOT to capture

- Project-specific decisions (base URLs, artifact names, branch names)
- One-off bugs that were fixed during the session
- User preferences that are already in CLAUDE.md (like "no type casting")
- Anything already in the skill's reference files

# Migration Retrospective — Self-Improvement Protocol

## When to trigger

Run **automatically** at these points — do NOT wait for the user to ask:
- After Phase 1 (PLAN) is approved — capture planning-phase learnings before /clear
- After Phase 3 (SHARED CODE MIGRATION) completes — capture execution-phase learnings before /clear
- After all phases complete — capture execution-phase learnings
- On any REQUIRES_APPROVAL that the user had to manually resolve

The retrospective MUST complete BEFORE the orchestrator instructs `/clear`. Context is erased on clear — if the retrospective hasn't run, all session learnings are permanently lost.

## What to scan for

### Source material
Scan TWO sources for learnings:
1. **Conversation history** — corrections, surprises, workarounds discovered during the session
2. **findings.md** — if the gameplan has a `findings.md`, read it for research notes, debug logs, and workarounds that contain reusable learnings

Cross-reference all findings against existing skill files AND against each other to avoid duplicate learnings within the same retrospective.

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

## Execution (autonomous)

After collecting findings:

1. **Cross-reference** against existing skill reference files — drop any learning already captured
2. **Cross-reference** findings against each other — merge duplicates within the same retrospective
3. **Check existing open issues** — `gh issue list --state open --label "skill:kmm-workflow" --label "type:self-improvement" --json number,title,body`
4. **For each learning:**
   - If an existing open issue covers the same file/topic → `gh issue comment <number> --body "<new content>"`
   - Otherwise → create a new issue (format below)
5. **Summarize** what was done:

```
Retrospective complete — N learnings processed:

| # | Learning | Action | Issue |
|---|----------|--------|-------|
| 1 | Koin module order NPE | Created | #45 |
| 2 | WDA version mismatch | Commented on | #43 |
...

Review the issues above and modify if needed.
```

The user does NOT need to approve individual findings or the issue creation. The retrospective runs end-to-end autonomously. The user reviews the summary and can edit issues afterward if needed.

## Skill-Worthiness Gate

Before adding any learning to the skill, score it:

| Criterion | Points |
|-----------|--------|
| Specific to KMM migration (not generic programming) | +30 |
| Non-obvious (would surprise a senior KMM developer) | +25 |
| Hard-won (required debugging, caused a real failure) | +25 |
| Not already covered by existing skill rules | +20 |
| Generic programming advice ("use error handling") | -30 |
| Already in platform-api-gotchas.md or similar reference | -20 |

**Threshold: 70 points.** Below 70 → skip or merge into an existing rule. Above 70 → add as a new entry.

The goal is to keep the skill sharp, not long. Every addition must earn its place.

## Lean Output Format

Retrospective findings MUST use this structured format (not verbose prose):

```
Finding: {
  category: A|B|C|D|E,
  target_file: <which skill file should change>,
  existing_rule: <quote the existing rule to update, or "none" if new>,
  proposed_change: <1-line description of what to change>,
  rationale: <1-line why this matters>
}
```

When creating GitHub issues, group findings by target_file. Each issue should be actionable by the Improve mode — classify, find home, rewrite to absorb.

## Consolidation Mandate

The Improve mode (invoked via `/kmm-workflow improve`) applies retrospective learnings with these rules:

1. **NEVER append** a new bullet point to an existing list. Find the existing rule that covers this area and REWRITE it to absorb the learning.
2. **Measure file growth:** if any file grows by more than 10 lines net after applying learnings, consolidate further. The skill should get SHARPER with each iteration, not LONGER.
3. **One source of truth:** if a learning could go in SKILL.md or a reference doc, always choose the reference doc. SKILL.md stays lean.
4. **Generalization mandatory:** strip project-specific names, branch names, API endpoints. Extract the reusable pattern.

## Issue format

Title: `[kmm-retro] <project-name>: <N> learnings from migration`

Body contains for each learning:
- **File to modify:** exact path
- **Section:** where in the file
- **Content to add:** the actual markdown/text to insert (copy-pasteable)
- **Rationale:** why this was learned (what went wrong without it)

Labels: `skill:kmm-workflow`, `type:self-improvement`, `session:<date>`

- **Always create retrospective issues on the skill's own repo** (detect via `gh repo view --json nameWithOwner`), NOT on the app repo being migrated. The learnings are about the skill itself, not the app.

## Generalization rule (mandatory)

Every learning MUST be generalized before capturing. The skill's reference files are project-agnostic — they must be useful for ANY KMM migration, not just the current project.

**Before writing any learning, strip:**
- Project-specific class/interface names → replace with generic examples (e.g., `MyUseCase` not `IGetEstimatedMarginUseCase`)
- Branch names, repo names, artifact names → describe the pattern (e.g., "check if a KMM branch exists" not "merge `feature/xyz-kmm`")
- API endpoints, server names, product names → describe the category (e.g., "backend server" not "Heimdall")
- Gameplan/phase-specific context → extract the reusable principle

**Test:** Would a developer on a completely different Android→KMM project find this learning useful as-is? If they'd need to mentally replace project names to understand it, it's not generalized enough.

**For external SDK dependencies:** When capturing a learning about an SDK's KMM availability, do NOT record the specific SDK. Instead, record the **process improvement** — e.g., "always ask the user if a KMM version exists for external SDK deps before building Android bridge adapters."

## What NOT to capture

- Project-specific decisions (base URLs, artifact names, branch names, class names)
- One-off bugs that were fixed during the session
- User preferences that are already in CLAUDE.md (like "no type casting")
- Anything already in the skill's reference files
- Phase-specific or gameplan-specific details that only apply to the current session

# Phase 1: Discovery & Experience Capture

## Step 1: Discover skills used

Use **both** sources and merge results. Either source alone may be incomplete.

### Source A: Session log

Read `~/.skill-session-log.jsonl`. Each line is a JSON object:

```json
{
  "skill": "feature-analyzer",
  "timestamp": "2026-03-20T09:15:22Z",
  "tool": "Skill",
  "project": "sniper-v2-android"
}
```

Group entries by `skill` name. Count invocations per skill. Note the time range.

Filter to relevant entries:
- Default: today's entries only (current session)
- If the developer says "review the whole week" or similar, expand the window accordingly

### Source B: Conversation context (fallback and supplement)

Scan the current conversation for skill usage evidence:
- `<command-name>` tags — these indicate skill invocations (e.g., `<command-name>/clean-code:clean-code</command-name>`)
- `/plugin:skill` patterns in user messages
- `<system-reminder>` content mentioning prehook injections (e.g., "CLEAN CODE PREHOOK")
- `Skill` tool calls in the conversation

This catches skills the hook missed (e.g., prehook-injected skills that don't go through the Skill tool).

### Merge results

Combine both sources. Deduplicate by skill name. Mark the source for each (`log`, `context`, or `both`).

## Step 2: Present the discovery summary

Show the developer what was detected. Format:

```
📊 Session Skill Usage (2026-03-20)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. feature-analyzer     — 2 invocations (09:15, 11:42)
2. clean-code           — 1 invocation  (10:30)
3. qa-autopilot         — 3 invocations (12:00, 12:45, 13:10)

Session span: 09:15 → 13:10 (3h 55m)
Project: sniper-v2-android
```

Then ask: **"Does this look right? Any skills missing from this list that you used or expected to use?"**

If the developer names additional skills (that the hook missed or that failed to trigger), add them to the review list with a `[manual]` tag.

## Step 3: Context-first experience analysis

**BEFORE asking the developer anything**, analyze the conversation history for each skill. Look for these signals:

**Negative signals (lower rating):**
- User corrections: "no not that", "that's wrong", "don't do X"
- Re-runs or retries of the same skill
- User manually fixing skill output
- Explicit frustration: "this isn't working", "it's ignoring the guidelines"
- User having to explain what the skill should already know

**Positive signals (higher rating):**
- User accepting output without correction
- User praising output: "perfect", "exactly", "great"
- Moving on to next task without revisiting skill output
- User building on skill output (indicates trust)

**Auto-derive ratings:**
- Accepted without correction → ⭐⭐⭐⭐⭐
- Minor correction then accepted → ⭐⭐⭐⭐
- Multiple corrections or re-runs → ⭐⭐⭐
- User had to manually redo the work → ⭐⭐
- Skill actively produced wrong/harmful output → ⭐

### Present pre-filled assessment for confirmation

For each skill, present your analysis — do NOT ask open-ended questions:

```
━━━ clean-code (3 invocations) ━━━

Based on our session, here's what I observed:

OUTPUT QUALITY: Prehook fired but Claude ignored clean code principles
on first pass. User had to explicitly say "it's not following guidelines"
before references were applied. Second pass was correct.

FRICTION: User corrected output twice. Had to manually invoke
/clean-code:clean-code after prehook was insufficient.

MISSING: Prehook content in system-reminder was deprioritized by Claude.

AUTO-RATING: ⭐⭐⭐ (decent but needed manual intervention)

→ Correct anything that's off, or say "looks right" to confirm.
```

**Behavioral rules:**
- Present ALL skills at once if ≤ 3 skills. If > 3, batch in groups of 3.
- If context has no signals for a skill (e.g., prehook-only, no visible interaction), say "No interaction signals found" and auto-rate ⭐⭐⭐ (neutral).
- Accept terse confirmations: "looks right", "yep", "correct" are valid.
- If the developer corrects your assessment, update immediately — their judgment overrides your analysis.
- If the developer says "skip" for a skill, mark as "No feedback — skipped".

## Step 4: Capture untriggered skills

After all skills are reviewed, ask:

**"Were there any skills you expected to trigger during this session but didn't? This helps identify triggering gaps in skill descriptions."**

For each untriggered skill mentioned:
- What did the developer say/do that should have triggered it?
- Which skill should it have been?

Record these as "triggering failures" — they become P0 feedback items in Phase 2.

## Step 5: Handoff to Phase 2

Compile all collected data into a structured format for Phase 2:

```
Skills reviewed:
- skill_name: feature-analyzer
  invocations: 2
  output_quality: "domain analysis missed regulatory edge case for F&O segment"
  workflow_friction: "none"
  missing_capabilities: "auto-detect domain from project type"
  rating: 4
  source: log

- skill_name: jetpack-compose
  invocations: 0
  triggering_failure: "asked to build a Compose screen but it didn't trigger"
  trigger_phrase: "create a new portfolio screen with Compose"
  source: manual
```

Proceed to Phase 2 (GitHub Issue creation) immediately — do not wait for additional input unless the developer asks to pause.

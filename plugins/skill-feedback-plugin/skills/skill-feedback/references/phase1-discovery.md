# Phase 1: Discovery & Experience Capture

## Step 1: Parse the session log

Read `~/.skill-session-log.jsonl`. Each line is a JSON object:

```json
{
  "skill": "feature-analyzer",
  "timestamp": "2026-03-20T09:15:22Z",
  "file_path": "/mnt/skills/user/feature-analyzer/SKILL.md",
  "project": "sniper-v2-android"
}
```

Group entries by `skill` name. Count invocations per skill. Note the time range (earliest to latest invocation) to understand the session span.

Filter to relevant entries:
- Default: today's entries only (current session)
- If the developer says "review the whole week" or similar, expand the window accordingly

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

## Step 3: Per-skill experience capture

For each skill in the list, ask these four questions. Present them as a block so the developer can answer all at once:

```
━━━ feature-analyzer (2 invocations) ━━━

1. OUTPUT QUALITY: Did it produce what you expected? What was off?
   (e.g., "missed edge cases in domain analysis", "Notion output was perfect")

2. WORKFLOW FRICTION: Did you have to correct, re-run, or manually fix anything?
   (e.g., "had to re-run Phase 2 because it skipped cascading impact")

3. MISSING CAPABILITIES: Anything you wished it could do but couldn't?
   (e.g., "should auto-detect the domain context from the codebase")

4. RATING: 1-5 stars
   ⭐ = Actively hindered me
   ⭐⭐ = Didn't help much
   ⭐⭐⭐ = Decent, but needs work
   ⭐⭐⭐⭐ = Good, minor improvements needed
   ⭐⭐⭐⭐⭐ = Nailed it
```

Important behavioral rules:
- Present ALL skills at once if there are ≤ 3 skills. If > 3, batch in groups of 3.
- Accept terse answers. "Fine" or "4 stars, no issues" is valid. Don't push for detail when there's nothing to report.
- If the developer says "skip" for a skill, mark it as "No feedback — skipped" and move on.

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

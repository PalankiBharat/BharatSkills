# Trend Analyzer

Cross-references past GitHub Issues to identify patterns, recurring friction, and improvement trajectories for each skill.

## How to use

When generating the "Trend analysis" section of a feedback issue, follow these steps for each skill:

### Step 1: Query past issues for this skill

```bash
REPO=$(jq -r '.repo' ~/.skill-feedback-config.json)

# Get all issues (open and closed) for this skill
gh issue list -R "$REPO" \
  --label "skill:<skill-name>" \
  --state all \
  --json number,title,labels,body,createdAt,closedAt,state \
  --limit 50 | jq '.'
```

If no past issues exist, write:
```
_First feedback session for this skill. Trends will appear after 2+ sessions._
```

If past issues exist, extract from each:
- Issue number and date
- Rating (from the issue body)
- Priority label
- Key friction points
- Whether the issue is open or closed

### Step 2: Build the trend narrative

Analyze the trajectory across sessions. Answer three questions:

**1. Is this skill getting better, worse, or staying the same?**

Extract ratings from issue bodies and plot the trajectory:
```
Rating trend: ⭐⭐ (#12, Mar 10) → ⭐⭐⭐ (#28, Mar 15) → ⭐⭐⭐⭐ (#42, Mar 20) — improving ✅
```
or
```
Rating trend: ⭐⭐⭐⭐ (#15, Mar 10) → ⭐⭐⭐ (#30, Mar 18) → ⭐⭐⭐ (#42, Mar 20) — declining ⚠️
```

**2. Are there recurring friction points?**

Compare the current session's friction against open issues. If the same problem appears in 2+ issues, flag it:

```
🔁 RECURRING: Domain analysis misses F&O regulations
   Issues: #12 (Mar 10), #28 (Mar 15), #42 (Mar 20) — 3 sessions
   Status: Unresolved (all issues still open)
   → Auto-escalate to P0
```

Recurring issues (3+ sessions, still open) automatically escalate to P0 regardless of individual session priority. Add the `priority:P0` label if it wasn't already.

**3. Were past issues resolved?**

Check the state of prior issues for this skill:
- ✅ Closed issues = resolved friction
- 🔄 Open issues with comments from multiple sessions = partially addressed or still broken
- ⏳ Open issues with no activity = stale, needs attention

```
### Resolution tracker
- ✅ #12: Phase 1 question quality (closed Mar 16 — fixed)
- 🔄 #28: Cascading impact depth (open, 2 session comments — partially improved)
- ⏳ #15: Auto-domain detection (open since Mar 10, no activity — stale)
```

### Step 3: Format the trend section

```markdown
### Trend analysis

**Past issues for this skill:** 4 (#12, #15, #28, #35)
**Rating trend:** ⭐⭐⭐ → ⭐⭐⭐ → ⭐⭐⭐⭐ → ⭐⭐⭐⭐ (improving)

**Recurring issues:**
- 🔁 Domain analysis misses F&O-specific regulations — 3 sessions (#12, #28, current) → P0 escalation
- 🔁 Notion output inconsistent for nested checklists — 2 sessions (#28, current)

**Resolution tracker:**
- ✅ #12: Phase 1 question quality (closed — fixed)
- 🔄 #28: Cascading impact depth — improved but still misses 2nd-order deps
- ⏳ #15: Auto-domain detection — stale since Mar 10

**Insight:** <one-sentence synthesis of trajectory and highest-ROI next fix>
```

## Useful label queries

```bash
# All open P0 issues across all skills
gh issue list -R "$REPO" --label "priority:P0" --state open

# All issues for a specific skill
gh issue list -R "$REPO" --label "skill:feature-analyzer" --state all

# All issues from a specific session
gh issue list -R "$REPO" --label "session:2026-03-20" --state all

# Recurring issues (multiple session labels)
gh issue list -R "$REPO" --label "priority:P0" --state open --json number,title,labels \
  | jq '[.[] | select([.labels[].name | select(startswith("session:"))] | length > 1)]'
```

## Edge cases

- **First session ever:** Skip trend analysis, note it's the first session
- **Skill was significantly rewritten:** Note the rewrite, don't compare ratings across versions
- **Too many past issues (>20):** Focus on the 10 most recent. Summarize older ones as "N earlier issues, M resolved, K still open"

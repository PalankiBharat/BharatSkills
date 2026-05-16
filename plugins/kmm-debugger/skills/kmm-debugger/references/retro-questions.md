# Closing retro — question-to-action mapping

The retro asks 6 questions. Each answer category maps to a specific edit proposal. The skill's curator (the user) approves, modifies, or skips each one.

## When to fire the retro (hard gate)

The retro is NOT user-initiated. Fire proactively after any of:
- `git push` to remote
- PR opened or updated
- `./gradlew publish` to Nexus / Maven Central
- Alpha tagged and pushed
- All planned fixes for the session are shipped
- Phase 1 was re-fired due to a fix-didn't-fully-resolve loop (highest-value retro signal — the workflow caught itself, the user should see what the skill learned)

Don't wait for the user to signal "we're done" or "thanks" or to invoke `/skill-feedback`. The user-signaled trigger is one of many, not the only one. By the time the user signals closure, the session context is decaying and the highest-value lessons are already harder to recall.

If the user says "skip" or "later", respect it and note the offer in the session log. If they ask to come back to it later, the trigger conditions above apply at any point in a future session.

## Q1: Did the pitfall catalog map correctly?

For each user-reported bug, ask: did `references/pitfalls.md` predict the root cause?

| Answer | Action |
|---|---|
| "Yes, pitfall #N was the right diagnosis" | No edit needed. Note in session log that pitfall #N matched. |
| "Pitfall #N was close but the symptom matched something slightly different" | Edit pitfall #N to widen the "Symptom" section with the new symptom variant. Quote the user's actual phrasing where useful. |
| "None of the catalog pitfalls fit; the actual cause was X" | Add a new pitfall entry. Use the existing entry template: Symptom → Root cause → Right fix → Verification. Renumber if needed. Update SKILL.md's "Common KMM migration pitfalls" short summary. |
| "Multiple pitfalls fit and we couldn't decide which until later" | Add a cross-reference at the top of the involved pitfall entries: "If you're unsure between this and Pitfall #M, the disambiguator is: …" |

## Q2: Where did the mindset framing land or miss?

Ask: did "right KMM + don't break prod" hold throughout, or did you have to correct toward a different framing mid-session?

| Answer | Action |
|---|---|
| "It held; no corrections needed" | No edit. Note in session log. |
| "I had to correct toward [X framing] for [defect Y]" | This is the highest-value learning. Add to SKILL.md's "Mindset" section. Format: "Don't use this framing: [X]. Do use this framing: [Y]. Why: [brief reason]." Match the existing Do/Don't structure. |
| "The four-question framework didn't fit defect Y" | Add a note to SKILL.md's "Per-defect analysis pattern" describing the defect shape where the framework breaks down and what to do instead. Don't replace the framework — augment it. |
| "The 'master is one reference point, not the target' framing felt wrong for [scenario]" | Carefully consider whether the user's correction is a real exception or a regression to "match master at all costs." If real, add it. If regression, surface to the user: "I want to push back here — this looks like the 'match master' framing the skill was trying to avoid. Want to discuss?" |

## Q3: Which subagent prompts produced sharp findings vs. fluff?

Ask per subagent type (bug-investigation, PR-archeology, baseline-comparison, feasibility-analysis).

| Answer | Action |
|---|---|
| "Bug-investigation prompt was tight; sharp findings" | No edit. |
| "PR-archeology found nothing useful because [reason]" | Edit `references/subagent-prompts.md` template 2. If the reason is "no review threads existed on the PR" — add a step that handles unreviewed-PR signal explicitly (e.g., "if the PR has zero reviews, surface that as a signal and adjust confidence accordingly"). |
| "Baseline-comparison missed the existing pattern because the master file was renamed" | Edit template 3 to include `git log --follow` for path-rename detection. |
| "The prompt was too constraining and the subagent skipped useful detours" | Find the over-constraint. Common patterns: word-count too low for the scope, output structure too rigid for an unusual finding, "no code edits" framing preventing the subagent from sketching a fix shape inline. Loosen the specific constraint. |
| "The prompt was too vague and the subagent rambled" | Tighten with: more specific file:line starting points, narrower hypothesis-to-test wording, output format with sub-bullets. |

## Q4: What surprised you?

Ask for any non-obvious root cause not predicted by the catalog or the four-question framework.

| Answer | Action |
|---|---|
| "Nothing surprised me" | No edit (but this answer is rare — push gently: "even small surprises?"). |
| "Defect X had root cause Y which the catalog didn't anticipate" | Add a new pitfall entry, OR if it's a refinement of an existing pitfall, expand that entry. The novelty is in the "Why this is happening" framing — make sure the new content captures the *mental model*, not just the fix. |
| "The fix required a sequencing I didn't expect" | Edit SKILL.md's "Execution workflow" — add the sequencing nuance as a new bullet. |
| "A non-KMM tool/library behavior dominated the bug (e.g., Gradle Module Metadata, Hilt, AGP variant resolution)" | Decide if the surprise is in-scope. If yes (it's a recurring KMM consumer concern), add to pitfalls. If no (it was a one-off), note in session log only. |

## Q5: What would you do differently if this session started over?

The most important question. Listen for sequencing changes, phase skips, framing shifts.

| Answer | Action |
|---|---|
| "I'd start with Phase 2 (PR archeology) before Phase 1 (bug investigation) because the PR had a Known trade-offs section that telegraphed two bugs" | Add to SKILL.md's "Investigation workflow" — note that when the PR is suspected to have explicit trade-offs, PR archeology can lead. Don't reorder the default; add a conditional. |
| "I'd skip Phase 3 (baseline comparison) for [type of defect]" | Add a conditional to Phase 3: "Skip when [condition]." Be careful — the default should still be to run it. |
| "I'd ask the user for a Logcat / stack trace before dispatching any subagents" | Add a "Phase 0 — concrete signal collection" step to SKILL.md, OR add to each Phase 1 prompt a "request a Logcat capture from the user if a crash is involved." |
| "I'd run Phase 1 in series instead of parallel because the bugs were related" | This contradicts the skill's default. Push back: "I think parallel was right here — the bugs were independent enough that wall-time savings outweighed synthesis cost. What made you feel they were related?" Then decide if the answer reveals a genuine pattern (related bugs benefit from sequential) or was a perception. |
| "I'd skip the formal investigation entirely because the bug was obvious from the symptom" | This is a real signal — there's a class of obvious bugs where the workflow is overkill. Add to SKILL.md a "When to skip phases" section: "If the bug is a single symptom with a one-line fix obvious from the symptom (e.g., 'forgot to handle null'), skip directly to the fix. The workflow is for *unclear* multi-defect regressions." |

## Q6: Did the three doctrines (no-bias, deep-investigation, clean-solution) hold?

Ask: did you catch yourself anchoring on existing implementation, proposing minimal patches, or starting to write Fix N+1 as a patch on Fix N?

| Answer | Action |
|---|---|
| "Doctrines held; no bias detected" | No edit. Note in session log. |
| "I anchored on the existing implementation for defect X — had to re-fire with explicit bias-guard reminder" | Strengthen the bias-guard preamble in `references/subagent-prompts.md`. Make the named bias more specific (e.g., "do not defend the existing storage shape because the migration author marked it as deliberate"). Add the bias mode to `references/doctrines.md` Doctrine 1 named-bias-modes list. |
| "I proposed a minimal patch for defect X when the clean fix was feasible" | Add the specific patch-instinct trigger to `references/doctrines.md` Doctrine 3 anti-pattern table. Quote the user's correction verbatim — the user's phrasing is what catches the same pattern next time. |
| "I shipped Fix N, it didn't fully work, and I started writing Fix N+1 as a patch on Fix N before catching myself" | Strengthen the recognition criteria in `references/fix-loop-protocol.md` "Recognizing the loop" section. The fact that the protocol existed and drift still happened is the signal — sharpen the trigger language so the next session catches it faster. |
| "I shipped Fix N, it didn't fully work, and I started writing Fix N+1 as a patch on Fix N WITHOUT catching myself — the user had to stop me" | Same as above, plus: this is a serious failure mode. Surface the specific drift pattern to the user and propose adding a hard reminder near the top of `SKILL.md` Phase 1 — something like "if your last fix didn't fully resolve, jump to `fix-loop-protocol.md` immediately, do not proceed". |
| "A/B pair dispatch felt overkill for this bug" | Push back: was it actually overkill, or did it feel that way because A and B agreed? Agreement is the success case of A/B dispatch, not a failure. If genuinely overkill, the bug was unambiguous and the doctrine still says A/B for unambiguous bugs — surface the disagreement and we discuss whether to adjust the doctrine. |
| "Doctrines held but I felt slowed down" | This is a real cost worth tracking. Add to the session log how much wall time the dispatch added. If the pattern recurs across sessions, that's data for revisiting the dispatch matrix. Do not edit the doctrine on a single data point. |

## Edit application discipline

- **Diff format for multi-line edits.** Show the user a unified diff (5 lines of context) before applying.
- **Inline preview for single-sentence edits.** "I'd add this line to the Mindset section: `<line>`."
- **One edit at a time.** Don't propose all 5 question's edits as a single mega-diff. Walk through each.
- **Approve / modify / skip per edit.** User says "skip 3, approve 1/2/4/5 with these tweaks…".
- **Apply only after approval.** Use the same Edit tool the rest of the workflow uses.

## Session log format

If the user opts into the session log, write a short entry to `sessions/YYYY-MM-DD-<short-slug>.md`. Template:

```markdown
# YYYY-MM-DD — <short slug, e.g. "sesame-mig28-fix">

**Bug surface investigated:** <one-line description>

**Pitfalls matched:** <list, e.g. "#1 BuildKonfig wiring, #4 init-time scope leak">

**Mindset corrections (if any):** <one-line, or "none">

**Surprises:** <one-line, or "none">

**Skill updates from this session:**
- SKILL.md: <link/anchor or "none">
- pitfalls.md: <link/anchor or "none">
- subagent-prompts.md: <link/anchor or "none">

**Outcome:** <fixes shipped? alpha published? smoke green? bug closed?>
```

Keep under 200 words. The trail's purpose is pattern recognition across sessions, not full archival.

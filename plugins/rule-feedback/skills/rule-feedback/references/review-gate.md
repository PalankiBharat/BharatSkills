# Review Gate

The review gate is non-negotiable. Nothing leaves this phase without
explicit per-item approval.

## Presentation format

Present candidates **one at a time**, not as a big list. The user should
make deliberate decisions, not skim through. For each candidate:

```
─────────────────────────────────────────────────────────
Candidate N of M — [classification] [priority] [target_file]

I suspect Claude missed this rule because:
> <verbatim user text or observation>

Interpretation:
<Claude's one-sentence summary of what rule this relates to>

Proposed issue:
  Title: <short, imperative>
  Body:
    <rendered body from issue-template.md>
  Labels: rule-feedback, <classification>, priority:<P>

Action? [r]aise / [e]dit / [s]kip
─────────────────────────────────────────────────────────
```

## Handling user input

- **raise** — record the candidate as "to create" and move to the next.
- **edit** — ask the user what to change (title, body, priority,
  classification, target file). Apply the edit and re-present the
  candidate. Loop until raise or skip.
- **skip** — defer this candidate. Return at the end of the review
  pass and present once more. If the user skips again, drop.

There is no permanent "drop" option. A single explicit skip after a
second presentation is sufficient to dismiss — no one needs a third
prompt for the same item.

## Bundle offer

If the detection phase flagged multiple candidates with the same theme
(e.g., three concurrency-related corrections), offer a bundle:

> "Three candidates touch concurrency. Bundle into one issue with
>  three bullet points, or keep separate?"

Default is **separate** unless the user explicitly asks to bundle. One
issue per theme is easier to triage than one mega-issue with six
unrelated asks.

## Final confirmation

After every candidate is reviewed, show the summary:

```
Ready to create N issues on <owner>/<repo>:

  1. [claude-md, P1] <title>
  2. [constitution, P2] <title>
  3. [path-rule, P2] <title>

Proceed? [y/n]
```

If `n`, exit without creating anything. If `y`, move to Phase 3.

## Empty session handling

If Phase 1 returned no candidates, say so and stop. Do not prompt for
manual entry. Do not invent issues. Example:

> "Scanned the session — no rule-worthy corrections detected.
>  Nothing to raise. Exiting."

## Anti-patterns

- Do not pre-approve "obvious" candidates to save the user time.
- Do not batch-approve ("create all 5 as drafted"). One-by-one is the
  whole point.
- Do not argue if the user drops a candidate. Note the drop and move on.
- Do not re-raise a dropped candidate later in the same session.

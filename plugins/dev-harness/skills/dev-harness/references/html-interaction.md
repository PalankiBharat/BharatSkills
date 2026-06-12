# HTML interaction layer

Every human touchpoint renders as a themed browser page — never a raw terminal prompt.

## needs-user questions → a structured FORM (not prose)

When an agent needs the user to decide, it writes `.harness/artifacts/questions.json` and the Orchestrator renders it with **`bash .harness/ask .harness/artifacts/questions.json`** (`scripts/render-questions.sh`). This produces a clean, minimal, UX-friendly form — severity-grouped, one field per question, the recommended option pre-selected and badged — and a single **Copy answers** button that emits a parseable `HARNESS ANSWERS` block the user pastes back.

**Schema** (`questions.json`):
```json
{ "title": "one line of context (optional)",
  "groups": [
    { "label": "Blockers", "severity": "blocker | clarification", "questions": [
      { "id": "b1",
        "type": "single | multi | text",
        "q": "the question (short, specific)",
        "why": "one line on why it matters (optional)",
        "context": "2-4 plain-language sentences of background so the harness owner — who may not know the codebase — understands the situation AND what each option means in practice",
        "options": [ {"label":"option A","recommended":true}, {"label":"option B"} ],
        "allowNote": true } ] } ] }
```
Rules the agents follow: **one focused question per decision; every choice question offers concrete options with exactly one `recommended`** (the sensible default); **always write `context`** in plain language for a non-coder — a question like "Drop `#id` from alerts?" is meaningless without it; `blocker` (gates the build) is grouped apart from `clarification`; `text` only when free input is genuinely needed; never a vague open-ended ask. `options`/`allowNote` are ignored for `type: text`.

**Reply format** (what the user pastes back) — the Orchestrator parses it:
```
HARNESS ANSWERS
[b1] I'll paste the spec now
  [b1 note] …optional free text…
[b2] symbol,price,ts; skip malformed
[c1] Skip the row, continue
```

## Other touchpoints (prose review)


`scripts/render-review.sh <kind> <payload-file> [--no-open]`
- **kinds:** `story` · `plan` · `questionnaire` · `verdict` · `summary`
- wraps the payload (markdown/text) — first **redacted** then **HTML-escaped** — in `assets/theme.css`
- writes `.harness/review/<kind>-<ts>.html`, prints the path, and `open`s it (skips with `--no-open` or when `open` is absent)
- the page has a comment box + a **Copy reply** button (clipboard API, with a select-the-preview fallback for `file://`)

## Figma parity gate → per-screen visual review

`scripts/render-parity.sh <parity-root> [--no-open]` (wrapper: `bash .harness/parity-review …`) renders every screen under `.harness/artifacts/parity/` as **design left / render right** with the diff heatmap, an `approve | needs changes` verdict and a comment box per screen. **Copy reply** emits the parseable block the Orchestrator routes to Dev:

```
PARITY REVIEW
[screen-a] approve
[screen-b] needs-changes: header spacing too tight
```

## The contract
1. Orchestrator writes the payload (e.g. spec + phase plan) to a file.
2. Calls `render-review.sh plan <file>` → page opens.
3. User reviews, types comments/answers, clicks **Copy reply**, pastes the block back into the main session.
4. Orchestrator parses the reply and proceeds (or loops the gate).

## Scope
v1.5 ships the **lean** page (header + payload + comment box + copy). The fuller feature-analyzer
theming (sticky sidebar, Original-Story tab) is deferred to v2. The user still always reviews in HTML.

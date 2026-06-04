# HTML interaction layer

Every human touchpoint renders as a themed browser page — never a raw terminal prompt.

`scripts/render-review.sh <kind> <payload-file> [--no-open]`
- **kinds:** `story` · `plan` · `questionnaire` · `verdict` · `summary`
- wraps the payload (markdown/text) — first **redacted** then **HTML-escaped** — in `assets/theme.css`
- writes `.harness/review/<kind>-<ts>.html`, prints the path, and `open`s it (skips with `--no-open` or when `open` is absent)
- the page has a comment box + a **Copy reply** button (clipboard API, with a select-the-preview fallback for `file://`)

## The contract
1. Orchestrator writes the payload (e.g. spec + phase plan) to a file.
2. Calls `render-review.sh plan <file>` → page opens.
3. User reviews, types comments/answers, clicks **Copy reply**, pastes the block back into the main session.
4. Orchestrator parses the reply and proceeds (or loops the gate).

## Scope
v1.5 ships the **lean** page (header + payload + comment box + copy). The fuller feature-analyzer
theming (sticky sidebar, Original-Story tab) is deferred to v2. The user still always reviews in HTML.

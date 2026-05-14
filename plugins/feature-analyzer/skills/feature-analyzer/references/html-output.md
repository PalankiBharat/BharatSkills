# HTML Output (Mode 1 default)

Mode 1 emits an HTML doc — not Markdown — because the audience is PM / Design / Backend, who consume the doc in a browser, not a terminal. Markdown in chat is unshareable; HTML is.

## Output path

`docs/feature-analysis/<feature-slug>-analysis.html`

Slug rule: kebab-case from the feature title (e.g. `Custom Time Frame` → `custom-time-frame`).

## Required components

The HTML doc has eight required components. All must be present even if a section ends up empty (render an empty-state hint instead of dropping the section).

1. **Sidebar nav (sticky, left rail)** — page-section links: Scope · Existing flow · Code requirements · Blockers · Clarifications · Nice-to-have · Assumptions · Copy. One-click jumps; current section highlighted as you scroll.
2. **Header block** — feature name, one-line intent, date, run mode (Mode 1), session-id (small grey).
3. **Scope-report block** — populated by `scope-classifier.md`. Renders included / stripped / conditional sections as a 3-column callout.
4. **Existing-flow trace** — collapsible. Populated by `existing-flow-trace.md`. If skipped (greenfield), render a 1-line "Flow trace skipped — story self-declares greenfield" note.
5. **Code requirements (diff block)** — collapsible. For every `delta` produced by `gap-analyzer` that maps to a concrete code touch-point, render a unified diff snippet showing current-state → target-state. See "Diff block" below.
6. **Priority buckets** — `<details>` per bucket: 🔴 Blockers · 🟡 Clarifications · 🟢 Nice-to-have. Each bucket lists its question cards.
7. **Per-question card** — see "Question card" below.
8. **Copy controls** — top-right toolbar with: filter chips (priority + role), select-all-in-bucket, **selective copy modal**, copy-all-selected button.

## Sidebar nav

The sidebar is the navigation backbone. Stakeholders skim a 30-question doc faster when section jumps are one click away.

```html
<nav class="sidebar">
  <h2>{{feature_name}}</h2>
  <ul>
    <li><a href="#scope">Scope filter</a></li>
    <li><a href="#flow">Existing flow</a></li>
    <li><a href="#diff">Code requirements</a></li>
    <li><a href="#blockers">🔴 Blockers (<span class="badge">{{n_blockers}}</span>)</a></li>
    <li><a href="#clarifications">🟡 Clarifications (<span class="badge">{{n_clarify}}</span>)</a></li>
    <li><a href="#nice">🟢 Nice-to-have (<span class="badge">{{n_nice}}</span>)</a></li>
    <li><a href="#assumptions">📌 Assumptions</a></li>
    <li><a href="#copy">📋 Copy answers</a></li>
  </ul>
  <hr>
  <h3>Filter</h3>
  <div class="filter-chips">
    <button data-filter-role="all" class="chip active">All roles</button>
    <button data-filter-role="PM">PM</button>
    <button data-filter-role="Backend">Backend</button>
    <button data-filter-role="Design">Design</button>
    <button data-filter-role="QA">QA</button>
    <button data-filter-role="Compliance">Compliance</button>
    <button data-filter-role="DevOps">DevOps</button>
  </div>
</nav>
```

The sidebar uses `position: sticky; top: 0; height: 100vh;` so it stays visible while the main column scrolls. Scroll-spy updates which link is active.

## Scope-report block

Three-column callout: Included (green) · Stripped (grey, struck-through) · Conditional (amber). Easier to scan than the original bulleted list.

```html
<div class="scope-report" id="scope">
  <div class="col included">
    <h4>✓ Included</h4>
    <ul>{{included_items}}</ul>
  </div>
  <div class="col stripped">
    <h4>✗ Stripped</h4>
    <ul>{{stripped_items}}</ul>
  </div>
  <div class="col conditional">
    <h4>⚠ Conditional</h4>
    <ul>{{conditional_items}}</ul>
  </div>
</div>
```

## Existing-flow trace

If flow-tracer ran successfully, render the chain as a vertical breadcrumb with `file:line` cites:

```html
<details id="flow" open>
  <summary>Existing flow audit (confidence: {{avg_confidence}})</summary>
  <ol class="flow-chain">
    <li><b>UI</b> — DurationSelectionBottomSheet
        <code>app/.../DurationSelectionBottomSheet.kt:24</code></li>
    <li><b>ViewModel</b> — ChartViewModel
        <code>app/.../ChartViewModel.kt:88</code></li>
    <li><b>SDK</b> — HistoryRemoteStore
        <code>marketpulse-android-sdk/.../HistoryRemoteStore.kt:45</code></li>
  </ol>
  <h4>Facts</h4>
  <ul class="facts">
    <li><span class="confidence high">high</span> Duration sent as query param `duration=<type>` (string)
        <code>marketpulse-android-sdk/.../HistoryRemoteStore.kt:45</code></li>
  </ul>
</details>
```

If `partial: true` or skipped, render a single callout line stating the reason. Never fabricate a chain.

## Code requirements — diff block

When `gap-analyzer` identifies a delta that the developer will need to implement, render it as a unified diff inside a `<pre class="codediff">`. Diffs come from the gap-analyzer output's `delta[].current_state` and `delta[].target_state` fields.

```html
<details id="diff" open>
  <summary>Code requirements (delta from existing flow)</summary>

  <div class="delta">
    <h4>Δ1 — Persist user-defined durations</h4>
    <p>Today: <code>ChartDurationModel</code> is a fixed enum.
       Target: extend the model with a user-defined list backed by Room.</p>
    <pre class="codediff"><code>--- a/marketpulse-android-sdk/.../ChartDurationModel.kt
+++ b/marketpulse-android-sdk/.../ChartDurationModel.kt
@@ -10,3 +10,8 @@
 enum class ChartDuration(val seconds: Int) {
   ONE_MIN(60), FIVE_MIN(300), ...
 }
+
+data class CustomDuration(
+  val id: String,
+  val seconds: Int,
+) : ChartDurationSpec</code></pre>
    <p class="evidence">Evidence: <code>ChartDurationModel.kt:12</code></p>
  </div>
</details>
```

Rules:
- Only include diffs grounded in a `gap-analyzer.delta[]` entry whose evidence has `file:line` cites. No fabricated diffs.
- If gap-analyzer ran in degraded mode (no repo access), render a placeholder diff with the comment `// TODO: target shape — repo not accessible at trace time` rather than inventing content.
- Maximum 5 diff blocks per doc. Overflow → bucket the rest under "Further deltas (links)" with a one-line description each.

## Question card

```html
<section class="question-card priority-{{priority}}" data-qid="{{qid}}"
         data-role="{{role}}" data-pillar="{{pillar}}">
  <header>
    <input type="checkbox" class="select-q" title="Include in copy-all"
           checked>
    <span class="role-tag">{{role}}</span>
    <span class="pillar-tag">{{pillar}}</span>
    <span class="confidence {{confidence}}">{{confidence}}</span>
    <button class="copy-btn">Copy this</button>
  </header>
  <h4>{{question}}</h4>
  <p class="why"><b>Decision affected:</b> {{impact}}</p>
  <p class="reason-not-derivable">
    <b>Not derivable from code/Figma because:</b> {{reason_not_derivable}}
  </p>
  <label class="pill recommended">
    <input type="radio" name="{{qid}}" value="{{rec_label}}" checked>
    {{rec_label}} — {{rec_reason}}
  </label>
  <label class="pill"><input type="radio" name="{{qid}}" value="{{opt_b}}">{{opt_b}}</label>
  <label class="pill"><input type="radio" name="{{qid}}" value="{{opt_c}}">{{opt_c}}</label>
  <input class="override" placeholder="Other / override…">
  <small class="qid">{{qid}}</small>
</section>
```

Per-card fields:

- **Header checkbox (`.select-q`)** — defaults checked. Drives selective copy.
- **Role tag** — what stakeholders see (PM, Backend, Design, Compliance, QA, DevOps).
- **Pillar tag** — small grey (`design|tech|qa|domain`). Distinct from role; see specialist-roster.md "Role → pillar map".
- **Confidence chip** — `high` (green), `medium` (amber), `low` (grey).
- **Per-card copy** — copies that one Q+A.
- **Reason-not-derivable** — mandatory; rendered as a small line so reviewer sees *why* this couldn't be answered from code.
- **Override input** — supplements the radio options.
- **Stable qid** — grey monospace at the bottom.

## Copy controls (toolbar + selective copy modal)

Top-right toolbar:

```html
<div class="copy-toolbar">
  <button id="select-all">Select all</button>
  <button id="select-none">Select none</button>
  <button id="select-blockers">Blockers only</button>
  <button id="open-copy-modal" class="primary">📋 Copy selected…</button>
</div>
```

Clicking "Copy selected…" opens a modal listing every selected question with a preview of the answer; the developer un-checks any they don't want before the final copy. Once confirmed:

```text
Q1 (Backend / blocker): How should the /history endpoint accept custom durations?
  → A: New `customSeconds` query param (recommended).

Q2 (Design / clarification): How should custom-duration chips be ordered?
  → A: Ascending by seconds (recommended).
...
```

Selective copy reduces "I just need the blockers" → "I just need backend questions" → "give me the full set" friction down to one click.

## Filter chips (top + sidebar)

Filter chips show/hide question cards in real time. State persists in `localStorage` so a stakeholder returning to the page sees the same view.

- Priority chips: `🔴 Blockers` / `🟡 Clarifications` / `🟢 Nice` / `All`
- Role chips: `PM / Backend / Design / QA / Compliance / DevOps / All`
- Pillar chips (advanced): `design / tech / qa / domain`

Combined filters use AND logic.

## Template skeleton

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Feature Analysis — {{feature_name}}</title>
  <style>
    :root { --bg:#fafafa; --card:#fff; --text:#1a1a1a; --muted:#666;
            --blocker:#dc2626; --clarify:#f59e0b; --nice:#16a34a;
            --diff-add:#dcfce7; --diff-del:#fee2e2; --diff-meta:#eef; }
    * { box-sizing: border-box; }
    body { font: 15px/1.5 -apple-system, system-ui, sans-serif; color:var(--text);
           background:var(--bg); margin:0; display:grid;
           grid-template-columns: 240px 1fr; min-height:100vh; }
    nav.sidebar { position:sticky; top:0; height:100vh; padding:20px; overflow:auto;
                  border-right:1px solid #e5e5e5; background:#fff; }
    nav.sidebar h2 { margin:0 0 12px; font-size:16px; }
    nav.sidebar ul { list-style:none; padding:0; margin:0 0 16px; }
    nav.sidebar li a { display:block; padding:6px 8px; border-radius:4px; color:inherit;
                       text-decoration:none; font-size:13px; }
    nav.sidebar li a:hover, nav.sidebar li a.active { background:#f0f0f0; font-weight:600; }
    .badge { color:var(--muted); font-size:11px; margin-left:4px; }
    .filter-chips { display:flex; flex-wrap:wrap; gap:4px; }
    .filter-chips button { font-size:12px; padding:3px 8px; border:1px solid #ddd;
                           background:#fff; border-radius:999px; cursor:pointer; }
    .filter-chips button.active { background:#1a1a1a; color:#fff; border-color:#1a1a1a; }
    main { padding:24px 36px; max-width:920px; }
    h1 { margin:0 0 4px; }
    .meta { color:var(--muted); font-size:13px; margin-bottom:16px; }
    .copy-toolbar { position:sticky; top:0; z-index:10; background:var(--bg);
                    padding:10px 0; border-bottom:1px solid #e5e5e5; margin-bottom:16px;
                    display:flex; gap:8px; flex-wrap:wrap; }
    .copy-toolbar button { padding:6px 12px; border:1px solid #ddd; background:#fff;
                           border-radius:6px; cursor:pointer; font:inherit; }
    .copy-toolbar button.primary { background:#1a1a1a; color:#fff; border-color:#1a1a1a; }
    .scope-report { display:grid; grid-template-columns: 1fr 1fr 1fr; gap:12px;
                    margin:12px 0 20px; }
    .scope-report .col { padding:12px 14px; border-radius:6px; }
    .scope-report .included { background:#f0fdf4; border-left:4px solid #16a34a; }
    .scope-report .stripped { background:#f5f5f5; border-left:4px solid #9ca3af; }
    .scope-report .stripped li { text-decoration: line-through; opacity:0.7; }
    .scope-report .conditional { background:#fffbea; border-left:4px solid var(--clarify); }
    .scope-report h4 { margin:0 0 6px; font-size:13px; }
    .scope-report ul { margin:0; padding-left:18px; font-size:13px; }
    details { background:var(--card); border:1px solid #e5e5e5; border-radius:8px;
              margin:12px 0; padding:12px 16px; }
    details summary { font-weight:600; cursor:pointer; }
    .flow-chain { padding-left:22px; }
    .flow-chain li { margin:4px 0; }
    .flow-chain code, .facts code { background:#f1f5f9; padding:1px 6px; border-radius:3px;
                                    font-size:12px; }
    .codediff { background:#0d1117; color:#c9d1d9; padding:12px 16px; border-radius:6px;
                font: 12px/1.5 ui-monospace, SFMono-Regular, monospace;
                overflow:auto; }
    .codediff code { display:block; white-space:pre; }
    .codediff code, .codediff .add { color:#7ee787; }
    .codediff .del { color:#ff7b72; }
    .delta { padding:8px 0; border-bottom:1px solid #eee; }
    .delta:last-child { border-bottom:0; }
    .delta h4 { margin:8px 0 4px; }
    .question-card { padding:16px; border:1px solid #ececec; border-radius:6px;
                     margin:12px 0; background:#fff; transition: opacity 120ms; }
    .question-card.hidden { display:none; }
    .question-card header { display:flex; align-items:center; gap:8px; margin-bottom:8px;
                            flex-wrap:wrap; }
    .question-card.priority-red { border-left:4px solid var(--blocker); }
    .question-card.priority-yellow { border-left:4px solid var(--clarify); }
    .question-card.priority-green { border-left:4px solid var(--nice); }
    .select-q { width:18px; height:18px; cursor:pointer; }
    .role-tag, .pillar-tag, .confidence { display:inline-block; padding:2px 8px;
                                          border-radius:4px; font-size:12px; }
    .role-tag { background:#eef; color:#225; }
    .pillar-tag { background:#f5f5f5; color:var(--muted); font-family: ui-monospace,
                  monospace; font-size:11px; }
    .confidence { font-size:11px; }
    .confidence.high { background:#dcfce7; color:#166534; }
    .confidence.medium { background:#fef3c7; color:#92400e; }
    .confidence.low { background:#f1f5f9; color:#475569; }
    .why { color:var(--muted); font-size:13px; margin:4px 0 4px; }
    .reason-not-derivable { color:#475569; font-size:12px; font-style:italic;
                            margin:0 0 10px; }
    .pill { display:inline-block; padding:6px 12px; border:1px solid #ddd; border-radius:999px;
            cursor:pointer; margin:4px 6px 4px 0; font-size:13px; }
    .pill input { margin-right:6px; }
    .recommended { border-color:#16a34a; background:#f0fdf4; }
    .recommended::before { content:"★ Recommended — "; color:#16a34a; font-weight:600; }
    .override { display:block; margin-top:8px; width:100%; padding:6px 8px;
                border:1px solid #ddd; border-radius:4px; font:inherit; }
    .copy-btn { padding:4px 10px; font-size:12px; cursor:pointer;
                background:#f5f5f5; border:1px solid #ddd; border-radius:4px;
                margin-left:auto; }
    .qid { color:#bbb; font-family: ui-monospace, monospace; font-size:11px; display:block;
           margin-top:8px; }
    /* modal */
    .modal-backdrop { position:fixed; inset:0; background:rgba(0,0,0,0.4);
                      display:none; align-items:center; justify-content:center; z-index:50; }
    .modal-backdrop.open { display:flex; }
    .modal { background:#fff; border-radius:8px; padding:24px; max-width:720px;
             max-height:80vh; overflow:auto; width:90%; }
    .modal h3 { margin-top:0; }
    .modal pre { background:#f8f8f8; padding:12px 14px; border-radius:6px; overflow:auto;
                 font-size:12px; }
    .modal-actions { display:flex; gap:8px; margin-top:12px; }
  </style>
</head>
<body>
  <nav class="sidebar"> <!-- as above --> </nav>
  <main>
    <h1>{{feature_name}}</h1>
    <div class="meta">{{intent}} · {{date}} · Mode 1 · <small>{{session_id}}</small></div>

    <div class="copy-toolbar">
      <button id="select-all">Select all</button>
      <button id="select-none">Select none</button>
      <button id="select-blockers">Blockers only</button>
      <button id="open-copy-modal" class="primary">📋 Copy selected…</button>
    </div>

    <div class="scope-report" id="scope">…</div>

    <details id="flow" open><summary>Existing flow audit</summary>…</details>
    <details id="diff" open><summary>Code requirements (delta from existing flow)</summary>…</details>

    <details id="blockers" open><summary>🔴 Blockers ({{n_blockers}})</summary>{{blocker_cards}}</details>
    <details id="clarifications" open><summary>🟡 Clarifications ({{n_clarify}})</summary>{{clarify_cards}}</details>
    <details id="nice"><summary>🟢 Nice-to-have ({{n_nice}})</summary>{{nice_cards}}</details>

    <details id="assumptions"><summary>📌 Assumptions</summary>{{assumptions_list}}</details>
  </main>

  <div class="modal-backdrop" id="copy-modal">
    <div class="modal">
      <h3>Copy selected answers</h3>
      <p class="meta">{{n_selected}} of {{n_total}} questions selected. Edit selection below, then click Copy.</p>
      <pre id="copy-preview">{{preview_text}}</pre>
      <div class="modal-actions">
        <button id="copy-final" class="primary">Copy to clipboard</button>
        <button id="modal-close">Close</button>
      </div>
    </div>
  </div>

  <script>
    // Per-card copy
    document.querySelectorAll('.copy-btn').forEach(b => b.onclick = () => {
      const card = b.closest('.question-card');
      const q = card.querySelector('h4').innerText;
      const sel = card.querySelector('input[type=radio]:checked');
      const txt = card.querySelector('.override').value;
      navigator.clipboard.writeText(`Q: ${q}\nA: ${(sel?.value || '—')}${txt ? ` (override: ${txt})` : ''}`);
    });

    // Bulk select
    document.getElementById('select-all').onclick = () =>
      document.querySelectorAll('.select-q').forEach(c => c.checked = true);
    document.getElementById('select-none').onclick = () =>
      document.querySelectorAll('.select-q').forEach(c => c.checked = false);
    document.getElementById('select-blockers').onclick = () => {
      document.querySelectorAll('.question-card').forEach(c => {
        c.querySelector('.select-q').checked = c.classList.contains('priority-red');
      });
    };

    // Filter chips
    let activeRole = 'all';
    document.querySelectorAll('[data-filter-role]').forEach(b => {
      b.onclick = () => {
        activeRole = b.dataset.filterRole;
        document.querySelectorAll('[data-filter-role]').forEach(x =>
          x.classList.toggle('active', x === b));
        document.querySelectorAll('.question-card').forEach(c => {
          const match = activeRole === 'all' || c.dataset.role === activeRole;
          c.classList.toggle('hidden', !match);
        });
      };
    });

    // Selective copy modal
    function buildPreview() {
      const cards = [...document.querySelectorAll('.question-card')].filter(
        c => c.querySelector('.select-q').checked && !c.classList.contains('hidden')
      );
      return cards.map(c => {
        const role = c.dataset.role;
        const bucket = c.classList.contains('priority-red') ? 'blocker'
                     : c.classList.contains('priority-yellow') ? 'clarification'
                     : 'nice';
        const q = c.querySelector('h4').innerText;
        const sel = c.querySelector('input[type=radio]:checked');
        const txt = c.querySelector('.override').value;
        return `Q (${role} / ${bucket}): ${q}\n  → A: ${(sel?.value || '—')}${txt ? ` (override: ${txt})` : ''}`;
      }).join('\n\n');
    }
    document.getElementById('open-copy-modal').onclick = () => {
      document.getElementById('copy-preview').innerText = buildPreview() || '(no questions selected)';
      document.getElementById('copy-modal').classList.add('open');
    };
    document.getElementById('modal-close').onclick = () =>
      document.getElementById('copy-modal').classList.remove('open');
    document.getElementById('copy-final').onclick = () => {
      navigator.clipboard.writeText(buildPreview());
      document.getElementById('modal-close').click();
    };
  </script>
</body>
</html>
```

## Markdown opt-in

Caller flag `--format md` falls back to the markdown layout in `SKILL.md` Mode 1 output block. Use only for terminal-only sessions or when HTML rendering is unavailable.

## Why these components

| Component | Reason |
|---|---|
| Sidebar | Doc can be 30+ questions; without nav, stakeholders scroll-lose. |
| Diff block | Engineers don't want to read prose deltas. A real unified diff is the fastest way to convey "what changes in code". |
| Filter chips | A Backend engineer doesn't want to see 20 design questions. One click filters. |
| Selective copy | Stakeholders rarely need the whole set. Per-question checkboxes + bucket presets = 1-click "blockers only". |
| Confidence chip | Reviewer sees at a glance which questions rest on `flow-tracer` cites vs UX heuristic vs speculation. |
| Reason-not-derivable line | Surfaces *why* the code couldn't answer this. Pushes back against questions that are just lazily generated. |

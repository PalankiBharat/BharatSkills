# HTML Output (Mode 1 default)

Mode 1 emits an HTML doc — not Markdown — because the audience is PM / Design / Backend, who consume the doc in a browser, not a terminal. Markdown in chat is unshareable; HTML is.

## Output path

`docs/feature-analysis/<feature-slug>-analysis.html`

Slug rule: kebab-case from the feature title (e.g. `Custom Time Frame` → `custom-time-frame`).

## Canonical reference render

A populated reference rendering of this template lives at
`plugins/feature-analyzer/skills/feature-analyzer-workspace/canonical/analysis-v2.html`.
When in doubt about styling intent, open that file in a browser. The CSS
inline there is the source of truth for visual decisions; the prose in
this file is the source of truth for structural decisions (which
components, in what order, with what data fields).

## Required components

The HTML doc has ten required components. All must be present even if a section ends up empty (render an empty-state hint instead of dropping the section).

1. **Sidebar nav (sticky, left rail)** — page-section links: Story · Scope · Existing flow · Code requirements · Blockers · Clarifications · Nice-to-have · Assumptions · Copy. One-click jumps; current section highlighted as you scroll.
2. **Header block** — feature name, one-line intent, date, run mode (Mode 1), session-id (small monospace).
3. **Tab strip + Original Story panel (MANDATORY, always visible)** — A two-tab strip sits at the top of `<main>` directly under the header: `Analysis` (default) and `Original Story`. The `Original Story` tab renders the raw story text the reviewer submitted, completely unmodified (no rewriting, no summarising, no question generation). Markdown is rendered with a minimal renderer; headings, lists, code, links preserved. The panel is required on every Mode 1 run, including greenfield and degraded-mode runs. See "Original Story panel" below.
4. **Progress bar** — "X / N answered" counter + fill bar. Tracks user interactions with radio groups. Starts at 0 (Recommended options are NOT pre-checked; the reviewer must actively select).
5. **Scope-report block** — populated by `scope-classifier.md`. Wide left column for Included; stacked right rail for Stripped + Conditional.
6. **Existing-flow trace** — collapsible panel. Populated by `existing-flow-trace.md`. If skipped (greenfield), render a 1-line "Flow trace skipped — story self-declares greenfield" note.
7. **Screen Catalog (Figma walk)** — collapsible panel. Populated by `design-reviewer`'s output per `figma-walk.md`. Renders thumbnails for each visited frame in a horizontal step strip, with per-frame name, annotations, linked Code Connect components, and a flow-graph showing prototype edges. If `figma_unavailable: true`, render a 1-line "No Figma URLs found in story — design questions are text-only" note. If Figma MCP failed, render a Pre-flight callout instead.
8. **Code requirements (diff block)** — collapsible panel. For every `delta` produced by `gap-analyzer`, render a unified diff with a per-block header showing the relative file path.
9. **Priority buckets** — collapsible panel per bucket: 🔴 Blockers · 🟡 Clarifications · 🟢 Nice-to-have. Each panel contains a question-card grid.
10. **Copy controls** — sticky toolbar with: select-all / select-none / blockers-only, **selective copy modal**.

## Design system — dark mode by default

The template uses a near-black layered surface palette with a violet accent, inspired by Linear.app: calm, layered, refined. Fonts are Inter (400-900) and JetBrains Mono.

### Contrast guarantees (WCAG AA on bg-root #0C0C0E)

Every text token used for human-readable content meets WCAG AA 4.5:1 contrast against `--bg-root`. Verified ratios:

| Token | Ratio | Use |
|---|---|---|
| `--text` #F0F0F3 | 17.4:1 | body copy, headings |
| `--text-secondary` #9898A3 | 6.4:1 | sub-labels, meta lines |
| `--text-tertiary` #8B8B95 | 5.5:1 | hints, captions, nav-section titles |
| `--accent` #8B5CF6 | 4.6:1 | active text (borderline; pair with bold/large where possible) |
| `--accent-hover` #A78BFA | 7.0:1 | active text, hover state |
| `--red` #F87171 | 9.3:1 | blocker accents |
| `--amber` #FBBF24 | 12.3:1 | clarification accents |
| `--green` #34D399 | 9.7:1 | nice-to-have / answered |
| `--blue` #60A5FA | 7.8:1 | info accents |
| `--text-disabled` #5A5A65 | 2.8:1 | reserved for truly-disabled state; **never** active content |

When introducing a new text colour, run a contrast check before merging. Tools: WebAIM contrast checker, `chrome devtools → CSS color picker → contrast ratio`. Borders + decorative shapes are exempt from text contrast rules but should still meet WCAG 1.4.11 (3:1) when they convey state (e.g. focus rings, active borders).

Fonts are Inter (400-900) and JetBrains Mono. Load them from Google Fonts:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
```

```css
:root {
  --bg-root:       #0C0C0E;
  --bg-sidebar:    #0E0E11;
  --bg-surface:    #16161A;
  --bg-elevated:   #1C1C22;
  --bg-hover:      #23232B;
  --bg-input:      #1A1A20;

  --border:        #272730;
  --border-hover:  #343440;
  --border-focus:  #4B4B5A;

  --text:          #F0F0F3;
  --text-secondary:#9898A3;
  --text-tertiary: #8B8B95;  /* WCAG AA on bg-root: 5.5:1 */
  --text-disabled: #5A5A65;  /* 2.8:1; for truly-disabled state only */

  --accent:        #8B5CF6;
  --accent-hover:  #A78BFA;
  --accent-bg:     rgba(139,92,246,0.10);
  --accent-bg-soft:rgba(139,92,246,0.06);
  --accent-border: rgba(139,92,246,0.30);
  --accent-glow:   rgba(139,92,246,0.15);

  --red:           #F87171;
  --red-bg:        rgba(248,113,113,0.08);
  --red-border:    rgba(248,113,113,0.25);
  --amber:         #FBBF24;
  --amber-bg:      rgba(251,191,36,0.08);
  --amber-border:  rgba(251,191,36,0.25);
  --green:         #34D399;
  --green-bg:      rgba(52,211,153,0.08);
  --green-border:  rgba(52,211,153,0.25);
  --blue:          #60A5FA;
  --blue-bg:       rgba(96,165,250,0.08);

  --font:          'Inter', -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
  --font-mono:     'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, monospace;

  --radius-sm:     8px;
  --radius-md:     12px;
  --radius-lg:     16px;
  --radius-xl:     20px;
}
```

## Sidebar nav

The sidebar is the navigation backbone. 260px fixed width; `position: sticky; top: 0; height: 100vh` so it stays visible while main scrolls. Scroll-spy updates the active link.

Role filter chips in the sidebar use colour-coded pill style with `active` state. Priority and pillar filter groups are stacked below role. Combined filters use AND logic. Filter state persists in `localStorage`.

```html
<nav class="sidebar">
  <div class="sidebar-logo">
    <div class="label">Feature Analysis · Mode 1</div>
    <h2>{{feature_name}}</h2>
  </div>

  <ul>
    <li><a href="#scope"><span class="nav-icon">◫</span> Scope filter</a></li>
    <li><a href="#flow"><span class="nav-icon">⇢</span> Existing flow</a></li>
    <li><a href="#screens"><span class="nav-icon">▣</span> Screen catalog</a></li>
    <li><a href="#diff"><span class="nav-icon">±</span> Code requirements</a></li>
    <li><a href="#blockers"><span class="nav-icon">●</span> Blockers <span class="badge red">{{n_blockers}}</span></a></li>
    <li><a href="#clarifications"><span class="nav-icon">●</span> Clarifications <span class="badge amber">{{n_clarify}}</span></a></li>
    <li><a href="#nice"><span class="nav-icon">●</span> Nice-to-have <span class="badge green">{{n_nice}}</span></a></li>
    <li><a href="#assumptions"><span class="nav-icon">📌</span> Assumptions</a></li>
    <li><a href="#copy-toolbar"><span class="nav-icon">⧉</span> Copy answers</a></li>
  </ul>

  <hr class="sidebar-divider">
  <div class="sidebar-section-label">Filters</div>

  <div class="sidebar-filters">
    <div class="filter-group">
      <div class="filter-group-label">Role</div>
      <div class="chip-row" data-filter-group="role">
        <button class="chip active" data-filter-role="all">All</button>
        <button class="chip" data-filter-role="PM">PM</button>
        <button class="chip" data-filter-role="Backend">Backend</button>
        <button class="chip" data-filter-role="Design">Design</button>
        <button class="chip" data-filter-role="QA">QA</button>
        <button class="chip" data-filter-role="Compliance">Compliance</button>
        <button class="chip" data-filter-role="DevOps">DevOps</button>
      </div>
    </div>
    <div class="filter-group">
      <div class="filter-group-label">Priority</div>
      <div class="chip-row" data-filter-group="priority">
        <button class="chip active" data-filter-priority="all">All</button>
        <button class="chip red" data-filter-priority="red">Blockers</button>
        <button class="chip amber" data-filter-priority="yellow">Clarify</button>
        <button class="chip green" data-filter-priority="green">Nice</button>
      </div>
    </div>
    <div class="filter-group">
      <div class="filter-group-label">Pillar</div>
      <div class="chip-row" data-filter-group="pillar">
        <button class="chip active" data-filter-pillar="all">All</button>
        <button class="chip" data-filter-pillar="design">design</button>
        <button class="chip" data-filter-pillar="tech">tech</button>
        <button class="chip" data-filter-pillar="qa">qa</button>
        <button class="chip" data-filter-pillar="domain">domain</button>
      </div>
    </div>
  </div>
</nav>
```

## Page header + progress bar

```html
<div class="page-header">
  <div class="run-badge">{{session_id}} &nbsp;·&nbsp; {{date}}</div>
  <h1>{{feature_name}}</h1>
  <div class="intent">{{intent}}</div>
  <div class="page-meta">
    <span>Mode 1</span>
    <span>·</span>
    <span>{{n_total}} questions</span>
    <span>·</span>
    <span>{{n_diff_blocks}} diff blocks</span>
    <span>·</span>
    <span>{{scope_summary}}</span>
  </div>
  <div class="progress-bar-wrap">
    <div class="progress-label">
      <span>Progress</span>
      <strong><span id="answered-count">0</span> / {{n_total}} answered</strong>
    </div>
    <div class="progress-track">
      <div class="progress-fill" id="progress-fill"></div>
    </div>
  </div>
</div>
```

**Progress bar semantics:** "answered" means the reviewer has fired a `change` event on any radio in the card — i.e. they made an active choice. The Recommended option is NOT pre-checked; `input[type=radio]` elements carry no `checked` attribute in the HTML. The JS tracks answered qids in a `Set` keyed by `data-qid` and fires on every `change`. This avoids the bug where a pre-selected Recommended makes the bar start at 100%. The counter uses `aria-live="polite"` so screen readers announce progress changes.

## Tab strip + Original Story panel

The very first interactive element in `<main>` (under the header, above the progress bar) is a two-tab strip. The reviewer should ALWAYS be one click away from the source story — without it, every question card is unverifiable.

### Why this is mandatory

- Reviewers need to cross-check questions against the story that produced them. Without the story inline, they alt-tab to a Slack / Jira / Linear / Notion tab and break flow.
- Skill regression review needs the story to be embedded in the artifact — a `.feature-analyzer/<slug>/<session>/00-preflight.json` file is the source of truth, but the rendered HTML must be self-contained for sharing.
- Greenfield runs especially benefit — when there's no flow trace and no diff, the story IS the only context for the questions.

### Behaviour

- **Tabs**: `Analysis` (default, selected) and `Original Story`.
- **Persistence**: active tab persisted in `localStorage` key `fa-active-tab`. A returning reviewer lands on whichever tab they last viewed.
- **Keyboard**: arrow-left/right cycles tabs when the strip has focus; numeric `1` jumps to Analysis, `2` to Story (with `aria-keyshortcuts`).
- **Visibility**: switching tabs swaps `display: block` ↔ `display: none` on the two `<section>` panels. Both panels stay in the DOM so anchor links from the sidebar still work (the click handler activates the Analysis tab before scrolling).
- **No transformation**: the Story panel renders the raw text the reviewer submitted. No summarising, no re-styling, no inserting links to questions. The minimal markdown renderer handles headings, lists, code fences, blockquotes, inline code, and bold/italic. Anything more exotic falls back to a `<pre>` block so the text is never lost.
- **Diff against story**: each question card carries a "View source" affordance that opens the Story tab and scrolls to the first matching keyword (using `mark.js`-style highlighting). Out of scope for v1; tracked as iter-4 in the iteration plan.

### HTML pattern

```html
<div class="tab-strip" role="tablist" aria-label="View">
  <button class="tab active" role="tab" aria-selected="true"
          aria-controls="tab-analysis" id="tab-btn-analysis"
          data-tab="analysis" aria-keyshortcuts="1">
    Analysis
  </button>
  <button class="tab" role="tab" aria-selected="false"
          aria-controls="tab-story" id="tab-btn-story"
          data-tab="story" aria-keyshortcuts="2">
    Original Story
    <span class="tab-hint">⌥2</span>
  </button>
</div>

<section id="tab-analysis" role="tabpanel"
         aria-labelledby="tab-btn-analysis" class="tab-panel active">
  <!-- progress bar, copy toolbar, scope, flow, diff, priority buckets, assumptions -->
</section>

<section id="tab-story" role="tabpanel"
         aria-labelledby="tab-btn-story" class="tab-panel" hidden>
  <div class="story-meta">
    <span>Source story · submitted at run start · not modified</span>
    <button class="toolbar-btn" id="copy-story">Copy story</button>
  </div>
  <article class="story-body">
    {{rendered_story_markdown}}
  </article>
</section>
```

### CSS pattern

```css
.tab-strip {
  display: flex; gap: 0;
  border-bottom: 1px solid var(--border);
  margin-bottom: 32px;
}
.tab {
  appearance: none; background: none; border: none;
  color: var(--text-tertiary);
  padding: 16px 24px;
  font: 600 15px var(--font);
  cursor: pointer;
  display: inline-flex; align-items: center; gap: 8px;
  border-bottom: 2px solid transparent;
  margin-bottom: -1px;
  transition: all 120ms ease;
  letter-spacing: -0.01em;
}
.tab:hover { color: var(--text-secondary); }
.tab.active { color: var(--text); border-bottom-color: var(--accent); }
.tab-hint { font: 500 11px var(--font-mono); color: var(--text-disabled);
            padding: 2px 6px; background: var(--bg-elevated); border-radius: 4px; }
.tab.active .tab-hint { color: var(--accent-hover); background: var(--accent-bg-soft); }
.tab-panel[hidden] { display: none; }
.tab-panel.active { display: block; }
.story-body { padding: 8px 0 48px; font: 16px/1.75 var(--font); }
.story-body h1 { font-size: 30px; font-weight: 900; letter-spacing: -0.04em;
                 margin: 0 0 20px; color: var(--text); }
.story-body h2 { font-size: 22px; font-weight: 800; color: var(--text-secondary);
                 margin: 32px 0 14px; letter-spacing: -0.02em; }
.story-body h3 { font-size: 14px; text-transform: uppercase; letter-spacing: 0.08em;
                 color: var(--text-tertiary); margin: 28px 0 10px; font-weight: 800; }
.story-body p { color: var(--text-secondary); margin-bottom: 16px;
                max-width: 900px; line-height: 1.75; }
.story-body ul, .story-body ol { padding-left: 28px; margin: 10px 0 20px;
                                 display: flex; flex-direction: column; gap: 8px; }
.story-body li { color: var(--text-secondary); line-height: 1.65; font-size: 15px; }
.story-body code { font-family: var(--font-mono); font-size: 14px;
                   background: var(--bg-hover); padding: 3px 8px;
                   border-radius: 6px; color: var(--accent-hover); font-weight: 500; }
.story-body pre { background: #08080C; padding: 18px 20px;
                  border-radius: var(--radius-md); overflow: auto;
                  border: 1px solid var(--border); margin: 16px 0;
                  font-family: var(--font-mono); font-size: 13px;
                  line-height: 1.85; color: #83838F; }
.story-body blockquote { border-left: 3px solid var(--border);
                         padding: 8px 18px; color: var(--text-tertiary);
                         margin: 16px 0; font-style: italic; }
.story-body strong { color: var(--text); font-weight: 700; }
.story-body em { color: var(--text-tertiary); }
```

### JS pattern

```js
const TAB_KEY = 'fa-active-tab';
function activateTab(name) {
  document.querySelectorAll('.tab').forEach(btn => {
    const isActive = btn.dataset.tab === name;
    btn.classList.toggle('active', isActive);
    btn.setAttribute('aria-selected', isActive);
  });
  document.querySelectorAll('.tab-panel').forEach(panel => {
    const isActive = panel.id === `tab-${name}`;
    panel.classList.toggle('active', isActive);
    panel.hidden = !isActive;
  });
  localStorage.setItem(TAB_KEY, name);
}
document.querySelectorAll('.tab').forEach(btn => {
  btn.addEventListener('click', () => activateTab(btn.dataset.tab));
});
window.addEventListener('keydown', e => {
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
  if (e.key === '1') activateTab('analysis');
  if (e.key === '2') activateTab('story');
});
// Sidebar anchor links: activate Analysis tab first, then scroll
document.querySelectorAll('nav.sidebar a[href^="#"]').forEach(a => {
  a.addEventListener('click', () => {
    if (a.getAttribute('href') !== '#tab-story') activateTab('analysis');
  });
});
// Hydrate
activateTab(localStorage.getItem(TAB_KEY) || 'analysis');
```

### Minimal markdown renderer

For the story panel only, a small markdown-to-HTML helper runs at render time (in the skill, not in the browser — the skill emits already-rendered HTML inside `<article class="story-body">`). The renderer covers:

| Source | Output |
|---|---|
| `# Heading` | `<h1>` |
| `## Heading` | `<h2>` |
| `### Heading` | `<h3>` |
| `- bullet` / `* bullet` | `<ul><li>` |
| `1. ordered` | `<ol><li>` |
| ` ```code``` ` (triple-backtick fenced) | `<pre><code>` |
| `` `inline` `` | `<code>` |
| `**bold**` | `<strong>` |
| `*italic*` / `_italic_` | `<em>` |
| `> quote` | `<blockquote>` |
| `[text](url)` | `<a href>` with `rel="noopener"` |
| blank-line-separated paragraph | `<p>` |
| anything else | passed through inside its block |

If the renderer encounters a construct it doesn't recognise (e.g. tables, footnotes, custom shortcodes), it wraps the entire offending block in a `<pre class="raw-block">` rather than silently dropping content. This guarantees the reviewer never loses information.

## Copy toolbar

Sticky below the header; stays visible as the user scrolls questions.

```html
<div class="copy-toolbar" id="copy-toolbar">
  <button class="toolbar-btn" id="select-all">Select all</button>
  <button class="toolbar-btn" id="select-none">Select none</button>
  <button class="toolbar-btn" id="select-blockers">Blockers only</button>
  <span class="toolbar-spacer"></span>
  <button class="toolbar-btn primary" id="open-copy-modal">⧉ Copy selected…</button>
</div>
```

## Scope-report block

Wide left column for Included (spans 2 rows); right rail stacks Stripped above Conditional. This avoids the equal-thirds layout that wastes space when Conditional has only 1 item.

```html
<div class="scope-grid" id="scope">
  <div class="scope-col included">
    <h4>Included</h4>
    <ul>{{included_items}}</ul>   <!-- each <li><span>…</span></li> -->
  </div>
  <div class="scope-col stripped">
    <h4>Stripped</h4>
    <ul>{{stripped_items}}</ul>
  </div>
  <div class="scope-col conditional">
    <h4>Conditional</h4>
    <ul>{{conditional_items}}</ul>
  </div>
</div>
```

Grid rule: `grid-template-columns: 1fr 280px; grid-template-rows: auto auto;` with `.included { grid-row: 1 / 3; }`.

## Existing-flow trace

Collapsible `<details class="panel">`. Summary line shows avg confidence. If `partial: true`, open with a prominent amber callout explaining degraded mode.

```html
<details class="panel" id="flow" open>
  <summary>
    Flow audit
    <span class="summary-label">avg confidence: {{avg_confidence}}</span>
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">
    <!-- If partial: true -->
    <div class="partial-callout">
      <span class="icon">⚠</span>
      <div>Flow trace ran in <strong>degraded mode</strong> (<code>partial: true</code>).
      No <code>file:line</code> cites claimed. All auto-answer candidates surfaced.</div>
    </div>

    <!-- SDKs probed list -->
    <ul class="facts-list">
      <li><span class="conf-chip low">not_located</span> &nbsp;<code>{{sdk_name}}</code> — {{status_note}}</li>
    </ul>

    <!-- Inferred chain -->
    <ol class="flow-chain">
      <li><b>UI</b> — {{ui_component}} <span class="conf-chip {{confidence}}">{{confidence}}</span></li>
      <li><b>ViewModel</b> — {{viewmodel}} <span class="conf-chip {{confidence}}">{{confidence}}</span></li>
      <!-- … -->
    </ol>
  </div>
</details>
```

If the story is greenfield (no existing flow to trace), render a single callout:

```html
<div class="partial-callout">
  <span class="icon">ℹ</span>
  <div>Flow trace skipped — story self-declares greenfield. No existing component chain to audit.</div>
</div>
```

## Screen Catalog (Figma walk)

Renders the screens `design-reviewer` captured. For each Figma target, the panel contains a step strip (linear sequence of thumbnails representing the prototype flow), a flow-graph subhead if branches exist, and per-screen annotations.

```html
<details class="panel" id="screens" open>
  <summary>
    Screen catalog
    <span class="summary-label">{{n_screens}} screens · {{n_flows}} flow{{n_flows>1?'s':''}}</span>
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">

    <!-- Figma unavailable -->
    <div class="partial-callout">
      <span class="icon">ℹ</span>
      <div>No Figma URLs found in story. Design questions are text-only.</div>
    </div>

    <!-- Or: Figma MCP failure -->
    <div class="partial-callout warn">
      <span class="icon">⚠</span>
      <div>Figma MCP unreachable. <code>{{failure_reason}}</code></div>
    </div>

    <!-- Per flow-graph: horizontal step strip -->
    <div class="screen-strip">
      <div class="screen-tile" data-node-id="42:198">
        <img src="{{screenshot_path}}" alt="{{screen_name}}" loading="lazy">
        <div class="screen-meta">
          <div class="screen-name">Duration sheet — current state</div>
          <div class="screen-anno">{{designer_annotation_or_blank}}</div>
        </div>
      </div>
      <div class="screen-arrow" aria-hidden="true">→</div>
      <div class="screen-tile" data-node-id="42:215">
        <img src="{{screenshot_path}}" alt="Add custom configurator">
        <div class="screen-meta">
          <div class="screen-name">Add custom configurator</div>
          <div class="screen-anno">"Validate range 1s–24h"</div>
        </div>
      </div>
      <!-- repeat with arrows between -->
    </div>

    <!-- Design tokens referenced -->
    <div class="tokens-section">
      <h4>Design tokens referenced</h4>
      <table class="tokens-table">
        <thead><tr><th>Figma token</th><th>Value</th><th>Suggested app token</th></tr></thead>
        <tbody>
          <tr><td><code>color/surface/elevated</code></td><td>#1E293B</td><td>Surface.Elevated</td></tr>
        </tbody>
      </table>
    </div>

    <!-- Code Connect cross-reference -->
    <div class="cc-section">
      <h4>Linked Code Connect components</h4>
      <ul>
        <li><code>ChipRow</code> (from Figma) → <code>app/.../ChipRow.kt</code></li>
      </ul>
    </div>

  </div>
</details>
```

```css
.screen-strip { display: flex; flex-wrap: wrap; gap: 12px; align-items: stretch;
                padding: 12px 0; overflow-x: auto; }
.screen-tile { background: var(--bg-surface); border: 1px solid var(--border);
               border-radius: var(--radius-md); overflow: hidden; flex: 0 0 240px;
               display: flex; flex-direction: column;
               transition: transform 150ms ease, border-color 150ms ease; }
.screen-tile:hover { transform: translateY(-2px); border-color: var(--border-hover); cursor: pointer; }
.screen-tile img { width: 100%; aspect-ratio: 9 / 16; object-fit: cover; background: var(--bg-elevated); }
.screen-meta { padding: 10px 12px; }
.screen-name { font: 500 13px/1.3 var(--font); color: var(--text); }
.screen-anno { font: 400 12px/1.4 var(--font); color: var(--text-secondary); margin-top: 4px;
               font-style: italic; }
.screen-arrow { align-self: center; color: var(--text-tertiary); font-size: 18px; }

.tokens-section, .cc-section { margin-top: 18px; }
.tokens-section h4, .cc-section h4 { font: 500 13px/1.3 var(--font); color: var(--text-secondary);
                                     margin: 12px 0 6px; }
.tokens-table { width: 100%; border-collapse: collapse; font-size: 13px; }
.tokens-table th, .tokens-table td { padding: 6px 8px; text-align: left;
                                     border-bottom: 1px solid var(--border); }
.tokens-table th { color: var(--text-secondary); font-weight: 500; }
.tokens-table code { font: 12px/1 var(--font-mono); }
```

Clicking a `.screen-tile` opens the screenshot in a lightbox modal at full resolution (lightbox markup + JS minimal; reuses the copy-modal pattern with `display: flex` overlay). Right-click → "Open original" goes to the Figma URL in a new tab if `data-figma-url` is set on the tile.

## Code requirements — diff block

Each delta gets its own bordered card with a header showing the file path. The diff body uses a dark terminal look (`background: #010409`). Lines are `<span>` elements with class `diff-line add|del|meta|hunk`.

```html
<details class="panel" id="diff" open>
  <summary>
    Delta from existing flow
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">
    <!-- Placeholder callout if no repo access -->
    <div class="partial-callout">…</div>

    <div class="delta">
      <div class="delta-header">
        <span class="delta-index">Δ1</span>
        <span class="delta-title">{{delta_title}}</span>
        <span class="delta-filepath">{{relative_file_path}}</span>
      </div>
      <div class="delta-desc"><p>{{current_state}} → {{target_state}}</p></div>
      <pre class="codediff"><code>
<span class="diff-line meta">--- a/{{file_path}}</span>
<span class="diff-line meta">+++ b/{{file_path}}</span>
<span class="diff-line hunk">@@ {{hunk_header}} @@</span>
<span class="diff-line"> {{context_line}}</span>
<span class="diff-line del">-{{removed_line}}</span>
<span class="diff-line add">+{{added_line}}</span>
      </code></pre>
      <div class="delta-evidence">Evidence: {{evidence_cite}}</div>
    </div>
    <!-- repeat .delta up to 5 times -->
  </div>
</details>
```

Rules:
- Only include diffs grounded in a `gap-analyzer.delta[]` entry whose evidence has `file:line` cites. No fabricated diffs.
- If gap-analyzer ran in degraded mode, render placeholder diffs with `// TODO: target shape — repo not accessible at trace time`.
- Maximum 5 diff blocks per doc. Overflow → bucket the rest under "Further deltas" with a one-line description each.

## Priority buckets

Each bucket is a `<details class="panel bucket-{color}">`. The left border color (3px) signals priority at a glance without needing to read the heading.

```html
<details class="panel bucket-red" id="blockers" open>
  <summary>
    <span class="summary-icon">🔴</span> Must answer before implementation starts
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">
    <div class="question-grid">
      {{blocker_cards}}
    </div>
  </div>
</details>

<details class="panel bucket-yellow" id="clarifications" open>
  <summary>
    <span class="summary-icon">🟡</span> Should clarify before sprint ends
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">
    <div class="question-grid">
      {{clarify_cards}}
    </div>
  </div>
</details>

<details class="panel bucket-green" id="nice">
  <summary>
    <span class="summary-icon">🟢</span> Address when bandwidth allows
    <span class="summary-chevron">›</span>
  </summary>
  <div class="panel-body">
    <div class="question-grid">
      {{nice_cards}}
    </div>
  </div>
</details>
```

The question grid is single-column by default; switches to 2-column above 1440px viewport (where each card has ≥560px — comfortable for radio-pill content). The breakpoint is set at 1440px viewport rather than 1100px because the 260px sidebar leaves only ~840px of main at 1100px, which is too narrow for two pill-option cards.

## Question card

Card layout clusters: meta-row (checkbox + role + pillar + confidence + per-card copy) at top; question + impact + reason-not-derivable in the body; radio pills below; card footer = override input + stable qid.

Radio pills are NOT pre-checked. The Recommended option is visually distinguished by a `★ Rec` badge inside the label, not by `checked`. The reviewer must click to register an answer.

```html
<section class="question-card priority-{{priority}}"
         data-qid="{{qid}}"
         data-role="{{role}}"
         data-pillar="{{pillar}}"
         data-priority="{{priority}}">

  <div class="card-meta-row">
    <input type="checkbox" class="card-select select-q" title="Include in copy">
    <span class="role-tag {{role}}">{{role}}</span>
    <span class="pillar-tag">{{pillar}}</span>
    <span class="conf-chip {{confidence}}">{{confidence}}</span>
    <button class="card-copy-btn copy-btn">Copy</button>
  </div>

  <div class="card-body">
    <h4>{{question}}</h4>
    <p class="card-impact"><strong>Decision affected:</strong> {{impact}}</p>
    <p class="card-reason">
      <strong>Not derivable because:</strong> {{reason_not_derivable}}
    </p>

    <div class="card-options">
      <!-- Recommended option — note: NO checked attribute -->
      <label class="pill recommended">
        <input type="radio" name="{{qid}}" value="{{rec_label}}">
        <span class="pill-rec-badge">★ Rec</span>
        <span class="pill-text">
          {{rec_label}}
          <span class="pill-reason">{{rec_reason}}</span>
        </span>
      </label>

      <!-- Other options -->
      <label class="pill">
        <input type="radio" name="{{qid}}" value="{{opt_b}}">
        <span class="pill-text">{{opt_b}}</span>
      </label>
      <label class="pill">
        <input type="radio" name="{{qid}}" value="{{opt_c}}">
        <span class="pill-text">{{opt_c}}</span>
      </label>
    </div>
  </div>

  <div class="card-footer">
    <input class="override-input override" placeholder="Other / override…">
    <span class="qid">{{qid}}</span>
  </div>
</section>
```

Per-card fields:

- **Header checkbox (`.select-q`)** — defaults checked (set by JS init). Drives selective copy.
- **Role tag** — colour-coded by role: PM (blue), Backend (purple), Design (orange), QA (green), Compliance (amber), DevOps (grey).
- **Pillar tag** — monospace badge (`design|tech|qa|domain`). Distinct from role.
- **Confidence chip** — `high` (green), `medium` (amber), `low` (grey). 10px monospace uppercase.
- **Per-card copy** — copies that Q+A as plain text.
- **Reason-not-derivable** — mandatory italic block. Reviewer sees *why* this couldn't be answered from code.
- **Override input** — supplements the radio options; dark input field.
- **Stable qid** — dim monospace at bottom-right.

## Copy controls (toolbar + selective copy modal)

```html
<div class="modal-backdrop" id="copy-modal">
  <div class="modal">
    <h3>Copy selected answers</h3>
    <p class="modal-sub">
      <span id="modal-count">0</span> of <span id="modal-total">{{n_total}}</span>
      questions selected. Review below, then click Copy.
    </p>
    <pre id="copy-preview">(no questions selected)</pre>
    <div class="modal-actions">
      <button class="toolbar-btn primary" id="copy-final">Copy to clipboard</button>
      <button class="toolbar-btn" id="modal-close">Close</button>
    </div>
  </div>
</div>
```

Output format (plain text, one block per question):

```
Q (Backend / blocker): Does the /history endpoint accept arbitrary duration values?
  → A: Accept arbitrary integer seconds via existing duration param

Q (Design / clarification): How should custom-duration chips be ordered?
  → A: Ascending by seconds, interleaved with built-ins
```

## Filter chips

Three filter groups in the sidebar: Role · Priority · Pillar. Each group has an "All" chip and per-value chips. Combined filters use AND logic. State persists in `localStorage`.

Chip visual states:
- Default: `border: 1px solid var(--border); color: var(--text-muted)`
- Hover: `background: var(--elevated); color: var(--text)`
- Active: `background: var(--elevated); border-color: var(--text-dim); color: var(--text)`
- Active + Priority: colour-tinted (red/amber/green bg + border-color match)

## Template skeleton

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Feature Analysis — {{feature_name}}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800;900&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg-root:#0C0C0E; --bg-sidebar:#0E0E11; --bg-surface:#16161A;
      --bg-elevated:#1C1C22; --bg-hover:#23232B; --bg-input:#1A1A20;
      --border:#272730; --border-hover:#343440; --border-focus:#4B4B5A;
      --text:#F0F0F3; --text-secondary:#9898A3;
      --text-tertiary:#63636D; --text-disabled:#44444D;
      --accent:#8B5CF6; --accent-hover:#A78BFA;
      --accent-bg:rgba(139,92,246,0.10); --accent-bg-soft:rgba(139,92,246,0.06);
      --accent-border:rgba(139,92,246,0.30); --accent-glow:rgba(139,92,246,0.15);
      --red:#F87171; --red-bg:rgba(248,113,113,0.08); --red-border:rgba(248,113,113,0.25);
      --amber:#FBBF24; --amber-bg:rgba(251,191,36,0.08); --amber-border:rgba(251,191,36,0.25);
      --green:#34D399; --green-bg:rgba(52,211,153,0.08); --green-border:rgba(52,211,153,0.25);
      --blue:#60A5FA; --blue-bg:rgba(96,165,250,0.08);
      --font:'Inter',-apple-system,BlinkMacSystemFont,system-ui,sans-serif;
      --font-mono:'JetBrains Mono',ui-monospace,SFMono-Regular,Menlo,monospace;
      --radius-sm:8px; --radius-md:12px; --radius-lg:16px; --radius-xl:20px;
    }
    *, *::before, *::after { box-sizing:border-box; margin:0; padding:0; }
    html { scroll-behavior:smooth; -webkit-font-smoothing:antialiased; }
    body {
      font-family:var(--font); font-size:16px; line-height:1.65;
      color:var(--text); background:var(--bg-root);
      display:grid; grid-template-columns:280px 1fr; min-height:100vh;
      letter-spacing:-0.01em;
    }
    /* Sidebar */
    nav.sidebar { position:sticky; top:0; height:100vh; overflow-y:auto;
      background:var(--bg-sidebar); border-right:1px solid var(--border);
      display:flex; flex-direction:column; padding:0; }
    .sidebar-header { padding:28px 24px 24px; border-bottom:1px solid var(--border); }
    .sidebar-header h2 { font-size:22px; font-weight:800; letter-spacing:-0.03em;
                         color:var(--text); line-height:1.2; }
    nav.sidebar li a { display:flex; align-items:center; gap:10px;
      padding:8px 12px; border-radius:8px; color:var(--text-secondary);
      font-size:14px; font-weight:450; transition:all 120ms ease; }
    nav.sidebar li a:hover { background:var(--bg-elevated); color:var(--text); }
    nav.sidebar li a.active { background:var(--bg-elevated); color:var(--text);
                              font-weight:600; }
    nav.sidebar li a.active::before { content:""; position:absolute;
      left:0; top:50%; transform:translateY(-50%);
      width:3px; height:18px; background:var(--accent);
      border-radius:0 3px 3px 0; }
    .nav-icon { width:18px; text-align:center; font-size:14px; opacity:0.7; }
    .badge { font-size:11px; font-weight:700; padding:2px 8px;
             border-radius:99px; font-family:var(--font-mono); margin-left:auto; }
    .badge.red   { color:var(--red);   background:var(--red-bg); }
    .badge.amber { color:var(--amber); background:var(--amber-bg); }
    .badge.green { color:var(--green); background:var(--green-bg); }
    .badge.blue  { color:var(--blue);  background:var(--blue-bg); }
    /* Filters toggle */
    .filters-section { border-top:1px solid var(--border); margin-top:auto;
                       background:rgba(0,0,0,0.2); }
    .filters-toggle { width:100%; display:flex; align-items:center;
      justify-content:space-between; padding:14px 24px;
      background:none; border:none; color:var(--text-secondary);
      font:600 11px var(--font); letter-spacing:0.08em;
      text-transform:uppercase; cursor:pointer; }
    .filters-toggle[aria-expanded="true"] .filters-chevron { transform:rotate(90deg); }
    .filters-body { padding:0 16px 20px; display:none; }
    .filters-body.open { display:block; }
    /* Chips */
    .chip { font-size:12px; font-weight:500; padding:5px 12px;
            border:1px solid var(--border); background:transparent;
            border-radius:99px; cursor:pointer; color:var(--text-secondary);
            transition:all 120ms ease; font-family:var(--font); }
    .chip:hover { background:var(--bg-hover); color:var(--text);
                  border-color:var(--border-hover); }
    .chip.active { background:var(--accent-bg); color:var(--accent-hover);
                   border-color:var(--accent-border); font-weight:600; }
    .chip.active.red   { color:var(--red);   background:var(--red-bg);   border-color:var(--red-border); }
    .chip.active.amber { color:var(--amber); background:var(--amber-bg); border-color:var(--amber-border); }
    /* Main */
    main { padding:48px 56px 120px; max-width:1100px; margin:0 auto; width:100%; }
    .page-header { padding-bottom:32px; border-bottom:1px solid var(--border);
                   margin-bottom:32px; }
    .page-header h1 { font-size:42px; font-weight:900; letter-spacing:-0.04em;
                      line-height:1.1; margin-bottom:12px; color:var(--text); }
    .run-badge { display:inline-flex; align-items:center; gap:8px;
                 font-size:12px; font-weight:600; color:var(--accent-hover);
                 background:var(--accent-bg-soft); border:1px solid var(--accent-border);
                 padding:6px 14px; border-radius:99px; margin-bottom:16px;
                 font-family:var(--font-mono); letter-spacing:0.02em; }
    .progress-fill { height:100%; width:0%;
                     background:linear-gradient(90deg, var(--accent), var(--accent-hover));
                     border-radius:99px;
                     transition:width 500ms cubic-bezier(0.4, 0, 0.2, 1); }
    /* Copy toolbar */
    .copy-toolbar { position:sticky; top:0; z-index:20;
      background:linear-gradient(180deg, var(--bg-root) 0%, rgba(12,12,14,0.97) 100%);
      border-bottom:1px solid var(--border); padding:14px 0; margin-bottom:36px;
      display:flex; align-items:center; gap:8px; flex-wrap:wrap;
      backdrop-filter:blur(12px); }
    .toolbar-btn { font:500 14px var(--font); padding:8px 16px;
      border:1px solid var(--border); background:var(--bg-surface);
      color:var(--text-secondary); border-radius:var(--radius-md);
      cursor:pointer; transition:all 120ms ease; }
    .toolbar-btn:hover { background:var(--bg-hover); color:var(--text);
                         border-color:var(--border-hover); }
    .toolbar-btn.primary { background:var(--accent); color:#fff;
                           border-color:var(--accent); font-weight:700; }
    .toolbar-btn.primary:hover { background:var(--accent-hover);
                                 border-color:var(--accent-hover); }
    /* Scope grid */
    .scope-grid { display:grid; grid-template-columns:1fr 320px; gap:12px; }
    .scope-col { padding:24px; border-radius:var(--radius-lg);
                 border:1px solid var(--border);
                 box-shadow:0 1px 0 rgba(255,255,255,0.03) inset; }
    .scope-col.included    { grid-row:1/3; background:var(--green-bg);
                             border-color:var(--green-border); border-left:3px solid var(--green); }
    .scope-col.stripped    { background:var(--bg-elevated); }
    .scope-col.conditional { background:var(--amber-bg);
                             border-color:var(--amber-border); border-left:3px solid var(--amber); }
    /* Panels */
    details.panel { background:var(--bg-surface); border:1px solid var(--border);
                    border-radius:var(--radius-lg); margin:0 0 20px; overflow:hidden;
                    box-shadow:0 1px 0 rgba(255,255,255,0.03) inset; }
    details.panel summary { display:flex; align-items:center; gap:10px;
      padding:18px 24px; font-size:15px; font-weight:700; cursor:pointer;
      color:var(--text); list-style:none; user-select:none; }
    details.panel summary::-webkit-details-marker { display:none; }
    details.panel[open] summary { border-bottom:1px solid var(--border);
                                  background:var(--bg-elevated); }
    .panel-body { padding:24px; }
    details.panel.bucket-red    { border-left:3px solid var(--red); }
    details.panel.bucket-yellow { border-left:3px solid var(--amber); }
    details.panel.bucket-green  { border-left:3px solid var(--green); }
    /* Diff blocks */
    .codediff { background:#08080C; color:#83838F;
                font-family:var(--font-mono); font-size:13px; line-height:1.85;
                overflow-x:auto; border-top:1px solid var(--border); }
    .diff-line { display:block; padding:0 18px; white-space:pre;
                 border-left:3px solid transparent; line-height:1.85;
                 font-family:var(--font-mono); font-size:13px; }
    .diff-line.add  { color:#86EFAC; background:rgba(52,211,153,0.06);
                      border-left-color:rgba(52,211,153,0.4); }
    .diff-line.del  { color:#FCA5A5; background:rgba(248,113,113,0.06);
                      border-left-color:rgba(248,113,113,0.4); }
    .diff-line.meta { color:#52525B; }
    .diff-line.hunk { color:#93C5FD; background:rgba(96,165,250,0.04); }
    /* Question cards — single column, spacious, big type */
    .question-grid { display:flex; flex-direction:column; gap:24px; max-width:900px; margin:0 auto; width:100%; align-items:stretch; }
    /* Card body internals centred (user spec) */
    .question-card .card-body { text-align:center; }
    .question-card .card-body h4 { text-align:center; }
    .question-card .card-options { align-items:center; }
    .question-card .card-options > * { max-width:640px; width:100%; }
    .question-card .card-footer { justify-content:center; }
    .question-card .card-override { text-align:center; }
    .question-card { background:var(--bg-surface); border:1px solid var(--border);
                     border-radius:var(--radius-xl); overflow:hidden;
                     transition:all 200ms ease; display:flex; flex-direction:column;
                     box-shadow:0 1px 0 rgba(255,255,255,0.03) inset,
                                0 2px 16px -8px rgba(0,0,0,0.4); }
    .question-card:hover { transform:translateY(-2px);
                           border-color:var(--border-hover); }
    .question-card.priority-red    { border-left:3px solid var(--red); }
    .question-card.priority-yellow { border-left:3px solid var(--amber); }
    .question-card.priority-green  { border-left:3px solid var(--green); }
    /* Pills */
    .pill { display:flex; align-items:flex-start; gap:12px;
            padding:14px 18px; border:1px solid var(--border);
            border-radius:var(--radius-md); cursor:pointer;
            transition:all 120ms ease; font-size:15px;
            color:var(--text-secondary); line-height:1.55;
            background:var(--bg-elevated); }
    .pill:hover { background:var(--bg-hover); color:var(--text);
                  border-color:var(--border-hover); transform:translateX(3px); }
    .pill.recommended { border-color:var(--green-border);
                        background:var(--green-bg); color:var(--text); }
    /* Role tags */
    .role-tag { font-size:12px; font-weight:700; padding:4px 12px;
                border-radius:99px; letter-spacing:0.02em; }
    .role-tag.PM         { color:#93C5FD; background:rgba(147,197,253,0.10); border:1px solid rgba(147,197,253,0.15); }
    .role-tag.Backend    { color:#C4B5FD; background:rgba(196,181,253,0.10); border:1px solid rgba(196,181,253,0.15); }
    .role-tag.Design     { color:#FDBA74; background:rgba(253,186,116,0.10); border:1px solid rgba(253,186,116,0.15); }
    .role-tag.QA         { color:#86EFAC; background:rgba(134,239,172,0.10); border:1px solid rgba(134,239,172,0.15); }
    .role-tag.Compliance { color:#F9A8D4; background:rgba(249,168,212,0.10); border:1px solid rgba(249,168,212,0.15); }
    .role-tag.DevOps     { color:#CBD5E1; background:rgba(203,213,225,0.10); border:1px solid rgba(203,213,225,0.15); }
    /* Pillar */
    .pillar-tag { font-size:11px; font-weight:600; font-family:var(--font-mono);
                  padding:4px 10px; border-radius:6px;
                  color:var(--text-tertiary); background:var(--bg-hover); }
    /* Confidence chip */
    .conf-chip { display:inline-flex; align-items:center;
                 font-size:10px; font-weight:800; font-family:var(--font-mono);
                 padding:4px 10px; border-radius:99px;
                 text-transform:uppercase; letter-spacing:0.08em; white-space:nowrap; }
    .conf-chip.high   { color:var(--green);          background:var(--green-bg);  border:1px solid var(--green-border); }
    .conf-chip.medium { color:var(--amber);          background:var(--amber-bg);  border:1px solid var(--amber-border); }
    .conf-chip.low    { color:var(--text-tertiary);  background:var(--bg-hover); border:1px solid var(--border); }
    /* Modal */
    .modal-backdrop { position:fixed; inset:0; background:rgba(0,0,0,0.65);
                      backdrop-filter:blur(8px); display:none;
                      align-items:center; justify-content:center; z-index:100; }
    .modal-backdrop.open { display:flex; }
    .modal { background:var(--bg-surface); border:1px solid var(--border);
             border-radius:var(--radius-xl); padding:32px;
             max-width:720px; max-height:85vh; overflow-y:auto; width:90%;
             box-shadow:0 32px 80px rgba(0,0,0,0.5); }
    /* A11y */
    *:focus-visible { outline:2.5px solid var(--accent); outline-offset:2px; }
    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after {
        animation-duration:0.01ms !important;
        transition-duration:0.01ms !important;
      }
    }
    /* … full CSS as in the canonical reference render … */
  </style>
</head>
<body>
  <nav class="sidebar"> <!-- as above --> </nav>

  <main>
    <div class="page-header">
      <div class="run-badge">{{session_id}} · {{date}}</div>
      <h1>{{feature_name}}</h1>
      <div class="intent">{{intent}}</div>
      <div class="page-meta">…</div>
      <div class="progress-bar-wrap">…</div>
    </div>

    <div class="copy-toolbar" id="copy-toolbar">…</div>

    <div id="scope">
      <div class="section-header"><h2>Scope filter</h2></div>
      <hr class="section-divider">
      <div class="scope-grid">…</div>
    </div>

    <div class="section-header"><h2>Existing flow</h2></div>
    <hr class="section-divider">
    <details class="panel" id="flow" open>…</details>

    <div class="section-header"><h2>Code requirements</h2></div>
    <hr class="section-divider">
    <details class="panel" id="diff" open>…</details>

    <div class="section-header" id="blockers"><h2>🔴 Blockers</h2></div>
    <hr class="section-divider">
    <details class="panel bucket-red" open>
      <div class="panel-body"><div class="question-grid">{{blocker_cards}}</div></div>
    </details>

    <div class="section-header" id="clarifications"><h2>🟡 Clarifications</h2></div>
    <hr class="section-divider">
    <details class="panel bucket-yellow" open>
      <div class="panel-body"><div class="question-grid">{{clarify_cards}}</div></div>
    </details>

    <div class="section-header" id="nice"><h2>🟢 Nice-to-have</h2></div>
    <hr class="section-divider">
    <details class="panel bucket-green">
      <div class="panel-body"><div class="question-grid">{{nice_cards}}</div></div>
    </details>

    <div class="section-header" id="assumptions"><h2>Assumptions</h2></div>
    <hr class="section-divider">
    <details class="panel" open>
      <summary>📌 {{n_assumptions}} assumptions <span class="summary-chevron">›</span></summary>
      <div class="panel-body">
        <ul class="assumptions-list">{{assumptions_items}}</ul>
      </div>
    </details>
  </main>

  <div class="modal-backdrop" id="copy-modal">…</div>

  <script>
    // Progress tracking — change events only, no pre-checked state
    const answeredQids = new Set();
    const totalQ = {{n_total}};
    function updateProgress() {
      const count = answeredQids.size;
      document.getElementById('answered-count').textContent = count;
      document.getElementById('progress-fill').style.width = `${(count / totalQ) * 100}%`;
    }
    document.querySelectorAll('.question-card input[type=radio]').forEach(radio => {
      radio.addEventListener('change', () => {
        answeredQids.add(radio.closest('.question-card').dataset.qid);
        updateProgress();
      });
    });

    // Bulk select
    document.getElementById('select-all').onclick = () =>
      document.querySelectorAll('.select-q').forEach(c => c.checked = true);
    document.getElementById('select-none').onclick = () =>
      document.querySelectorAll('.select-q').forEach(c => c.checked = false);
    document.getElementById('select-blockers').onclick = () =>
      document.querySelectorAll('.question-card').forEach(c => {
        c.querySelector('.select-q').checked = c.classList.contains('priority-red');
      });

    // Per-card copy
    document.querySelectorAll('.copy-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const card = btn.closest('.question-card');
        const sel = card.querySelector('input[type=radio]:checked');
        const override = card.querySelector('.override').value.trim();
        navigator.clipboard.writeText(
          `Q: ${card.querySelector('h4').innerText}\nA: ${sel ? sel.value : '(no selection)'}${override ? `\nOverride: ${override}` : ''}`
        ).catch(() => {});
      });
    });

    // Filter chips (AND logic)
    const filterState = { role:'all', priority:'all', pillar:'all' };
    function applyFilters() {
      document.querySelectorAll('.question-card').forEach(c => {
        const ok = (filterState.role === 'all' || c.dataset.role === filterState.role) &&
                   (filterState.priority === 'all' || c.dataset.priority === filterState.priority) &&
                   (filterState.pillar === 'all' || c.dataset.pillar === filterState.pillar);
        c.classList.toggle('hidden', !ok);
      });
    }
    function wireFilterGroup(groupName, stateKey, dataAttr) {
      const g = document.querySelector(`[data-filter-group="${groupName}"]`);
      if (!g) return;
      g.querySelectorAll('button').forEach(btn => {
        btn.addEventListener('click', () => {
          filterState[stateKey] = btn.dataset[dataAttr];
          g.querySelectorAll('button').forEach(b => b.classList.toggle('active', b === btn));
          applyFilters();
        });
      });
    }
    wireFilterGroup('role', 'role', 'filterRole');
    wireFilterGroup('priority', 'priority', 'filterPriority');
    wireFilterGroup('pillar', 'pillar', 'filterPillar');

    // Selective copy modal
    function buildCopyPreview() {
      const cards = [...document.querySelectorAll('.question-card')].filter(c =>
        c.querySelector('.select-q').checked && !c.classList.contains('hidden')
      );
      if (!cards.length) return '(no questions selected)';
      return cards.map(c => {
        const bucket = c.classList.contains('priority-red') ? 'blocker'
                     : c.classList.contains('priority-yellow') ? 'clarification' : 'nice';
        const sel = c.querySelector('input[type=radio]:checked');
        const override = c.querySelector('.override').value.trim();
        return `Q (${c.dataset.role} / ${bucket}): ${c.querySelector('h4').innerText}\n` +
               `  → A: ${sel ? sel.value : '(no selection)'}${override ? `\n  Override: ${override}` : ''}`;
      }).join('\n\n');
    }
    document.getElementById('open-copy-modal').addEventListener('click', () => {
      const selected = [...document.querySelectorAll('.select-q')].filter(c => c.checked).length;
      document.getElementById('modal-count').textContent = selected;
      document.getElementById('modal-total').textContent = totalQ;
      document.getElementById('copy-preview').textContent = buildCopyPreview();
      document.getElementById('copy-modal').classList.add('open');
    });
    document.getElementById('modal-close').addEventListener('click', () =>
      document.getElementById('copy-modal').classList.remove('open'));
    document.getElementById('copy-modal').addEventListener('click', e => {
      if (e.target === e.currentTarget) document.getElementById('copy-modal').classList.remove('open');
    });
    document.getElementById('copy-final').addEventListener('click', () => {
      navigator.clipboard.writeText(buildCopyPreview()).catch(() => {});
      document.getElementById('copy-modal').classList.remove('open');
    });

    // Scroll-spy
    const navLinks = [...document.querySelectorAll('nav.sidebar a[href^="#"]')];
    const anchorEls = navLinks.map(a => document.getElementById(a.getAttribute('href').slice(1))).filter(Boolean);
    function updateScrollSpy() {
      const y = window.scrollY + 100;
      let current = anchorEls[0];
      for (const el of anchorEls) { if (el.offsetTop <= y) current = el; }
      navLinks.forEach(a =>
        a.classList.toggle('active', a.getAttribute('href') === '#' + (current?.id ?? '')));
    }
    document.addEventListener('scroll', updateScrollSpy, { passive: true });
    updateScrollSpy();

    // Init: default checkboxes on
    document.querySelectorAll('.select-q').forEach(c => { c.checked = true; });
    updateProgress();
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
| Progress bar | Makes "0 of 14 answered" visible — accountability at a glance. Starts at 0 because Recommended is not pre-checked; reviewer must actively decide. |
| Diff block | Engineers don't want prose deltas. A real unified diff is the fastest way to convey "what changes in code". Per-block file-path header makes jumping to the right file instant. |
| Filter chips | A Backend engineer doesn't want to see 20 Design questions. One click filters. |
| Selective copy | Stakeholders rarely need the whole set. Per-question checkboxes + bucket presets = 1-click "blockers only". |
| Confidence chip | Reviewer sees at a glance which questions rest on `flow-tracer` cites vs UX heuristic vs speculation. |
| Reason-not-derivable line | Surfaces *why* the code couldn't answer this. Pushes back against questions that are lazily generated. |
| Dark surface palette | Consistent with developer tooling aesthetics (GitHub, Linear, Vercel). Reduces eye strain in low-light review sessions. High-contrast semantic colours (green/amber/red) communicate priority without colour-only dependency. |

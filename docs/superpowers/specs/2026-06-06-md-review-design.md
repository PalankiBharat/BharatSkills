# md-review — design

**Date:** 2026-06-06
**Status:** Approved (brainstorm) → ready for implementation plan
**Type:** New Claude Code plugin in the `punchhq-skills` marketplace

## Summary

`md-review` is a skill that opens a Markdown file in a beautiful local web page for
reading, ticking checkboxes, and editing inline. The user says *"review this md file"*
(or runs `/md-review [path]`); the skill starts a tiny localhost web server, opens the
page in the browser, and when the user clicks **Save**, writes the edited Markdown
straight back to the original file. No copy-paste, no extra steps.

## Goals

- Make reviewing/editing a single Markdown file fast and pleasant in the browser.
- One-click **Save** that writes back to the correct file automatically.
- Beautiful, readable GFM rendering with clickable task lists.
- Direct inline editing of any block, plus a raw full-file mode.
- Self-contained: no network calls, no package installs.

## Non-goals (v1)

- Editing more than one file per session.
- Git operations, diffs, PR creation.
- Real-time collaboration / multi-user.
- Remote or authenticated access (localhost only).
- Non-Markdown files.
- A separate version history or `.bak` file — git is the undo.
- Syntax-highlighting theme for code blocks (deferred to v2).

## User experience

### Trigger
- Model-invoked skill `md-review`. The frontmatter `description` is tuned to fire on
  natural phrases: "review this md file", "open this markdown in the browser",
  "let me edit/review this .md", etc.
- Also invocable explicitly as `/md-review [path]`.

### File targeting
Resolution order:
1. Explicit path argument, if provided.
2. The Markdown file just written or discussed in the current session.
3. Fallback: a quick picker listing `.md` files in the repo.

Exactly one file is opened per session.

### Flow
1. User: "review this md file."
2. Skill resolves the path, starts the local server, opens the browser.
3. User reads, ticks checkboxes, edits blocks, toggles raw if needed.
4. User clicks **Save** (or ⌘S) → file is written → success toast.
5. User closes; the server shuts down (explicit "done" signal or idle timeout).

## Architecture

### Server
- `scripts/serve.py` — Python 3 standard library only (`http.server` / `socketserver`),
  no third-party dependencies.
- Binds `127.0.0.1` on a random free port. Prints the URL; opens it via `open`
  (macOS) / `xdg-open` (Linux) when available.
- Launched by the skill with the resolved file path as an argument.

### Endpoints
- `GET /` → the page shell (HTML from `assets/`).
- `GET /api/doc` → `{ "path": <display path>, "markdown": <file contents>, "hash": <sha256> }`.
- `POST /api/save` with `{ "markdown": <full text>, "baseHash": <hash read at open> }`:
  - If the current on-disk hash ≠ `baseHash` → `409 Conflict` (file changed underneath);
    the client warns before offering a forced overwrite.
  - Otherwise write the file and return `{ "ok": true, "hash": <newHash> }`.
- Static assets (CSS, vendored `marked.js`) served from `assets/`.

### Rendering
- Client-side, using a **vendored `marked.js`** committed under `assets/` (no CDN).
- GFM features rendered: headings, paragraphs, lists, **task lists**, tables, code
  blocks, inline code, blockquotes, links, emphasis. Code blocks render in monospace
  with no color theme in v1.

### Block model & editing (the load-bearing decision)
- The Markdown source is the single source of truth at all times. The page never
  converts rendered HTML back to Markdown.
- On load, the document is split into **top-level blocks** (separated by Markdown block
  boundaries / blank lines). Each rendered block retains its exact Markdown source string.
- **Inline edit:** clicking a block swaps it for a small `<textarea>` holding that
  block's Markdown source; on blur, only that block is re-rendered and its source
  updated; the document is marked dirty.
- **Checkbox toggle:** clicking a task checkbox flips `- [ ]` ↔ `- [x]` on that exact
  source line within its block; re-render; mark dirty.
- **Raw mode:** the Rendered ⇆ Raw toggle swaps the whole document for one full-file
  `<textarea>` of the complete Markdown; edits there are authoritative; switching back
  re-renders.
- **Save** serializes blocks back into one Markdown string (joined in order, preserving
  the original block separators) and POSTs it.

### The page (UI)
- Sticky top bar: file name + path, dirty indicator (●), Rendered ⇆ Raw toggle, **Save**
  button (⌘S shortcut).
- Body: rendered Markdown, dark theme, comfortable reading column (~780px), clean
  typography.
- Toasts for Save success / conflict. An "unsaved changes" guard on page close when dirty.

## Safety, lifecycle, security
- Writes only the single opened file, to its original path.
- Conflict guard via SHA-256 compare on save.
- Server lifecycle: bound to `127.0.0.1` only; random port; auto-shutdown on an explicit
  "done" signal and after 30 minutes idle. No external network calls anywhere.
- No authentication (localhost trust model, consistent with local dev tooling).

## Repo packaging

New plugin under `plugins/md-review/`:

```
plugins/md-review/
  .claude-plugin/plugin.json        # name, description, version
  skills/md-review/
    SKILL.md                        # trigger description + how to launch serve.py
    scripts/serve.py                # the local server
    assets/
      index.html                    # page shell
      app.js                        # block model, editing, save (client)
      style.css                     # the theme
      marked.min.js                 # vendored renderer
```

Wiring required (the four-place version rule from CLAUDE.md):
1. `plugins/md-review/.claude-plugin/plugin.json` → `version`.
2. `.claude-plugin/marketplace.json` → new `plugins[]` entry (`source: "./plugins/md-review"`) with `version`.
3. `.claude-plugin/marketplace.json` → top-level `metadata.version` bump.
4. `README.md` → new row in the "Available Plugins" table.

Validate with `claude plugin validate .`. Ship as a PR off a feature branch — never push to master.

## Success criteria
- Saying "review this md file" opens the current `.md` in the browser within a couple seconds.
- Checkboxes toggle and persist on Save; the on-disk diff is exactly the flipped
  `[ ]`/`[x]` characters — untouched lines stay byte-identical.
- Inline edits to a block persist on Save and leave other blocks byte-identical.
- Save writes the original file with no paste-back; a success toast confirms.
- Editing a file that changed on disk warns before overwrite.
- `claude plugin validate .` passes.

## Future (v2, not now)
- Code syntax-highlighting theme.
- Multiple files / file tree.
- Inline review comments (the reviewed-but-deferred "review layer" option).
- Light-theme toggle.

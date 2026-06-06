---
name: md-review
description: Use when the user wants to read, review, or edit a Markdown (.md) file in a browser instead of the terminal — "review this md file", "open this markdown in the browser", "let me edit this .md", "tick/check the boxes in this doc", "open the spec/plan/README so I can review it", "show/preview/render this markdown nicely", or /md-review [path]; also right after you write or update a .md and the user wants to look it over. For Markdown files only; not for code review, PRs, diffs, or non-.md files.
---

# md-review

Open a Markdown file in a local browser page where the user reads it, ticks checkboxes, and edits inline, then clicks **Save** to write straight back to the same file. One file per session; localhost only.

## When to use
- The user asks to review / open / edit a specific `.md` in the browser.
- After you write or update a Markdown file and the user wants to look it over and tweak it.

**Do not use for:** non-Markdown files, code review, PR review, or diffs.

## How to run

1. **Resolve the file** (first match wins):
   - an explicit path the user gave;
   - else the `.md` you just wrote or discussed this session;
   - else list candidates with `git ls-files '*.md'` and ask which one.
2. **Launch the server in the background.** It auto-opens the browser, prints one JSON line `{"url": "..."}` to stdout, then keeps serving:

   ```bash
   python3 "${CLAUDE_PLUGIN_ROOT}/skills/md-review/scripts/serve.py" "<resolved .md path>"
   ```

   Run it with the Bash tool's `run_in_background: true` (the server is long-lived). Then read that background command's output — its first line is the `{"url": "..."}` — to get the URL to share.
3. **Hand off:** the page opens automatically; give the user the URL to click in case it didn't. They review, edit, and click **Save** — saving writes the file directly; nothing to paste back.

## Notes
- The server binds `127.0.0.1` on a random port and shuts down after 30 min idle (or `POST /api/done`).
- Save warns the user if the file changed on disk since it opened (SHA-256 guard).
- Requires `python3` (standard library only) and a desktop browser.

## Quick reference

| Action | What happens |
|---|---|
| Click a checkbox | Flips `- [ ]`/`- [x]` on that source line |
| Click a block | Inline editor for that block's Markdown; blur re-renders |
| Rendered ⇆ Raw | Toggle whole-file raw Markdown editing |
| Save / ⌘S | Writes the file; toast confirms; warns on disk conflict |

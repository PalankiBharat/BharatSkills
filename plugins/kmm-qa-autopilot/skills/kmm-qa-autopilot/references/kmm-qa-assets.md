# Reusable parity assets — `.kmm-qa/` in the repo (persist + reuse)

Everything a parity run discovers live — the login path, the custom keypad digit map, the
sheet-dismissal sequence, the per-journey nav recipes, the generated flows — is expensive to
rediscover and was, until now, stranded in the ephemeral `$RUN_DIR` (`~/.kmm-parity/pr-<n>/`) on one
machine. **Persist it to a committed, pushed `.kmm-qa/` directory at the repo root** so a rerun (e.g.
after the dev fixes the bug) skips discovery and goes straight to the failing checkpoint, and so every
contributor/machine reuses it. The migration doesn't touch the UI, so these assets are repo-stable.

## Layout (the as-built template — generate this same structure)

```
.kmm-qa/
  README.md                              # what it is + reuse rules + conventions
  manifest.json                          # captured_for_pr, captured_at_head, ui_source_tree
                                         #   (git-tree hash of app/src/main), skill_version,
                                         #   validate_reuse rule
  selectors.json                         # keypad digit→letter map (7=PQRS,8=TUV,9=WXYZ,…),
                                         #   OTP-entry method per screen (OTP#1=system kbd,
                                         #   PIN/TFA=letter-keypad), sheet-dismissal recipe
                                         #   (review + ^Close$), per-journey nav recipes,
                                         #   known testTags, biometric enroll/reach/auth recipe
  login/01_phone_entry.yaml              # launch→CONTINUE→inputText ${PHONE}→SEND OTP
  login/02_post_login_to_dashboard.yaml  # optional taps: Risk-Disclosure CONTINUE →
                                         #   "REVIEW AND HELP US GROW" → "^Close$" → wait chart_header
  flows/<journey>/NN_<step>.yaml         # generated per-journey checkpoint flows (no _tmp_ probes)
```

## The five hard rules (all enforced; codify them)

1. **No personal data in committed files.** Phone number → `${PHONE}` Maestro env var
   (`maestro -e PHONE=… test …`); PIN/OTP are entered interactively and **never written** to a file.
   Before committing, `grep`-scan `.kmm-qa/` for the run's phone/PIN/OTP digits — a **hard pre-commit
   gate**; abort the commit on any hit.
2. **Reuse validated by git-tree hash, not mtime.** `manifest.ui_source_tree = git rev-parse HEAD:app/src/main`.
   On rerun: tree hash matches current → **reuse `.kmm-qa/` wholesale**; else rediscover only the
   deltas and refresh the changed files + the manifest. (UI is untouched by a migration, so it usually
   matches even across PRs.)
3. **Gitignore check before commit.** `.kmm/` is gitignored in this repo; `.kmm-qa/` must NOT be.
   Run `git check-ignore .kmm-qa` first — if it's ignored, add a `!/.kmm-qa/` negation rather than
   silently no-op'ing the push.
4. **Promote only finalized flows.** `$RUN_DIR/flows/` holds throwaway `_tmp_*.yaml` probes during
   discovery; copy only the clean per-journey flows into `.kmm-qa/flows/`. `$RUN_DIR` stays the
   ephemeral working copy, **seeded from `.kmm-qa/`** at the start of a run.
5. **Commit hygiene.** Explicit `git add .kmm-qa` (never `git commit -am`), a conventional message
   (`chore(kmm-qa): persist reusable parity flows`) with the Co-Authored-By trailer, pushed to the PR
   branch so the assets land in the PR diff for the reviewer.

## Run lifecycle

- **Phase 0 (start):** if `.kmm-qa/manifest.json` exists and its `ui_source_tree` matches the current
  tree, seed `$RUN_DIR` from `.kmm-qa/` and skip rediscovery of login/selectors/flows. Otherwise start
  fresh and plan to rediscover only what changed.
- **Phase 6/7 (end):** promote finalized flows + refreshed selectors/manifest into `.kmm-qa/`, run the
  no-PII scan + `git check-ignore` gate, then `git add .kmm-qa` → conventional commit → push to the PR
  branch.

## manifest.json shape

```json
{
  "captured_for_pr": 420,
  "captured_at_head": "<pr-head-sha>",
  "ui_source_tree": "<git rev-parse HEAD:app/src/main>",
  "skill_version": "0.3.0",
  "validate_reuse": "reuse wholesale iff `git rev-parse HEAD:app/src/main` == ui_source_tree; else refresh deltas"
}
```

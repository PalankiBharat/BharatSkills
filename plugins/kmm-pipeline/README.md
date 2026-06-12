# kmm-pipeline

End-to-end, resumable KMM feature migration for **sniper-v2-android**: Android feature → `:shared` commonMain → Punch (iOS) wiring → parity QA → KMM-specific review → merged PR. Built from this repo's actual migration history (a 169-commit login migration vs a 10-commit clean move) to make the 10-commit shape the default.

## Why it looks like this

- **Platform knowledge is fetched, project knowledge is owned.** KMP/SKIE/CMP facts go stale, so a `kmm-researcher` agent fetches them live (context7 → official docs → web) with citations mandatory and `UNKNOWN` allowed. Project-specific KMM knowledge lives IN this plugin — `knowledge/repo-profile.md` (modules, SDKs, conventions, gotchas) and `knowledge/learnings.md` (incident ledger, PR-history taxonomy) — and updates at each phase boundary that surfaces a durable fact: harvest → commit to the plugin repo → `claude plugin update`. The next migration always starts with everything the last one learned, with no sniper-PR merge in the way; team sharing rides a plugin-repo PR at ship.
- **Discipline is enforced, not requested.** A PreToolUse guard (`scripts/migration_guard.py`, armed only while `.kmm/migrations/ACTIVE` exists) hard-blocks: copy-instead-of-`git mv`, android/ios/apple/darwin names, comment additions, `.broken` test silencing, untracked `@Ignore`, swallowed `CancellationException`, raw `viewModelScope.launch` in commonMain (K/N-fatal class), `Clock.System.now()` in commonMain, log-line deletion, ObjectBox schema edits, pre-release versions, raw dependency coordinates, `--rerun-tasks`, and `rm -r` on migration state. 32-case test suite: `tests/test-guard.sh`.
- **State on disk, resume anywhere.** `.kmm/migrations/<slug>/` (git-excluded) holds the cursor, journal, contract, plan, research, and reports. A SessionStart banner surfaces in-flight migrations; `/kmm-pipeline:migrate resume` reconciles journal vs git and continues.
- **Humans gate only what changes behavior**: contract (G1), plan (G2), blockers (G3), ship (G4). Everything else is autonomous.

## Skills

| Skill | Use |
|---|---|
| `/kmm-pipeline:migrate <feature>` | full pipeline, or `resume` to continue an in-flight migration |
| `/kmm-pipeline:qa [slug]` | the 9-lane parity QA matrix, standalone on any migration branch |
| `/kmm-pipeline:review [pr\|branch]` | two-lens adversarial KMM-migration review |

Agents (the team): `kmm-scout`, `kmm-researcher`, `kmm-migrator`, `kmm-ios-engineer`, `kmm-qa-verifier`, `kmm-reviewer`.

It composes rather than rebuilds: superpowers (writing-plans, TDD, systematic-debugging, receiving-code-review, worktrees, finishing-a-branch), graphify (scoping + post-change update), context7/web (live docs), Maestro (one flow, both platforms — `accessibilityIdentifier` mirrors `testTag`).

## Install

```bash
claude plugin install kmm-pipeline@punchhq-skills
```

Requires: `gh`, Xcode + CocoaPods, Maestro, graphify, python3 — probed at phase 0, not assumed.

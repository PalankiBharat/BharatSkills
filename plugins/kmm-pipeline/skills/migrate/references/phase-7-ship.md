# Phase 7 — Ship

Goal: merged PR, durable learnings recorded, state archived. QA + review verdicts are PASS before this phase starts.

1. **Integrate base.** `git merge origin/<base>` in the worktree (squash-merge repo — merge, never rebase published work). Conflicts touching moved files: resolve, then RE-RUN qa lanes 1-4 and 9 plus the baseline-executed assert — merge resolutions have silently uncompiled baselines and dropped imports here before. A merge that "compiles" but skips the baseline-count check is unverified.
2. **Knowledge home.** Append durable, reusable learnings from this migration (new traps, seam decisions, SDK facts with verification dates) to `.kmm/project.md` as an in-branch commit — the profile is team knowledge and travels with the PR. Write `retro.md` in the state dir (friction log: false starts, gate misses, prompt gaps) — input for improving this plugin, not committed.
3. **Final hygiene sweep.** `git diff <base>...HEAD --name-only`: every file ∈ plan inventory ∪ contract deliverables ∪ profile update. Anything else gets removed or explained at G4. Run `graphify update .` (repo rule after code changes).
4. **PR assembly.** Commit flow follows `docs/claude/COMMIT.md` (the repo's user-says-commit conventions: release notes, heat map, message format). PR body: contract summary with per-behavior verification status, QA lane table, review verdict, evidence links, explicit waivers. Post `review-report.md` as a PR comment — this repo's review record lives with the PR, and external reviewers should see what was already checked.
5. **G4 — ship approval.** Present: PR-ready summary, residual risks, waivers. AskUserQuestion options: open PR + merge when checks green / open PR and stop (user merges) / hold. Record the choice.
6. **Open + monitor.** Push, `gh pr create` (base from state.json). Watch checks (`gh pr checks`); CI failures route to kmm-migrator dispatches (≤2 rounds, then G3). Human review comments arriving on the PR: handle via superpowers:receiving-code-review — verify before implementing, push back with evidence when wrong.
7. **Close-out** (after merge, or after "open and stop"): superpowers:finishing-a-development-branch for worktree/branch cleanup; archive state dir to `.kmm/migrations/_archive/<slug>-<date>/`; remove BOTH `ACTIVE` markers (this disarms the guard); journal `phase-done`. Tell the user what merged, what was waived, and where the retro lives.

Exit: PR merged or explicitly handed off; profile updated; state archived; guard disarmed.

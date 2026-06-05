# PunchHQ Claude Code Skills Marketplace

A plugin marketplace for Claude Code, distributing skills for development workflows.

## Available Plugins

| Plugin | Version | Description |
|---|---|---|
| `feature-analyzer` | 2.2.1 | Pre-dev story interrogation — team-lead orchestrator walks code + Figma flows, honours project memory, strips out-of-platform sections, emits a centred dark-mode HTML doc with the original story pinned alongside option-pill questions across PM / Backend / Android / Design / QA / Compliance / DevOps roles |
| `qa-autopilot` | 1.3.2 | Android UI QA in three modes — branch QA (git diff → journey-risk → generate/run Maestro flows → report), single-flow Maestro authoring, and Figma visual parity (fetch design → screenshot the live screen → pixel-diff colour / thickness / spacing). Maestro discipline (accessibility-ID selectors, screen-tag enforcement) and the ADB fingerprint bridge are built in |
| `dev-harness` | 0.1.11 | `/harness "<story>"` drives a visible 6-pane tmux team (a driving Orchestrator pane + Tech Lead + Senior/Junior Dev + QA Lead/Tester + Review Architect) from a story to a tested, reviewed PR. Persona agents (opus leads dispatch sonnet workers), adaptive flow (feature / small-change / bug-fix), phased delivery, file-mailbox coordination, live streaming panes, two-lane feedback, restart, crash-safe resume, PreToolUse security guard, opt-in OS sandbox (`--sandbox`), and multi-run worktrees (`--worktree`). |
| `skill-feedback` | 1.2.0 | End-of-session skill auditor — reviews skills used and raises GitHub Issues with improvement feedback |
| `clean-code` | 1.2.7 | Clean Code principles (Uncle Bob) with auto-loading prehook — naming, functions, classes, error handling, testing |
| `skill-tester` | 1.0.0 | Automated QA loop for skills — 3-pane tmux workflow to test, validate, and fix skills until production-ready |
| `bug-finder` | 1.0.0 | Evidence-based bug/crash root cause diagnosis — flow mapping, hypothesis formation, log verification, root cause report |
| `om-pipeline` | 1.0.0 | Supreme 8-stage dev pipeline — plan, side-effect analysis, execute, harsh review, regression check, device testing, bug fix loops |
| `branch-manager` | 1.0.0 | Branch dev environment lifecycle — git worktrees, dedicated tmux panes with Claude Code, isolated Android emulators per branch, interactive cleanup with safety checks |
| `legacy-refactor` | 1.0.0 | Safe legacy code refactoring (Michael Feathers' "Working Effectively with Legacy Code") — seams, characterization tests, dependency breaking, sprout/wrap, Kotlin/Android patterns |
| `release` | 1.0.0 | Release builds with correct release notes — `/release` slash command for Play Store builds |
| `instructions-feedback` | 1.0.0 | End-of-session auditor that reviews the conversation for instruction corrections and 'always/never' directives, then drafts user-approved GitHub Issues proposing amendments to CLAUDE.md, path-scoped rules, or the project constitution |
| `review-pr` | 1.3.0 | Multi-agent PR review — 25 focused agents in parallel per file type, inline GitHub comments, calibration (human-in-loop) and autopilot (`--auto`) modes |
| `preview-compose` | 0.1.0 | Renders Jetpack Compose `@Preview` composables on a connected Android emulator from the terminal — installs the debug APK and launches a bundled PreviewActivity with the target preview's FQN |
| `kmm-migration-workflow` | 1.12.0 | Android-to-KMM migration orchestrator with strict behavioral-equivalence safety. Phased workflow — discovery, diagnostic, frozen baseline tests, `git mv` + surgical migration, Android+iOS validation, PR, code-review intake, then parity-QA hand-off. Live-sourced API knowledge (web + Context7), per-repo conventions in `.kmm/project.md`, diff-confirm gates, commit autopilot, blocking per-phase retro |
| `sniper-ops` | 1.3.0 | Ops shortcuts for the sniper-v2-android repo — `share-prod` / `share-staging` (commit + push + release-notes pre-flight then trigger CircleCI build), `install-prod` / `install-staging` (local install to a connected device, then auto-launch the app and tail a crash-only logcat `*:E` scoped to the app's PID in the background), `heap-dump-pair` (option-driven interview to capture a baseline + t+5min `.hprof` pair so you can diff retained objects in Android Studio Profiler), and `heap-dump-compare` (diff two Android `.hprof` files and present a side-by-side comparison table — data only, no diagnosis) |
| `kmm-qa-autopilot` | 0.4.0 | Parity QA for Android-to-KMM migration PRs — proves a migration is behavior-preserving by running the baseline `master` and the PR head head-to-head. From a PR link: builds two ProductionRelease APKs (the shipped R8-minified artifact, same package; auto-baselines a merged PR to pre-migration master), boots + locks two visible emulators (master→A, PR→B), one manual prod login each, a no-exclusions heatmap from the master-vs-PR diff, the SAME Maestro flows on both devices, and a view-hierarchy structure + stable-value diff (live prices/charts auto-masked by double-sampling) → per-journey parity verdict. Evidence-backed verdict (exception docs are context only); ends with a session retro. Real-prod-state safety gate holds order/funds/kill-switch flows behind explicit confirmation |
| `retro-triage` | 0.2.0 | Folds a skill's session retro (`retro.md` / improvement backlog) into reviewed, version-bumped skill edits and a PR. Treats the retro as candidates, not decisions — reads the whole target skill first, distills distinct candidates, gets approval one-by-one (each with a recommended option + reasoning via AskUserQuestion), reconciles candidates against the skill's own refuted/learned notes, then implements surgically in a worktree (surgical edit vs rewrite vs new file — no bloat) and ships a PR |

## Installation

### 1. Add the marketplace

```shell
/plugin marketplace add PunchHQ/claude-code-skills
```

### 2. Install plugins

```shell
/plugin install feature-analyzer@punchhq-skills
/plugin install qa-autopilot@punchhq-skills
/plugin install skill-feedback@punchhq-skills
/plugin install clean-code@punchhq-skills
/plugin install skill-tester@punchhq-skills
/plugin install bug-finder@punchhq-skills
/plugin install om-pipeline@punchhq-skills
/plugin install branch-manager@punchhq-skills
/plugin install legacy-refactor@punchhq-skills
/plugin install release@punchhq-skills
/plugin install instructions-feedback@punchhq-skills
/plugin install review-pr@punchhq-skills
/plugin install preview-compose@punchhq-skills
/plugin install kmm-migration-workflow@punchhq-skills
/plugin install sniper-ops@punchhq-skills
/plugin install kmm-qa-autopilot@punchhq-skills
/plugin install retro-triage@punchhq-skills
/plugin install dev-harness@punchhq-skills
```

### 3. Use the skills

```shell
# Feature analysis
analyze this feature: Add dark mode support to settings

# QA autopilot
test my changes

# Skill feedback (end of session)
skill feedback

# Clean code (auto-loads via hook on every prompt, or invoke manually)
/clean-code:clean-code

# Om pipeline (full dev pipeline: plan → build → review → test on device)
/om add dark mode toggle in settings screen

# KMM migration (auto-invoked skill; just describe the migration)
migrate the funds screen to KMM

# PR review (calibration = human-in-loop, --auto = fully autonomous)
/review-pr:review-pr 123
/review-pr:review-pr 123 --auto

# KMM PR review (auto-fires on KMP repos; or invoke explicitly)
review this KMP PR: https://github.com/<org>/<repo>/pull/123

# KMM debugger (post-migration regression debugging; closes with a self-improving retro)
QA filed 3 issues on our KMM alpha — Scan-QR is a no-op, post-OTP crash on upgrade, brokerage promo keeps reappearing. How should we investigate?
```

## For Teams

Add this to your project's `.claude/settings.json` to auto-prompt teammates to install the marketplace:

```json
{
  "extraKnownMarketplaces": {
    "punchhq-skills": {
      "source": {
        "source": "github",
        "repo": "PunchHQ/claude-code-skills"
      }
    }
  }
}
```

To pre-enable specific plugins:

```json
{
  "enabledPlugins": {
    "feature-analyzer@punchhq-skills": true,
    "qa-autopilot@punchhq-skills": true,
    "skill-feedback@punchhq-skills": true,
    "clean-code@punchhq-skills": true,
  }
}
```

## Updating

Users get updates automatically at startup, or manually:

```shell
/plugin marketplace update
```

## Repository Structure

```
claude-code-skills/
├── .claude-plugin/
│   └── marketplace.json              # Marketplace catalog
├── plugins/
│   ├── feature-analyzer/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/
│   │       └── feature-analyzer/
│   │           ├── SKILL.md
│   │           └── references/
│   ├── qa-autopilot/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/
│   │       └── qa-autopilot/
│   │           ├── SKILL.md
│   │           ├── references/
│   │           └── scripts/
│   ├── skill-feedback-plugin/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   ├── hooks/
│   │   │   └── hooks.json            # PostToolUse hook for tracking
│   │   ├── scripts/
│   │   └── skills/
│   │       └── skill-feedback/
│   │           ├── SKILL.md
│   │           └── references/
│   ├── clean-code-plugin/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   ├── hooks/
│   │   │   └── hooks.json            # UserPromptSubmit prehook
│   │   ├── scripts/
│   │   │   └── load-clean-code.sh    # Injects SKILL.md + rules card
│   │   └── skills/
│   │       └── clean-code/
│   │           ├── SKILL.md
│   │           └── references/
│   ├── skill-tester-plugin/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/
│   │       └── skill-tester/
│   │           ├── SKILL.md
│   │           └── references/
│   ├── bug-finder/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/
│   │       └── bug-finder/
│   │           ├── SKILL.md
│   │           └── references/
│   ├── om-pipeline/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── commands/
│   │       ├── om.md                  # Master orchestrator
│   │       ├── om-bramha.md           # Creation: plan, side effects, execute, review, regression
│   │       └── om-vishnu.md           # Preservation: test cases, device testing, bug assessment
│   ├── branch-manager/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/
│   │       ├── setup-branch/
│   │       │   └── SKILL.md
│   │       └── cleanup-branch/
│   │           └── SKILL.md
│   ├── legacy-refactor/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/
│   │       └── legacy-refactor/
│   │           ├── SKILL.md
│   │           └── references/
│   ├── release/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   ├── commands/
│   │   │   └── release.md
│   │   └── skills/
│   │       └── release/
│   │           └── SKILL.md
│   ├── instructions-feedback/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/
│   │       └── instructions-feedback/
│   │           ├── SKILL.md
│   │           └── references/
│   ├── preview-compose/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   ├── scripts/
│   │   ├── skills/
│   │   │   └── preview-compose/
│   │   │       └── SKILL.md
│   │   └── templates/                # Bundled PreviewActivity sources
│   ├── review-pr/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/
│   │       └── review-pr/
│   │           ├── SKILL.md
│   │           └── patterns/         # Per-file-type review rules
│   ├── kmm-migration-workflow/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/
│   │       └── kmm-migration/
│   │           ├── SKILL.md
│   │           └── references/
│   │               ├── test-discipline.md
│   │               └── phases/        # phase-0-discovery through phase-g-pr
└── README.md
```

## Adding a New Plugin

1. Create a directory under `plugins/<plugin-name>/`
2. Add `.claude-plugin/plugin.json` with name, description, version
3. Add skills under `skills/<skill-name>/SKILL.md`
4. Optionally add `hooks/hooks.json` for pre/post hooks
5. Add the plugin entry to `.claude-plugin/marketplace.json`
6. Validate: `/plugin validate .`
7. Bump version in both `plugin.json` and `marketplace.json` for updates

## Validation

```shell
claude plugin validate .
```

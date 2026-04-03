# PunchHQ Claude Code Skills Marketplace

A plugin marketplace for Claude Code, distributing skills for development workflows.

## Available Plugins

| Plugin | Version | Description |
|---|---|---|
| `feature-analyzer` | 1.0.0 | Two-phase user story and feature analysis for Android development |
| `qa-autopilot` | 1.0.0 | Automated QA — analyzes git changes, generates test cases, executes on Android devices |
| `skill-feedback` | 1.0.0 | End-of-session skill auditor — reviews skills used and raises GitHub Issues with improvement feedback |
| `clean-code` | 1.2.7 | Clean Code principles (Uncle Bob) with auto-loading prehook — naming, functions, classes, error handling, testing |
| `skill-tester` | 1.0.0 | Automated QA loop for skills — 3-pane tmux workflow to test, validate, and fix skills until production-ready |
| `bug-finder` | 1.0.0 | Evidence-based bug/crash root cause diagnosis — flow mapping, hypothesis formation, log verification, root cause report |
| `om-pipeline` | 1.0.0 | Supreme 8-stage dev pipeline — plan, side-effect analysis, execute, harsh review, regression check, device testing, bug fix loops |
| `kmm-plugin` | 6.0.0 | Battle-tested KMM migration orchestrator — 5-phase workflow with TDD, parallel agent teams, static parity analysis, verify-first Appium, enriched migration guide, integrated self-improvement |

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
/plugin install bug-finder@punchhq-skills
/plugin install om-pipeline@punchhq-skills
/plugin install kmm-plugin@punchhq-skills
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

# KMM migration (create, continue, or self-improve)
/kmm-plugin:kmm-workflow create my-feature-module
/kmm-plugin:kmm-workflow continue
/kmm-plugin:kmm-workflow improve
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
    "kmm-plugin@punchhq-skills": true,
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
│   ├── kmm-plugin/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json
│   │   └── skills/
│   │       ├── kmm/
│   │       │   ├── SKILL.md
│   │       │   └── references/        # 7 reference files (patterns, gotchas, dep map, etc.)
│   │       └── kmm-workflow/
│   │           ├── SKILL.md
│   │           └── references/        # batched-execution, feedback-capture
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

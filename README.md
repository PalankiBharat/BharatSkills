# PunchHQ Claude Code Skills Marketplace

A plugin marketplace for Claude Code, distributing skills for Android development workflows.

## Available Plugins

| Plugin | Description |
|---|---|
| `feature-analyzer` | Two-phase user story and feature analysis for Android development |
| `qa-autopilot` | Automated QA — analyzes git changes, generates test cases, executes on Android devices |

## Installation

### 1. Add the marketplace

```shell
/plugin marketplace add PunchHQ/claude-code-skills
```

### 2. Install a plugin

```shell
# Install a specific plugin
/plugin install feature-analyzer@punchhq-skills
/plugin install qa-autopilot@punchhq-skills
```

### 3. Use the skills

```shell
# Feature analysis
analyze this feature: Add dark mode support to settings

# QA autopilot
test my changes
```

## For teams

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

To also pre-enable specific plugins:

```json
{
  "enabledPlugins": {
    "feature-analyzer@punchhq-skills": true,
    "qa-autopilot@punchhq-skills": true
  }
}
```

## Updating

Users get updates automatically, or manually:

```shell
/plugin marketplace update
```

## Repository Structure

```
claude-code-skills/
├── .claude-plugin/
│   └── marketplace.json          # Marketplace catalog
├── plugins/
│   ├── feature-analyzer/
│   │   ├── .claude-plugin/
│   │   │   └── plugin.json       # Plugin manifest
│   │   └── skills/
│   │       └── feature-analyzer/
│   │           ├── SKILL.md
│   │           └── references/
│   └── qa-autopilot/
│       ├── .claude-plugin/
│       │   └── plugin.json
│       └── skills/
│           └── qa-autopilot/
│               ├── SKILL.md
│               ├── references/
│               └── scripts/
└── README.md
```

## Adding a new plugin

1. Create a directory under `plugins/<plugin-name>/`
2. Add `.claude-plugin/plugin.json` with name, description, version
3. Add skills under `skills/<skill-name>/SKILL.md`
4. Add the plugin entry to `.claude-plugin/marketplace.json`
5. Validate: `/plugin validate .`

## Validation

```shell
# From the repo root
claude plugin validate .
```

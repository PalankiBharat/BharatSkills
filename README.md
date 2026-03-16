# How to install Claude Code skills

## What are skills?

Skills are markdown-based instruction sets that teach Claude Code how to handle specific workflows. When you trigger a skill (by asking Claude something that matches the skill's description), Claude reads the skill's `SKILL.md` and follows its instructions — using reference files, scripts, and templates bundled with it.

Each skill is a folder:

```
skill-name/
├── SKILL.md              # Main instructions (required)
├── README.md             # Documentation (optional)
└── references/           # Supporting knowledge files (optional)
    ├── some-topic.md
    └── another-topic.md
```

## Installation methods

### Method 1: Copy the skill folder (recommended)

Copy the skill directory into your Claude Code skills location.

**User-level** (available in all projects):

```bash
# Create skills directory if it doesn't exist
mkdir -p ~/.claude/skills

# Copy a skill
cp -r feature-analyzer ~/.claude/skills/
```

**Project-level** (available only in this project):

```bash
# Create skills directory at project root
mkdir -p .claude/skills

# Copy a skill
cp -r feature-analyzer .claude/skills/
```

Claude Code automatically detects skills in both locations.

### Method 2: Install from a `.skill` file

If the skill is packaged as a `.skill` file (a zip archive), extract it to your skills directory:

```bash
# User-level
unzip feature-analyzer.skill -d ~/.claude/skills/

# Project-level
unzip feature-analyzer.skill -d .claude/skills/
```

### Method 3: Clone this repo and symlink

If you want to keep skills updated via git:

```bash
# Clone the repo
git clone <this-repo-url> ~/my-skills

# Symlink individual skills
ln -s ~/my-skills/feature-analyzer ~/.claude/skills/feature-analyzer

# Or symlink the entire collection
ln -s ~/my-skills ~/.claude/skills
```

## Verify installation

Start a Claude Code session and ask something that should trigger the skill. For example, with the `feature-analyzer` skill installed:

```
analyze this feature: Add dark mode support to the settings screen
```

Claude should read the skill's `SKILL.md` and follow its two-phase workflow.

You can also check directly:

```bash
# List installed user-level skills
ls ~/.claude/skills/

# List installed project-level skills
ls .claude/skills/
```

## User-level vs project-level

| | User-level (`~/.claude/skills/`) | Project-level (`.claude/skills/`) |
|---|---|---|
| Scope | All projects | Current project only |
| Git tracked | No | Yes (commit with your project) |
| Best for | Personal workflow skills | Team/project-specific skills |

You can have both. Project-level skills take precedence if there's a name conflict.

## Updating a skill

Since skills are just markdown files, updating is straightforward:

```bash
# If installed via copy
cp -r feature-analyzer ~/.claude/skills/

# If installed via symlink
cd ~/my-skills && git pull
```

Changes take effect on the next Claude Code session — no restart needed.

## Uninstalling a skill

Delete the skill folder:

```bash
rm -rf ~/.claude/skills/feature-analyzer
```

## Troubleshooting

**Skill not triggering?**

The skill's `description` field in `SKILL.md` frontmatter controls when Claude decides to use it. If your phrasing doesn't match, Claude may not activate the skill. Try using phrases listed in the skill's description, or ask Claude directly: "use the feature-analyzer skill on this."

**Skill partially loading?**

Large reference files may not all fit in Claude's context. Well-structured skills use progressive disclosure — the main `SKILL.md` is always loaded, and reference files are read on-demand as the skill instructs.

**Conflicting skills?**

If two skills have overlapping triggers, Claude picks the one whose description best matches your request. Rename or adjust descriptions to reduce overlap.

## Creating your own skills

A minimal skill is just a `SKILL.md` with YAML frontmatter:

```markdown
---
name: my-skill
description: What this skill does and when to use it.
---

# My Skill

Instructions for Claude go here.
```

For complex skills, add reference files:

```
my-skill/
├── SKILL.md
└── references/
    ├── detailed-topic.md
    └── another-topic.md
```

In your `SKILL.md`, tell Claude when to read each reference:

```markdown
When analyzing the domain, read `references/detailed-topic.md` first.
```

Keep `SKILL.md` under 500 lines. Put detailed knowledge in reference files.

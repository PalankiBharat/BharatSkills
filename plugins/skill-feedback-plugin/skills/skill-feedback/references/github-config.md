# GitHub Configuration

## Repo structure

The skill-feedback skill files issues against a single GitHub repo that serves as your skill marketplace / ecosystem hub. The repo structure is expected to be:

```
skill-marketplace/
├── skills/
│   ├── feature-analyzer/
│   │   ├── SKILL.md
│   │   └── references/
│   ├── qa-autopilot/
│   ├── clean-code/
│   └── ...
├── .github/
│   └── ISSUE_TEMPLATE/
│       └── skill-feedback.md    ← (optional) GitHub issue template
└── README.md
```

The repo doesn't need to exist with this exact structure — the skill only needs Issues to be enabled on the repo.

## Configuration file

The skill reads its target repo from `~/.skill-feedback-config.json`:

```json
{
  "repo": "owner/skill-marketplace"
}
```

If this file doesn't exist when the skill runs, it will ask the developer for the repo name and create it.

## Label taxonomy

The skill uses a structured label system to make issues filterable and queryable. All labels are created automatically by `scripts/ensure-labels.sh`.

### Skill labels (one per issue)
| Label | Color | Description |
|-------|-------|-------------|
| `skill:<n>` | `#0075ca` | Created dynamically per skill |

### Priority labels (one per issue)
| Label | Color | Description |
|-------|-------|-------------|
| `priority:P0` | `#d73a4a` | Fix immediately — blocks workflow |
| `priority:P1` | `#e4e669` | Fix this week — recurring or notable |
| `priority:P2` | `#0e8a16` | Backlog — nice to have |

### Type labels (one or more per issue)
| Label | Color | Description |
|-------|-------|-------------|
| `type:friction` | `#f9d0c4` | Developer had to intervene or re-run |
| `type:output-quality` | `#d4c5f9` | Output was wrong or incomplete |
| `type:missing-capability` | `#bfdadc` | Skill lacks a needed feature |
| `type:trigger-failure` | `#d73a4a` | Skill didn't trigger when expected |
| `type:trigger-false-positive` | `#fbca04` | Skill triggered incorrectly |

### Session labels (one per issue)
| Label | Color | Description |
|-------|-------|-------------|
| `session:YYYY-MM-DD` | `#c5def5` | Groups issues from same session |

## Authentication

The GitHub CLI must be authenticated. Verify with:

```bash
gh auth status
```

If not authenticated, run `gh auth login`. The skill checks this in Phase 0 and stops with clear instructions if auth is missing.

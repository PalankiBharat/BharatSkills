# Clean Code Plugin - Marketplace Deployment Guide

This guide shows you how to add the Clean Code plugin to your Claude Code marketplace.

## Quick Overview

The Clean Code plugin follows the standard Claude Code plugin structure:

```
clean-code-plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
├── skills/
│   └── clean-code/
│       ├── SKILL.md         # Main skill guide
│       └── references/      # 7 detailed references
│           ├── naming.md
│           ├── functions.md
│           ├── classes.md
│           ├── comments.md
│           ├── formatting.md
│           ├── error-handling.md
│           └── testing.md
├── README.md                # Plugin documentation
├── marketplace-entry.json   # Entry for your marketplace.json
└── example-marketplace.json # Complete marketplace example
```

## Deployment Options

### Option 1: GitHub Repository (Recommended)

**Step 1: Create a Repository**

```bash
# Create a new repository on GitHub
# Example: your-org/clean-code-plugin

# Upload the plugin files
git init
git add .
git commit -m "Add Clean Code plugin v1.0.0"
git branch -M main
git remote add origin https://github.com/your-org/clean-code-plugin.git
git push -u origin main
```

**Step 2: Add to Your Marketplace**

Add this entry to your marketplace's `.claude-plugin/marketplace.json`:

```json
{
  "name": "clean-code",
  "source": {
    "type": "github",
    "repo": "your-org/clean-code-plugin",
    "ref": "main"
  },
  "version": "1.0.0",
  "description": "Comprehensive guidelines for writing clean, maintainable code following Robert C. Martin's Clean Code principles.",
  "author": {
    "name": "Your Organization",
    "email": "support@yourorg.com"
  },
  "category": "productivity",
  "keywords": [
    "clean-code",
    "code-quality",
    "refactoring",
    "best-practices"
  ]
}
```

**Step 3: Test Installation**

```bash
# Engineers can now install it
claude plugin marketplace add github:your-org/your-marketplace
claude plugin install clean-code@your-marketplace
```

### Option 2: Same Repository as Marketplace

If your marketplace and plugins live in the same repo:

**Directory Structure:**

```
your-marketplace/
├── .claude-plugin/
│   └── marketplace.json
└── plugins/
    └── clean-code-plugin/
        ├── .claude-plugin/
        │   └── plugin.json
        └── skills/
            └── clean-code/
```

**marketplace.json entry:**

```json
{
  "name": "clean-code",
  "source": {
    "type": "path",
    "path": "./plugins/clean-code-plugin"
  },
  "version": "1.0.0",
  "description": "...",
  "category": "productivity"
}
```

### Option 3: GitLab/Bitbucket/Self-Hosted Git

For non-GitHub git repositories:

```json
{
  "name": "clean-code",
  "source": {
    "type": "git",
    "url": "https://gitlab.com/your-org/clean-code-plugin.git",
    "ref": "main"
  },
  "version": "1.0.0",
  "description": "..."
}
```

## Version Management

### Using Tags

```bash
# Tag a release
git tag -a v1.0.0 -m "Release version 1.0.0"
git push origin v1.0.0
```

Update marketplace.json:
```json
{
  "source": {
    "type": "github",
    "repo": "your-org/clean-code-plugin",
    "ref": "v1.0.0"
  }
}
```

### Using Commit SHA (for exact pinning)

```json
{
  "source": {
    "type": "github",
    "repo": "your-org/clean-code-plugin",
    "sha": "abc123def456..."
  }
}
```

## Private Repository Setup

### For GitHub Private Repos

Engineers need to authenticate:

```bash
# Using GitHub CLI
gh auth login

# Or set token environment variable
export GITHUB_TOKEN="your_personal_access_token"
```

### For GitLab/Bitbucket

```bash
# Set appropriate token
export GITLAB_TOKEN="your_gitlab_token"
export BITBUCKET_TOKEN="your_bitbucket_token"
```

## Testing Your Marketplace Entry

### 1. Validate JSON

```bash
# Check marketplace.json is valid
jq . .claude-plugin/marketplace.json
```

### 2. Test Installation Locally

```bash
# Add your marketplace
claude plugin marketplace add /path/to/your-marketplace

# Install the plugin
claude plugin install clean-code@your-marketplace

# Verify it works
claude "Write a clean function to calculate total price"
```

### 3. Check Plugin Loading

```bash
# List installed plugins
claude plugin list

# Should show:
# ✓ clean-code@your-marketplace (v1.0.0)
```

## Updating the Plugin

### Update Version

1. Make changes to the plugin files
2. Update version in `.claude-plugin/plugin.json`
3. Update version in your `marketplace.json` entry
4. Commit and push (or tag a new release)

```bash
# Update plugin
vim .claude-plugin/plugin.json  # Change version to 1.1.0
git commit -am "Update to v1.1.0"
git tag -a v1.1.0 -m "Version 1.1.0"
git push origin v1.1.0
```

### Auto-Updates

Claude Code automatically checks for updates at startup. Engineers get notified when new versions are available.

## Complete Marketplace Example

Here's a complete `marketplace.json` with multiple plugins:

```json
{
  "name": "acme-engineering",
  "owner": {
    "name": "ACME Engineering",
    "email": "dev@acme.com"
  },
  "plugins": [
    {
      "name": "clean-code",
      "source": {
        "type": "github",
        "repo": "acme/clean-code-plugin",
        "ref": "v1.0.0"
      },
      "version": "1.0.0",
      "description": "Clean Code best practices",
      "category": "productivity"
    },
    {
      "name": "acme-standards",
      "source": {
        "type": "path",
        "path": "./plugins/acme-standards"
      },
      "version": "2.1.0",
      "description": "ACME coding standards",
      "category": "internal"
    }
  ]
}
```

## Distribution

### Internal Teams

Share your marketplace URL:

```bash
# Engineers add it once
claude plugin marketplace add github:acme/engineering-marketplace

# Then install specific plugins
claude plugin install clean-code@acme
```

### Public Distribution

Host your marketplace on GitHub and share the repository:

```bash
claude plugin marketplace add github:your-org/public-marketplace
```

## Troubleshooting

### Plugin Not Found

- Verify `marketplace.json` syntax with `jq`
- Check repository URLs are correct
- Ensure `.claude-plugin/plugin.json` exists in plugin

### Authentication Issues

- For private repos, verify tokens are set
- Check token has repo access permissions

### Version Conflicts

- Use semantic versioning (1.0.0, 1.1.0, 2.0.0)
- Pin to specific tags or SHAs for stability

## Support

For Claude Code marketplace documentation:
https://code.claude.com/docs/en/plugin-marketplaces

---

**Your engineers will love having Clean Code guidance built right into their workflow! 🚀**

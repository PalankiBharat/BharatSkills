# Claude Code hooks for forcing skill invocation

Skill triggering depends on Claude reading the description and deciding to use the skill. That works most of the time but undertriggers in some real cases — especially when a Figma URL appears mid-conversation without the user explicitly saying "Compose" or "implement this." This doc explains how to set up a pre-prompt hook in **Claude Code** (the CLI) that forces this skill to be considered whenever a Figma URL appears.

**This is NOT shipped with the skill bundle.** Hooks are user-side configuration in `~/.claude/settings.json`; a skill author can't ship them. You configure this once on your machine. After that, every Claude Code session automatically reminds Claude about the skill the moment a Figma URL appears.

## What the hook does

The `UserPromptSubmit` hook runs immediately after you submit a message, before Claude reads it. The hook can append text to the message that Claude sees but you don't have to type. Pattern: detect Figma URLs in your prompt, and if one is present, append a reminder.

## Setup

Create or edit `~/.claude/settings.json`. Add a `hooks` block:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "figma\\.com",
        "hooks": [
          {
            "type": "command",
            "command": "echo '[hook] Figma URL detected. If this is a UI/Compose request, use the figma-to-compose skill — even if I did not say Compose explicitly. Run the skill from step 1 (export) and walk through the full pipeline. Re-read SKILL.md if it has been more than one tool use ago.'"
          }
        ]
      }
    ]
  }
}
```

**How it works:**
- `matcher: "figma\\.com"` is a regex tested against your prompt text.
- When the regex matches, the `command` runs and its stdout is appended to the prompt Claude receives.
- Claude sees both your original message AND the hook's text, so it can't easily skip the skill — the reminder is structurally part of the prompt.

## Stronger variants

The version above is gentle ("if this is a UI/Compose request"). If you want stricter enforcement:

```json
"command": "echo '[hook ENFORCEMENT] A Figma URL is in this prompt. The figma-to-compose skill MUST be invoked for any UI/screen/component task involving this URL. Do NOT generate Compose code without first running scripts/figma-to-json.js. If you are unsure whether the user wants Compose generation, ASK before assuming you should freelance a hand-written implementation.'"
```

## Combining with project context

If you only want the hook active in projects where you're using Compose, narrow the matcher with project-side scoping. Claude Code reads `~/.claude/settings.json` AND `.claude/settings.json` in the project root. Put the hook in the project-level file to scope it:

```
your-kmp-project/
  .claude/
    settings.json    # ← hook lives here, project-scoped
```

That way, Figma URLs in your KMP project trigger the skill, but Figma URLs in unrelated chats don't.

## Verifying it works

1. Set up the hook.
2. Start a new Claude Code session in your project.
3. Paste a message containing a Figma URL: "Hey, can you look at https://www.figma.com/design/abc/..."
4. Claude's response should reference the skill or run `figma-to-json.js`.
5. If it doesn't, check `claude --debug` output for "UserPromptSubmit" lines confirming the hook fired.

## What hooks CAN'T do

- They can't modify what skill files Claude has loaded.
- They can't run skill scripts on your behalf — the user (Claude, the agent) still has to invoke the skill's tools.
- They can't be shipped as part of a skill bundle. If you want to share this configuration with your team, share the `~/.claude/settings.json` snippet directly, not the skill.

## Why this lives in a reference doc, not in the main SKILL.md

A skill is shown to Claude every time it's referenced. Hook configuration belongs to you, the operator. Mixing the two is confusing — Claude doesn't need to know your hook settings, and you shouldn't have to read skill internals to configure your CLI. This doc exists so that when you (or someone reviewing your setup) asks "how do I make sure this skill always fires", there's an authoritative answer.

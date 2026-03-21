#!/bin/bash
# Pre-loads SKILL.md + condensed rules card into additionalContext.
# Uses a short, dense rules card (~50 lines) instead of full reference files
# to prevent the LLM from deprioritizing verbose system-reminder content.
# Full reference files remain available for explicit deep dives.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
REFS_DIR="$PLUGIN_ROOT/skills/clean-code/references"
SKILL_FILE="$PLUGIN_ROOT/skills/clean-code/SKILL.md"
RULES_CARD="$REFS_DIR/rules-card.md"

if [ ! -f "$SKILL_FILE" ]; then
  exit 0
fi

CONTENT=""
CONTENT+="$(cat "$SKILL_FILE")"

# Load condensed rules card — covers naming, functions, classes, errors in ~50 lines
if [ -f "$RULES_CARD" ]; then
  CONTENT+=$'\n\n--- RULES CARD (all principles condensed) ---\n'
  CONTENT+="$(cat "$RULES_CARD")"
fi

# Escape for JSON: backslashes, quotes, newlines, tabs
ESCAPED=$(printf '%s' "$CONTENT" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | awk '{printf "%s\\n", $0}')

cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "CLEAN CODE PREHOOK — MANDATORY: If this task involves writing, editing, or generating ANY code, you MUST apply the following principles. These are pre-loaded reference files — do NOT skip them.\n\n${ESCAPED}\n\nFor detailed examples with full context, read specific files from ${REFS_DIR}/ (naming.md, functions.md, classes.md, error-handling.md, comments.md, formatting.md, testing.md)."
  }
}
ENDJSON

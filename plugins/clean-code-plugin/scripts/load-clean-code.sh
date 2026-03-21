#!/bin/bash
# Pre-loads SKILL.md + core reference files directly into additionalContext.
# This removes the need for Claude to read references itself — the content
# is injected before Claude starts processing the prompt.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
REFS_DIR="$PLUGIN_ROOT/skills/clean-code/references"
SKILL_FILE="$PLUGIN_ROOT/skills/clean-code/SKILL.md"

if [ ! -f "$SKILL_FILE" ]; then
  exit 0
fi

# Build combined content: SKILL.md + always-needed references
CONTENT=""
CONTENT+="$(cat "$SKILL_FILE")"

# Always load naming and functions — needed for any code task
for ref in naming.md functions.md; do
  if [ -f "$REFS_DIR/$ref" ]; then
    CONTENT+=$'\n\n--- REFERENCE: '"$ref"$' ---\n'
    CONTENT+="$(cat "$REFS_DIR/$ref")"
  fi
done

# Escape for JSON: backslashes, quotes, newlines, tabs
ESCAPED=$(printf '%s' "$CONTENT" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/	/\\t/g' | awk '{printf "%s\\n", $0}')

cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "CLEAN CODE PREHOOK — MANDATORY: If this task involves writing, editing, or generating ANY code, you MUST apply the following principles. These are pre-loaded reference files — do NOT skip them.\n\n${ESCAPED}\n\nFor classes, error-handling, comments, formatting, or testing guidance, read the remaining files from ${REFS_DIR}/."
  }
}
ENDJSON

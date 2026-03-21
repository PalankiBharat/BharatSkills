#!/bin/bash
# Reads SKILL.md and returns it as additionalContext so Claude
# loads the full clean-code orchestrator before writing any code.
# The orchestrator references micro-skills (references/*.md) that
# Claude can load on demand based on what it's about to write.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(dirname "$(dirname "$0")")}"
SKILL_FILE="$PLUGIN_ROOT/skills/clean-code/SKILL.md"

if [ ! -f "$SKILL_FILE" ]; then
  exit 0
fi

SKILL_CONTENT=$(cat "$SKILL_FILE")

cat <<ENDJSON
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "CLEAN CODE PREHOOK: If this task involves writing, editing, or generating ANY code, you MUST follow these principles:\n\n${SKILL_CONTENT//\"/\\\"}\n\nLoad the relevant references/ files from ${PLUGIN_ROOT}/skills/clean-code/references/ when you need detailed guidance on a specific topic (naming, functions, classes, comments, formatting, error-handling, testing)."
  }
}
ENDJSON

#!/usr/bin/env bash
# skill-logger-hook.sh
# PostToolUse hook that logs skill invocations to ~/.skill-session-log.jsonl
#
# Detects skill usage via:
# 1. Skill tool invocations (tool_name: "Skill")
# 2. SKILL.md reads from any location (plugin cache, /mnt/skills/, ~/.claude/skills/)

set -euo pipefail

LOG_FILE="$HOME/.skill-session-log.jsonl"

# Read hook event from stdin
INPUT=$(cat)

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

SKILL_NAME=""
FILE_PATH=""

case "$TOOL_NAME" in
  Skill)
    # Direct skill invocation via /skill-name or /plugin:skill-name
    SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
    # Handle namespaced skills: "plugin-name:skill-name" → "skill-name"
    if [[ "$SKILL_NAME" == *":"* ]]; then
      SKILL_NAME="${SKILL_NAME##*:}"
    fi
    ;;
  Read|View)
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
    ;;
  Bash)
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if echo "$COMMAND" | grep -qE '(cat|less|head|tail|bat)\s+.*SKILL\.md'; then
      FILE_PATH=$(echo "$COMMAND" | grep -oE '/[^ ]*SKILL\.md' | head -1)
    fi
    ;;
  *)
    exit 0
    ;;
esac

# Extract skill name from SKILL.md file path if not already set
if [ -z "$SKILL_NAME" ] && [ -n "$FILE_PATH" ]; then
  # Match any SKILL.md path:
  #   /mnt/skills/{scope}/{skill}/SKILL.md
  #   ~/.claude/plugins/cache/{marketplace}/{plugin}/{version}/skills/{skill}/SKILL.md
  #   ~/.claude/skills/{skill}/SKILL.md
  #   .claude/skills/{skill}/SKILL.md
  if echo "$FILE_PATH" | grep -qE 'SKILL\.md$'; then
    # Get the directory name containing SKILL.md — that's the skill name
    SKILL_DIR=$(dirname "$FILE_PATH")
    SKILL_NAME=$(basename "$SKILL_DIR")
  fi
fi

[ -z "$SKILL_NAME" ] && exit 0

# Get project name from cwd in the hook event, fallback to PWD
PROJECT_NAME=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null | xargs basename 2>/dev/null || basename "${PWD:-unknown}")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Append to log
jq -n \
  --arg skill "$SKILL_NAME" \
  --arg timestamp "$TIMESTAMP" \
  --arg tool "$TOOL_NAME" \
  --arg project "$PROJECT_NAME" \
  '{skill: $skill, timestamp: $timestamp, tool: $tool, project: $project}' \
  >> "$LOG_FILE"

exit 0

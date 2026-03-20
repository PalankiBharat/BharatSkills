#!/usr/bin/env bash
# skill-logger-hook.sh
# PostToolUse hook that logs skill invocations to ~/.skill-session-log.jsonl
#
# Receives the PostToolUse event JSON on stdin from Claude Code.
# Detects when a SKILL.md file under /mnt/skills/ is read and logs it.
#
# JSON input schema (from Claude Code):
# {
#   "tool_name": "Read",
#   "tool_input": { "file_path": "/mnt/skills/user/feature-analyzer/SKILL.md" },
#   "tool_response": { ... },
#   "cwd": "/path/to/project",
#   ...
# }

set -euo pipefail

LOG_FILE="$HOME/.skill-session-log.jsonl"

# Read hook event from stdin
INPUT=$(cat)

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[ -z "$TOOL_NAME" ] && exit 0

# Detect SKILL.md reads
FILE_PATH=""

case "$TOOL_NAME" in
  Read|View)
    # Read tool: file_path in tool_input
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
    ;;
  Bash)
    # Bash tool: check if command reads a SKILL.md
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if echo "$COMMAND" | grep -qE '(cat|less|head|tail|bat)\s+.*SKILL\.md'; then
      FILE_PATH=$(echo "$COMMAND" | grep -oE '/[^ ]*SKILL\.md' | head -1)
    fi
    ;;
  *)
    exit 0
    ;;
esac

# Only log reads of /mnt/skills/**/SKILL.md
[ -z "$FILE_PATH" ] && exit 0
echo "$FILE_PATH" | grep -qE '^/mnt/skills/.*/SKILL\.md$' || exit 0

# Extract skill name: /mnt/skills/{scope}/{skill-name}/SKILL.md → skill-name
SKILL_NAME=$(echo "$FILE_PATH" | sed -E 's|^/mnt/skills/[^/]+/([^/]+)/SKILL\.md$|\1|')
[ -z "$SKILL_NAME" ] || [ "$SKILL_NAME" = "$FILE_PATH" ] && exit 0

# Get project name from cwd in the hook event, fallback to PWD
PROJECT_NAME=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null | xargs basename 2>/dev/null || basename "${PWD:-unknown}")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Append to log
jq -n \
  --arg skill "$SKILL_NAME" \
  --arg timestamp "$TIMESTAMP" \
  --arg file_path "$FILE_PATH" \
  --arg project "$PROJECT_NAME" \
  '{skill: $skill, timestamp: $timestamp, file_path: $file_path, project: $project}' \
  >> "$LOG_FILE"

exit 0

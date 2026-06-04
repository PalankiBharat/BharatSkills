#!/usr/bin/env bash
# feedback.sh <lane> <target> <text...>
#   task  <name|role> <text>   -> append (redacted) to .harness/<role>/feedback.md  (this run)
#   skill <skill>     <text>   -> append (redacted) to the durable cross-run store
# Skill feedback is a continuous side-channel; it never gates the pipeline.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; . "$HERE/lib.sh"
ROOT="${HARNESS_ROOT:-$(git rev-parse --show-toplevel)/.harness}"
STORE="${DEV_HARNESS_HOME:-$HOME/.dev-harness}/skill-feedback"

LANE="${1:?lane: task|skill}"; TARGET="${2:?target}"; shift 2 || true
TEXT="$*"; [ -n "$TEXT" ] || { echo "no feedback text" >&2; exit 2; }

case "$LANE" in
  task)
    ROLE="$(resolve_role "$TARGET")" || { echo "unknown target: $TARGET" >&2; exit 2; }
    printf '%s\n' "$TEXT" | redact_secrets >> "$ROOT/$ROLE/feedback.md"
    ;;
  skill)
    mkdir -p "$STORE"
    printf -- '- %s\n' "$TEXT" | redact_secrets >> "$STORE/$TARGET.md"
    ;;
  *) echo "lane must be task|skill" >&2; exit 2 ;;
esac

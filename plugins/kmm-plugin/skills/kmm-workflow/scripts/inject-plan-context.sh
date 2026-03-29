#!/usr/bin/env bash
# UserPromptSubmit: injects plan context — delegates to resolve-gameplan.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat | "$SCRIPT_DIR/resolve-gameplan.sh" plan-header

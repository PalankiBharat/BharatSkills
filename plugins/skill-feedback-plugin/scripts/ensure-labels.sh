#!/usr/bin/env bash
# ensure-labels.sh — Creates the label taxonomy on the skill marketplace repo.
# Safe to run multiple times — skips labels that already exist.

set -euo pipefail

CONFIG_FILE="$HOME/.skill-feedback-config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ No repo configured. Run repo setup first."
  exit 1
fi

REPO=$(jq -r '.repo' "$CONFIG_FILE")
echo "🏷️  Ensuring labels on $REPO..."

# Helper: create label if it doesn't exist
create_label() {
  local name="$1"
  local color="$2"
  local description="$3"

  if gh label list -R "$REPO" --json name -q ".[].name" 2>/dev/null | grep -qx "$name"; then
    echo "  ✓ $name (exists)"
  else
    gh label create "$name" -R "$REPO" --color "$color" --description "$description" 2>/dev/null && \
      echo "  ✅ $name (created)" || \
      echo "  ⚠️  $name (failed to create)"
  fi
}

echo ""
echo "Priority labels:"
create_label "priority:P0" "B60205" "Fix immediately — blocking or broken"
create_label "priority:P1" "D93F0B" "Fix this week — recurring or significant"
create_label "priority:P2" "FBCA04" "Backlog — nice to have"

echo ""
echo "Type labels:"
create_label "type:friction"            "1D76DB" "Workflow friction — had to correct or re-run"
create_label "type:output-quality"      "0075CA" "Output was wrong, incomplete, or poorly formatted"
create_label "type:missing-capability"  "5319E7" "Feature the skill should support but doesn't"
create_label "type:triggering"          "E4E669" "Skill failed to trigger or triggered incorrectly"

echo ""
echo "Skill labels will be created dynamically as feedback is generated."
echo "Session labels (session:YYYY-MM-DD) will be created per feedback run."
echo ""
echo "✅ Label setup complete."

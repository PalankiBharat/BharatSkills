#!/usr/bin/env bash
marker="${CLAUDE_PROJECT_DIR:-$PWD}/.kmm/migrations/ACTIVE"
[ -f "$marker" ] || exit 0
slug=$(head -n 1 "$marker")
state_dir=$(sed -n 's/^state=//p' "$marker")
phase=""
if [ -n "$state_dir" ] && [ -f "$state_dir/state.json" ]; then
  phase=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("phase", "?"))' "$state_dir/state.json" 2>/dev/null)
fi
echo "kmm-pipeline: migration '$slug' is in flight (phase ${phase:-unknown}). Guard hooks are armed for app/src, shared/src, and Punch/. Resume with /kmm-pipeline:migrate resume (state: ${state_dir:-unknown})."
exit 0

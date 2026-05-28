#!/usr/bin/env bash
# setup-worktrees.sh — build the two source trees a parity run compares:
#   - master : a detached worktree at the LATEST origin/master ("source of truth")
#   - pr     : a detached worktree at the PR head
#
# Why two fresh worktrees: master and a KMM-migration PR build the SAME applicationId
# (com.marketpulse.sniper.vte, production flavor, no suffix), so they cannot coexist on
# one device. We build each from its own tree and put one per emulator. Worktrees keep
# the user's working checkout untouched and let us hold both trees on disk at once.
#
# Fresh worktrees only contain TRACKED files, so build-required but gitignored files
# (local.properties for sdk.dir, etc.) are copied in from the user's checkout.
#
# Usage: setup-worktrees.sh <pr-number-or-url> [sniper-repo-root] [run-dir]
#   sniper-repo-root  defaults to `git rev-parse --show-toplevel` of CWD
#   run-dir           defaults to $HOME/.kmm-parity/pr-<num>
#
# Baseline override (testing an ALREADY-MERGED PR): set BASELINE_REF to the master commit to
# compare against (e.g. the merge commit's first parent, "<mergeSha>^1"). Default is the live
# tip origin/master. Use this only when latest master already contains the migration (so the
# normal master-vs-PR diff would be empty).
#
# Writes <run-dir>/state.env with MASTER_WT, PR_WT, MASTER_REF, PR_BRANCH, PR_NUM, SNIPER_ROOT, RUN_DIR.

set -euo pipefail

PR_INPUT="${1:?usage: setup-worktrees.sh <pr-number-or-url> [sniper-repo-root] [run-dir]}"
SNIPER_ROOT="${2:-$(git rev-parse --show-toplevel)}"
SNIPER_ROOT="$(cd "$SNIPER_ROOT" && pwd -P)"

# --- sanity: this must be a sniper-v2-android checkout ---
case "$(basename "$SNIPER_ROOT")" in
  sniper-v2-android*) : ;;
  *) echo "Refusing: '$SNIPER_ROOT' does not look like a sniper-v2-android checkout." >&2
     echo "Pass the repo root explicitly as arg 2 if this is wrong." >&2
     exit 2 ;;
esac

command -v gh >/dev/null || { echo "GitHub CLI 'gh' is required (brew install gh; gh auth login)." >&2; exit 2; }

# --- resolve the PR via gh (accepts a number or a full URL) ---
# Run gh from inside the sniper repo so it infers the correct GitHub repo from origin,
# regardless of the caller's current directory.
PR_JSON="$(cd "$SNIPER_ROOT" && gh pr view "$PR_INPUT" --json number,headRefName,headRefOid,baseRefName)"
PR_NUM="$(printf '%s' "$PR_JSON"  | python3 -c 'import json,sys;print(json.load(sys.stdin)["number"])')"
PR_REF="$(printf '%s' "$PR_JSON"  | python3 -c 'import json,sys;print(json.load(sys.stdin)["headRefName"])')"
PR_BASE="$(printf '%s' "$PR_JSON" | python3 -c 'import json,sys;print(json.load(sys.stdin)["baseRefName"])')"

RUN_DIR="${3:-$HOME/.kmm-parity/pr-$PR_NUM}"
mkdir -p "$RUN_DIR"
WT_BASE="$RUN_DIR/worktrees"
MASTER_WT="$WT_BASE/master"
PR_WT="$WT_BASE/pr"
PR_LOCAL_BRANCH="kmm-parity-pr-$PR_NUM"

MASTER_REF="${BASELINE_REF:-origin/master}"
echo "PR #$PR_NUM  head=$PR_REF  base=$PR_BASE"
echo "Run dir: $RUN_DIR"
echo "Baseline (A) ref: $MASTER_REF"
[ "$PR_BASE" = "master" ] || echo "Note: PR base is '$PR_BASE', but per design we diff against the baseline ref above."

# --- clean any prior run's worktrees, then prune stale registrations ---
for wt in "$MASTER_WT" "$PR_WT"; do
  if git -C "$SNIPER_ROOT" worktree list --porcelain | grep -qxF "worktree $wt"; then
    git -C "$SNIPER_ROOT" worktree remove --force "$wt" 2>/dev/null || true
  fi
  rm -rf "$wt"
done
git -C "$SNIPER_ROOT" worktree prune

# --- fetch latest master + the PR head (pull/N/head works for fork PRs too) ---
echo "Fetching latest origin/master and PR head..."
git -C "$SNIPER_ROOT" fetch --quiet origin master
git -C "$SNIPER_ROOT" fetch --quiet --force origin "pull/$PR_NUM/head:$PR_LOCAL_BRANCH"
# Baseline ref may be a sha not reachable from master's tip alone — widen the fetch if needed.
git -C "$SNIPER_ROOT" rev-parse --verify --quiet "$MASTER_REF^{commit}" >/dev/null || \
  git -C "$SNIPER_ROOT" fetch --quiet origin

# --- create the worktrees (master at the baseline ref; PR at its head) ---
mkdir -p "$WT_BASE"
git -C "$SNIPER_ROOT" worktree add --detach "$MASTER_WT" "$MASTER_REF"
git -C "$SNIPER_ROOT" worktree add --force "$PR_WT" "$PR_LOCAL_BRANCH"

MASTER_SHA="$(git -C "$MASTER_WT" rev-parse --short HEAD)"
PR_SHA="$(git -C "$PR_WT" rev-parse --short HEAD)"
echo "master worktree @ origin/master ($MASTER_SHA)"
echo "pr worktree     @ $PR_REF ($PR_SHA)"

# --- copy build-required but gitignored files into both worktrees ---
# These are not tracked, so a fresh worktree lacks them and Gradle would fail.
copy_in() {
  local rel="$1"
  if [ -f "$SNIPER_ROOT/$rel" ]; then
    cp "$SNIPER_ROOT/$rel" "$MASTER_WT/$rel" 2>/dev/null || true
    cp "$SNIPER_ROOT/$rel" "$PR_WT/$rel" 2>/dev/null || true
    echo "  copied $rel"
  fi
}
echo "Copying gitignored build inputs from your checkout..."
copy_in "local.properties"
copy_in "app/google-services.json"
copy_in "google-services.json"
# Fallback: ensure each worktree at least knows the SDK location.
for wt in "$MASTER_WT" "$PR_WT"; do
  if [ ! -f "$wt/local.properties" ] && [ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]; then
    printf 'sdk.dir=%s\n' "${ANDROID_HOME:-$ANDROID_SDK_ROOT}" > "$wt/local.properties"
    echo "  wrote fallback local.properties -> $wt"
  fi
done

# --- persist state for the rest of the run ---
cat > "$RUN_DIR/state.env" <<EOF
SNIPER_ROOT="$SNIPER_ROOT"
RUN_DIR="$RUN_DIR"
PR_NUM="$PR_NUM"
PR_BRANCH="$PR_REF"
PR_LOCAL_BRANCH="$PR_LOCAL_BRANCH"
MASTER_REF="$MASTER_REF"
MASTER_WT="$MASTER_WT"
PR_WT="$PR_WT"
MASTER_SHA="$MASTER_SHA"
PR_SHA="$PR_SHA"
EOF

echo "State written to $RUN_DIR/state.env"
echo "Diff for the heatmap:  git -C \"$MASTER_WT\" diff $MASTER_REF...$PR_LOCAL_BRANCH"

#!/usr/bin/env bash
# ingest.sh — Phase 0 of kmm-pr-review.
# Detects PR source (URL/branch/diff), computes diff against master, copies master baselines into state dir.
#
# Usage:
#   ingest.sh [--pr URL] [--diff PATH] [--base REF] [--state DIR]
# If neither --pr nor --diff: assumes current checked-out branch, diffs against origin/master.
# If --base not given: tries origin/master then origin/main.

set -euo pipefail

PR_URL=""
DIFF_PATH=""
BASE_REF=""
STATE_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR_URL="$2"; shift 2 ;;
        --diff) DIFF_PATH="$2"; shift 2 ;;
        --base) BASE_REF="$2"; shift 2 ;;
        --state) STATE_DIR="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Establish repo root + identity
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [[ -z "$REPO_ROOT" ]] && [[ -z "$DIFF_PATH" ]]; then
    echo "Not in a git repo and no --diff supplied." >&2
    exit 2
fi

ORIGIN_URL="$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null || echo "$REPO_ROOT")"
REPO_HASH="$(printf '%s\n' "$ORIGIN_URL" | sha256sum | cut -c1-12)"
BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "detached")"
HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")"

# State directory
if [[ -z "$STATE_DIR" ]]; then
    STATE_DIR="$HOME/.kmm-pr-review/$REPO_HASH/$BRANCH"
fi
mkdir -p "$STATE_DIR"/{findings,cache,master-baselines}

# Resolve base ref
if [[ -z "$BASE_REF" ]]; then
    for cand in origin/master origin/main master main; do
        if git -C "$REPO_ROOT" rev-parse --verify "$cand" >/dev/null 2>&1; then
            BASE_REF="$cand"; break
        fi
    done
fi
if [[ -z "$BASE_REF" ]]; then
    echo "Cannot resolve base ref (tried origin/master, origin/main, master, main)." >&2
    exit 2
fi

# Fetch PR if URL given (and capture title/body for migration keyword detection)
PR_META_FILE="$STATE_DIR/pr_meta.json"
if [[ -n "$PR_URL" ]]; then
    if ! command -v gh >/dev/null 2>&1; then
        echo "PR URL given but 'gh' CLI not found." >&2
        exit 2
    fi
    PR_NUM="$(printf '%s\n' "$PR_URL" | sed -E 's|.*/pull/([0-9]+).*|\1|')"
    PR_REPO="$(printf '%s\n' "$PR_URL" | sed -E 's|https://github.com/([^/]+/[^/]+)/.*|\1|')"
    gh -R "$PR_REPO" pr checkout "$PR_NUM"
    BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
    HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    # Capture title/body for migration keyword detection in classify.py
    gh -R "$PR_REPO" pr view "$PR_NUM" --json title,body,number,url > "$PR_META_FILE" 2>/dev/null || echo '{}' > "$PR_META_FILE"
else
    # Try to find a PR for the current branch (optional, best-effort)
    if command -v gh >/dev/null 2>&1; then
        gh -R "$(git -C "$REPO_ROOT" config --get remote.origin.url 2>/dev/null | sed -E 's|.*github\.com[:/]([^/]+/[^/]+)\.git|\1|; s|.*github\.com[:/]([^/]+/[^/]+)$|\1|')" \
            pr view --json title,body,number,url > "$PR_META_FILE" 2>/dev/null || echo '{}' > "$PR_META_FILE"
    else
        echo '{}' > "$PR_META_FILE"
    fi
fi

# Compute diff (file list with rename detection)
DIFF_FILE="$STATE_DIR/diff.namestatus"
if [[ -n "$DIFF_PATH" ]]; then
    # Pasted diff: extract file list
    grep -E '^(diff --git|rename from|rename to)' "$DIFF_PATH" \
        | awk '/^diff --git/ {print "M\t" $4} /^rename from/ {print "R\t" $3 "\t"}' \
        > "$DIFF_FILE" || true
else
    git -C "$REPO_ROOT" diff --name-status -M "$BASE_REF"...HEAD > "$DIFF_FILE"
fi

# Copy master baselines into the state dir for every file in the diff (old paths for renames; new paths for modifications)
BASELINE_DIR="$STATE_DIR/master-baselines"
while IFS=$'\t' read -r status path1 path2; do
    case "$status" in
        A) ;; # added — no master baseline
        M)
            mkdir -p "$BASELINE_DIR/$(dirname "$path1")"
            git -C "$REPO_ROOT" show "$BASE_REF:$path1" > "$BASELINE_DIR/$path1" 2>/dev/null || true
            ;;
        D)
            mkdir -p "$BASELINE_DIR/$(dirname "$path1")"
            git -C "$REPO_ROOT" show "$BASE_REF:$path1" > "$BASELINE_DIR/$path1" 2>/dev/null || true
            ;;
        R*)
            # path1 = old, path2 = new; copy old baseline
            mkdir -p "$BASELINE_DIR/$(dirname "$path1")"
            git -C "$REPO_ROOT" show "$BASE_REF:$path1" > "$BASELINE_DIR/$path1" 2>/dev/null || true
            ;;
    esac
done < "$DIFF_FILE"

# Emit metadata for Phase 1
cat > "$STATE_DIR/ingest.json" <<JSON
{
  "repo_hash": "$REPO_HASH",
  "branch": "$BRANCH",
  "base_ref": "$BASE_REF",
  "head_sha": "$HEAD_SHA",
  "repo_root": "$REPO_ROOT",
  "state_dir": "$STATE_DIR",
  "diff_file": "$DIFF_FILE",
  "pr_meta_file": "$PR_META_FILE"
}
JSON

echo "$STATE_DIR"

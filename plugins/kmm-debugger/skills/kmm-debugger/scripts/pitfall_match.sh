#!/usr/bin/env bash
# pitfall_match.sh — return candidate pitfall numbers + one-liners matching a symptom phrase.
#
# Usage:
#   pitfall_match.sh "UniqueViolationException"
#   pitfall_match.sh "wrong backend URL"
#   pitfall_match.sh "init time leak"
#
# Output:
#   Zero or more lines of "Pitfall #N: <title> — <one-line description>"
#   sorted by match count (highest first). Exits 0 even if no matches.
#
# Why this script exists:
# Loading the full pitfalls.md is ~6000 tokens. When only one pitfall is relevant,
# this script returns just the candidate(s) without loading the catalog. The parent
# then chooses to read the full entry from pitfalls.md if the candidate looks right.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") \"<symptom-phrase>\"" >&2
  exit 1
fi

QUERY="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PITFALLS_FILE="$SCRIPT_DIR/../references/pitfalls.md"

if [[ ! -f "$PITFALLS_FILE" ]]; then
  echo "Error: pitfalls.md not found at $PITFALLS_FILE" >&2
  exit 1
fi

# One-line summaries kept in sync with SKILL.md's pitfall index.
# Using a case statement instead of `declare -A` for compatibility with bash 3.2
# (the default on macOS — `declare -A` requires bash 4+).
summary_for() {
  case "$1" in
    1) echo "commonMain can't read AGP BuildConfig — forced BuildKonfig everywhere, wrong-flavor AARs in multi-flavor publish." ;;
    2) echo "Room KMP suspend DAOs in commonMain — async cache + observer machinery to bridge a sync API; race window after init." ;;
    3) echo "ObjectBox/Realm → Room with no in-place data migration — init-time refetch + event chains that no host handles." ;;
    4) echo "Init-time coroutine machinery — singleton scopes never cancelled; observer collectors accumulating across re-inits." ;;
    5) echo "Transitive dep version drift at consumer — POM pulls higher versions than consumer's declared pins." ;;
    6) echo "Multi-flavor publishing limitations — BuildKonfig 0.17.0 generates one file per Gradle invocation; silent wrong-flavor AARs." ;;
    7) echo "Latent invariant in expect/actual or annotation-driven schemas — SDK encodes load-bearing invariant on undocumented BE contract; contract drift surfaces as SDK crash." ;;
    *) echo "(no summary for pitfall #$1)" ;;
  esac
}

# Build per-pitfall keyword corpus from the markdown.
# Awk parses `## N. <title>` headers and accumulates each pitfall's body into a
# single line, then emits one TSV row per pitfall. Uses POSIX-compatible awk
# (no GNU-only 3-arg match) so it works on macOS BSD awk and gawk alike.
awk '
  # Pitfall header: "## N. <title>" — extract the integer N via $2 then strip trailing dot.
  /^## [0-9]+\./ {
    if (current_n != "") print current_n "\t" corpus
    n = $2
    sub(/\./, "", n)
    current_n = n
    corpus = $0
    in_relevant = 1
    next
  }
  # Non-numeric "## " header marks end of pitfalls (e.g., "## Cross-cutting principle").
  /^## [^0-9]/ {
    if (current_n != "") print current_n "\t" corpus
    current_n = ""
    in_relevant = 0
    next
  }
  /^---$/ {
    in_relevant = 0
    next
  }
  in_relevant && current_n != "" {
    corpus = corpus " " $0
  }
  END {
    if (current_n != "") print current_n "\t" corpus
  }
' "$PITFALLS_FILE" > /tmp/pitfall_corpus.$$.tsv

# Tokenize the query (lowercase, split on whitespace, dedupe).
QUERY_LOWER=$(printf '%s' "$QUERY" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' '\n' | sort -u)

# Score each pitfall by counting unique query-token hits in its corpus.
SCORES=$(while IFS=$'\t' read -r n corpus; do
  corpus_lower=$(printf '%s' "$corpus" | tr '[:upper:]' '[:lower:]')
  score=0
  while read -r tok; do
    [[ -z "$tok" ]] && continue
    if [[ "$corpus_lower" == *"$tok"* ]]; then
      score=$((score + 1))
    fi
  done <<< "$QUERY_LOWER"
  if (( score > 0 )); then
    printf '%d\t%d\n' "$score" "$n"
  fi
done < /tmp/pitfall_corpus.$$.tsv | sort -rn)

rm -f /tmp/pitfall_corpus.$$.tsv

if [[ -z "$SCORES" ]]; then
  echo "No pitfall matches for: \"$QUERY\""
  echo ""
  echo "Consider scanning the full catalog at references/pitfalls.md, or — if no pitfall fits — note this in the closing retro (Q1) so a new pitfall entry can be added."
  exit 0
fi

while IFS=$'\t' read -r score n; do
  echo "Pitfall #$n (score $score): $(summary_for "$n")"
done <<< "$SCORES"

echo ""
echo "Read the full entry: less +/'^## $(echo "$SCORES" | head -1 | cut -f2)\\.' references/pitfalls.md"

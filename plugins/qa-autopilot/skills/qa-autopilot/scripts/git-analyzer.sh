#!/bin/bash
# git-analyzer.sh — Extracts structured change context from current branch vs master
# Usage: bash git-analyzer.sh [base_branch]
# Output: Structured analysis of all changes suitable for QA test generation

set -euo pipefail

BASE_BRANCH="${1:-master}"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "UNKNOWN")

# Ensure we're in a git repo
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "ERROR: Not inside a git repository"
    exit 1
fi

# Ensure base branch exists
if ! git rev-parse --verify "$BASE_BRANCH" &>/dev/null; then
    echo "ERROR: Base branch '$BASE_BRANCH' not found"
    echo "Available branches:"
    git branch -a | head -20
    exit 1
fi

echo "============================================"
echo "  QA AUTOPILOT — Git Change Analysis"
echo "============================================"
echo ""
echo "Branch:  $CURRENT_BRANCH"
echo "Base:    $BASE_BRANCH"
echo "Date:    $(date '+%Y-%m-%d %H:%M %Z')"
echo ""

# ── Commit summary ──────────────────────────────────────────────
echo "## COMMITS"
echo "---"
COMMIT_COUNT=$(git rev-list --count "$BASE_BRANCH"..HEAD 2>/dev/null || echo "0")
echo "Total commits: $COMMIT_COUNT"
echo ""
git log "$BASE_BRANCH"..HEAD --oneline --no-decorate 2>/dev/null || echo "(no commits)"
echo ""

# ── File change summary ────────────────────────────────────────
echo "## FILE CHANGES"
echo "---"
git diff "$BASE_BRANCH"...HEAD --stat 2>/dev/null || git diff "$BASE_BRANCH"..HEAD --stat 2>/dev/null
echo ""

# ── Categorized file list ──────────────────────────────────────
echo "## CATEGORIZED CHANGES"
echo "---"

# Get changed files with status
CHANGED_FILES=$(git diff "$BASE_BRANCH"...HEAD --name-status 2>/dev/null || git diff "$BASE_BRANCH"..HEAD --name-status 2>/dev/null)

if [ -z "$CHANGED_FILES" ]; then
    echo "No changes found between $CURRENT_BRANCH and $BASE_BRANCH"
    exit 0
fi

# Categorize files
echo ""
echo "### Kotlin/Java Source Files (App Logic)"
echo "$CHANGED_FILES" | grep -E "\.(kt|java)$" | grep -v -E "(test/|androidTest/|build/)" || echo "  (none)"

echo ""
echo "### UI Files (Screens, Composables, Layouts)"
echo "$CHANGED_FILES" | grep -E "(Screen\.kt|Fragment\.kt|Activity\.kt|Composable|/ui/|/screen/|/compose/|\.xml$)" | grep -v -E "(test/|build/)" || echo "  (none)"

echo ""
echo "### ViewModel Files"
echo "$CHANGED_FILES" | grep -E "(ViewModel\.kt|/viewmodel/)" | grep -v -E "(test/|build/)" || echo "  (none)"

echo ""
echo "### Data/Repository/Network Files"
echo "$CHANGED_FILES" | grep -E "(Repository|Dao|Api|Service|/data/|/network/|/repository/|/api/|/db/)" | grep -v -E "(test/|build/)" || echo "  (none)"

echo ""
echo "### Model/Entity Files"
echo "$CHANGED_FILES" | grep -E "(Model\.kt|Entity\.kt|Dto\.kt|/model/|/entity/|/dto/)" | grep -v -E "(test/|build/)" || echo "  (none)"

echo ""
echo "### Navigation Files"
echo "$CHANGED_FILES" | grep -E "(NavGraph|Route|Navigation|/navigation/)" | grep -v -E "(test/|build/)" || echo "  (none)"

echo ""
echo "### DI/Module Files"
echo "$CHANGED_FILES" | grep -E "(Module\.kt|Component\.kt|/di/|/hilt/)" | grep -v -E "(test/|build/)" || echo "  (none)"

echo ""
echo "### Resource Files"
echo "$CHANGED_FILES" | grep -E "(/res/|strings\.xml|colors\.xml|themes\.xml|styles\.xml)" || echo "  (none)"

echo ""
echo "### Build/Config Files"
echo "$CHANGED_FILES" | grep -E "(build\.gradle|\.toml|\.properties|proguard|AndroidManifest)" || echo "  (none)"

echo ""
echo "### Test Files"
echo "$CHANGED_FILES" | grep -E "(test/|androidTest/|Test\.kt|Spec\.kt)" || echo "  (none)"

echo ""
echo "### Other Files"
echo "$CHANGED_FILES" | grep -v -E "\.(kt|java|xml|gradle|toml|properties)$" || echo "  (none)"

# ── New functions/classes added ─────────────────────────────────
echo ""
echo "## NEW FUNCTIONS & CLASSES"
echo "---"
git diff "$BASE_BRANCH"...HEAD --diff-filter=AM -- '*.kt' '*.java' 2>/dev/null | \
    grep -E "^\+.*(fun |class |object |interface |sealed |enum |data class |@Composable)" | \
    grep -v "^\+\+\+" | \
    sed 's/^\+/  /' | head -50 || echo "  (none detected)"

# ── Modified function signatures ────────────────────────────────
echo ""
echo "## MODIFIED FUNCTION SIGNATURES"
echo "---"
git diff "$BASE_BRANCH"...HEAD -- '*.kt' '*.java' 2>/dev/null | \
    grep -E "^[-+].*(fun |class |interface )" | \
    grep -v "^\+\+\+\|^---" | head -50 || echo "  (none detected)"

# ── UI-specific changes ────────────────────────────────────────
echo ""
echo "## UI-SPECIFIC CHANGES"
echo "---"

# Composable changes
COMPOSE_CHANGES=$(git diff "$BASE_BRANCH"...HEAD -- '*.kt' 2>/dev/null | \
    grep -E "^\+.*(@Composable|remember|LaunchedEffect|mutableStateOf|collectAsState|Modifier\.|Column|Row|Box|Text\(|Button\(|TextField|LazyColumn|LazyRow|Scaffold|TopAppBar|BottomNavigation)" | \
    grep -v "^\+\+\+" | head -30)
if [ -n "$COMPOSE_CHANGES" ]; then
    echo "### Compose UI Changes:"
    echo "$COMPOSE_CHANGES" | sed 's/^\+/  /'
else
    echo "  (no Compose UI changes detected)"
fi

echo ""

# Navigation changes
NAV_CHANGES=$(git diff "$BASE_BRANCH"...HEAD -- '*.kt' 2>/dev/null | \
    grep -E "^\+.*(NavHost|composable\(|navigate\(|popBackStack|NavController|deepLink|navArgument)" | \
    grep -v "^\+\+\+" | head -20)
if [ -n "$NAV_CHANGES" ]; then
    echo "### Navigation Changes:"
    echo "$NAV_CHANGES" | sed 's/^\+/  /'
else
    echo "  (no navigation changes detected)"
fi

# ── Dependency/import analysis ──────────────────────────────────
echo ""
echo "## DEPENDENCY HINTS"
echo "---"
echo "### New imports added:"
git diff "$BASE_BRANCH"...HEAD -- '*.kt' '*.java' 2>/dev/null | \
    grep -E "^\+import " | \
    grep -v "^\+\+\+" | \
    sort -u | sed 's/^\+/  /' | head -30 || echo "  (none)"

echo ""
echo "### Removed imports:"
git diff "$BASE_BRANCH"...HEAD -- '*.kt' '*.java' 2>/dev/null | \
    grep -E "^-import " | \
    grep -v "^---" | \
    sort -u | sed 's/^-/  /' | head -30 || echo "  (none)"

# ── Full diff for context ───────────────────────────────────────
echo ""
echo "## FULL DIFF"
echo "---"
echo "(Truncated to first 500 lines. Run 'git diff $BASE_BRANCH...HEAD' for complete diff)"
echo ""
git diff "$BASE_BRANCH"...HEAD 2>/dev/null | head -500

echo ""
echo "============================================"
echo "  Analysis complete. Feed this to QA Autopilot."
echo "============================================"

#!/usr/bin/env python3
"""
PreToolUse hook for kmm-migration: blocks edits to frozen baseline tests
unless a corresponding .kmm/exceptions/<id>.md file references the file.

Why this exists (per SKILL.md cross-cutting "Migration-exception process"):
  "Skill itself refuses to edit frozen baselines without a corresponding
   exception file present — this is the primary enforcement layer."
This hook converts that advisory rule into deterministic enforcement.

Reads JSON from stdin describing the proposed tool call. Exit codes:
  0  → allow (write proceeds)
  2  → block (write rejected; message printed to stderr is shown to Claude)
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

# Baseline-test path heuristic — covers Phase B (androidUnitTest) and post-E
# (commonTest). The destination module path is project-specific, so we match
# on the source-set segment only.
BASELINE_PATH_RE = re.compile(
    r"/src/(androidUnitTest|commonTest)/", re.IGNORECASE
)

# Statuses at/after Phase C freeze. Phase B audited rows are NOT frozen yet
# (still pre-C), but the freeze flips audited → frozen at C.3. Conservative:
# block anything from `frozen` onward.
FROZEN_STATUSES = {"frozen", "migrated", "promoted"}


def find_session_coverage(path: Path) -> Path | None:
    """Walk up from `path` looking for a .kmm/migrations/*/coverage.md.

    A baseline test inside the worktree may sit several levels below the repo
    root; .kmm/ lives at the repo root.
    """
    for parent in [path, *path.parents]:
        candidate = parent / ".kmm" / "migrations"
        if candidate.is_dir():
            for session in candidate.iterdir():
                cov = session / "coverage.md"
                if cov.is_file():
                    return cov
    return None


def find_all_coverage(path: Path) -> list[Path]:
    """Find every coverage.md under any ancestor's .kmm/migrations/.

    Multiple parallel sessions (worktrees) may have separate coverage files.
    """
    for parent in [path, *path.parents]:
        root = parent / ".kmm" / "migrations"
        if root.is_dir():
            return list(root.glob("*/coverage.md"))
    return []


def status_for_file(target: Path, coverage_files: list[Path]) -> str | None:
    """Read each coverage.md and find the row referring to `target`.

    coverage.md is a Markdown table — but the path column often uses `.../`
    as a package-segment placeholder (e.g.,
    `shared/src/androidUnitTest/.../FundsUseCaseTest.kt`). We therefore
    match on **basename uniqueness**: per `test-discipline` §3 "Mirror the
    package", test file names are unique within the codebase, so a basename
    match in a coverage row is a reliable identifier.

    Returns the lowercased Status value if found, else None. Status comes
    from any cell in the matched row that equals a known status keyword.
    """
    name_lower = target.name.lower()
    for cov in coverage_files:
        try:
            text = cov.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for line in text.splitlines():
            line_lower = line.lower()
            if name_lower not in line_lower:
                continue
            # Skip the header separator rows that aren't real entries.
            stripped = line.strip()
            if stripped.startswith("|--") or stripped.startswith("|=="):
                continue
            cells = [c.strip().lower() for c in line.split("|")]
            for status in FROZEN_STATUSES:
                if status in cells:
                    return status
    return None


def exception_references(target: Path, coverage_files: list[Path]) -> bool:
    """Check whether any .kmm/exceptions/*.md references this baseline.

    SKILL.md mandates: "Exception file at .kmm/exceptions/<YYYY-MM-DD>-<id>.md
    with: what changed, why, risk, user sign-off." A real exception file
    SHOULD name the baseline it covers. We match on the file's basename
    appearing in any exception file.
    """
    if not coverage_files:
        return False
    # exceptions live at .kmm/exceptions/ — same .kmm root as coverage
    kmm_root = coverage_files[0].parent.parent.parent  # coverage.md → session/ → migrations/ → .kmm/
    exc_dir = kmm_root / "exceptions"
    if not exc_dir.is_dir():
        return False
    needle = target.name
    for exc in exc_dir.glob("*.md"):
        try:
            text = exc.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if needle in text or str(target) in text:
            return True
    return False


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        # Malformed input — don't block legitimate work, but log
        print("[frozen_baseline_guard] could not parse stdin JSON; allowing",
              file=sys.stderr)
        return 0

    tool_name = payload.get("tool_name") or payload.get("toolName") or ""
    if tool_name not in {"Write", "Edit", "MultiEdit", "str_replace", "create_file"}:
        return 0

    tool_input = payload.get("tool_input") or payload.get("toolInput") or {}
    raw_path = (
        tool_input.get("file_path")
        or tool_input.get("path")
        or tool_input.get("filepath")
        or ""
    )
    if not raw_path:
        return 0

    path = Path(raw_path).resolve() if os.path.isabs(raw_path) else Path(raw_path)

    if not BASELINE_PATH_RE.search(str(path)):
        return 0  # not a baseline test path

    coverage_files = find_all_coverage(path)
    if not coverage_files:
        # No .kmm/migrations/ in scope → not under skill governance. Allow.
        return 0

    status = status_for_file(path, coverage_files)
    if status not in FROZEN_STATUSES:
        return 0  # pre-freeze, or unknown (e.g., feature-surface test not in coverage)

    if exception_references(path, coverage_files):
        # Exception present — allow, but make it visible.
        print(
            f"[frozen_baseline_guard] write to FROZEN baseline {path.name} "
            f"allowed: matching .kmm/exceptions/*.md found.",
            file=sys.stderr,
        )
        return 0

    # Block
    msg = (
        f"\n[frozen_baseline_guard] BLOCKED: {path}\n\n"
        f"This baseline test is in status `{status}` per coverage.md. "
        f"Edits to frozen baselines require a corresponding "
        f".kmm/exceptions/<YYYY-MM-DD>-<short-id>.md file that references "
        f"this baseline by name and documents: what changed, why, risk, "
        f"user sign-off.\n\n"
        f"Options:\n"
        f"  1. If divergence is intentional → create the exception file "
        f"first, then retry the edit.\n"
        f"  2. If the baseline is genuinely wrong → invoke the "
        f"migration-exception process (Opus confirms intent, user signs "
        f"off, then proceed).\n"
        f"  3. If you're trying to fix a flake → STOP. A frozen baseline "
        f"that fails is signal, not noise; investigate the production "
        f"divergence instead.\n"
    )
    print(msg, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())

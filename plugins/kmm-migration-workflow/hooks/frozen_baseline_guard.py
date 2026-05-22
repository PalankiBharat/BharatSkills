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


def _kmm_root_from_coverage(coverage_path: Path) -> Path:
    """Resolve `.kmm/` root from a coverage.md path.

    Layout: <repo>/.kmm/migrations/kmm/<feature>-<depth>/coverage.md
    Walk up until a directory named `.kmm` is found, NOT a fixed parent
    chain — historic chains undercounted by one and pointed at
    `.kmm/migrations/` instead of `.kmm/`.
    """
    for ancestor in coverage_path.parents:
        if ancestor.name == ".kmm":
            return ancestor
    # Fallback: best-effort fixed walk
    return coverage_path.parent.parent.parent.parent


def _parse_authorizes_baseline_edit(exc_text: str) -> list[str] | None:
    """Parse the `Authorizes.baseline-edit` list from an exception file.

    Schema (per test-discipline/migration-baselines.md):
        - **Authorizes**:
          ...
          - `baseline-edit`: <list of file paths, or "none">

    Returns the list of paths if found, [] if `none`, or None if the field
    isn't present (legacy exception schema — fall back to plain-text match).
    """
    # Find the Authorizes block — accept various Markdown styles.
    m = re.search(
        r"\*?\*?Authorizes\*?\*?\s*:?(.*?)(?=\n\s*-\s*\*\*[A-Z]|\Z)",
        exc_text, re.DOTALL,
    )
    if not m:
        return None
    block = m.group(1)
    be = re.search(
        r"baseline[-_]?edit\s*[:`]+\s*(.+?)(?=\n\s*-|\Z)",
        block, re.DOTALL | re.IGNORECASE,
    )
    if not be:
        return None
    content = be.group(1).strip().strip("`").strip()
    if content.lower() in {"none", "[]", "[ ]"}:
        return []
    # Split list items: support bullet-list, comma-separated, or inline list.
    items: list[str] = []
    for line in content.splitlines():
        stripped = line.strip().lstrip("-*").strip().strip("`").strip()
        if not stripped:
            continue
        # Comma-separated on one line
        for piece in stripped.split(","):
            piece = piece.strip().strip("`").strip()
            if piece and piece.lower() not in {"none"}:
                items.append(piece)
    return items if items else None


def exception_references(target: Path, coverage_files: list[Path]) -> tuple[bool, str | None]:
    """Check whether any .kmm/exceptions/*.md authorizes editing this baseline.

    Returns (authorized, exception_id) — the exception_id is the filename
    stem of the matching exception, surfaced to the user via the green-light
    stderr line.

    Matching:
      1. Prefer the structured `Authorizes.baseline-edit` list (per
         migration-baselines.md schema). Match by filename basename
         appearing in the list OR by full-path suffix match.
      2. Legacy fallback: plain-text basename search in the exception body
         (covers pre-schema exception files).
    """
    if not coverage_files:
        return (False, None)
    kmm_root = _kmm_root_from_coverage(coverage_files[0])
    exc_dir = kmm_root / "exceptions"
    if not exc_dir.is_dir():
        return (False, None)
    target_name = target.name
    target_str = str(target)
    for exc in exc_dir.glob("*.md"):
        try:
            text = exc.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        # Structured-schema check first.
        authorized_list = _parse_authorizes_baseline_edit(text)
        if authorized_list is not None:
            for entry in authorized_list:
                if entry == target_name or target_str.endswith(entry) or entry.endswith(target_name):
                    return (True, exc.stem)
            # Structured schema present and target not listed → skip this file.
            continue
        # Legacy fallback: plain-text basename match.
        if target_name in text or target_str in text:
            return (True, exc.stem)
    return (False, None)


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

    authorized, exc_id = exception_references(path, coverage_files)
    if authorized:
        # Green-light feedback — make it impossible to wonder whether the hook fired.
        print(
            f"[frozen_baseline_guard] ✓ Edit to FROZEN baseline {path.name} "
            f"authorized by exception {exc_id}.md (status was `{status}`).",
            file=sys.stderr,
        )
        return 0

    # Block
    msg = (
        f"\n[frozen_baseline_guard] ✗ BLOCKED: {path}\n\n"
        f"This baseline test is in status `{status}` per coverage.md. "
        f"Edits to frozen baselines require a corresponding "
        f".kmm/exceptions/<YYYY-MM-DD>-<short-id>.md file with this "
        f"baseline listed under `Authorizes.baseline-edit`, plus what "
        f"changed, why, risk, and user sign-off.\n\n"
        f"Options:\n"
        f"  1. If divergence is intentional → create the exception file "
        f"first (or extend an existing one via the Amendments section), "
        f"then retry the edit.\n"
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

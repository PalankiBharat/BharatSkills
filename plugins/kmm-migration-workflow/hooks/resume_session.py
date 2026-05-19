#!/usr/bin/env python3
"""
SessionStart hook for kmm-migration: emit a structured state report when
the session starts on a `kmm/<feature>-<depth>` branch with a matching
`.kmm/migrations/<feature>-<depth>/` folder.

Why this exists (per SKILL.md "Resume protocol"):
  Previously the skill dispatched a Haiku subagent at every invocation to
  read every phase file and reconstruct state. This hook does the same
  extraction deterministically — and BEFORE Claude's first turn — so the
  raw phase files never enter main context. Claude's first turn sees the
  state report and picks up at the next pending task.

Output:
  Markdown printed to stdout is appended to the session's initial context
  (Claude Code SessionStart hook contract). If not on a kmm/ branch, or
  no matching session folder, the hook is silent.

Phase file format (per SKILL.md "Phase file format"):
  Status: not-started | in-progress | complete
  Last updated: <ISO timestamp>
  Tasks: - [x] / - [ ] checkboxes
  ## Decisions log: chronological bullets
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


# Phase metadata: (phase_id, output_filename, human_name). Order matters —
# phases proceed in this sequence.
PHASES = [
    ("0", "scope.md",       "Discovery & Scoping"),
    ("A", "plan.md",        "Diagnostic"),
    ("B", "audit.md",       "Structural relocation + Baselines"),
    ("C", "freeze.md",      "Freeze"),
    ("D", "migration.md",   "KMM-ification"),
    ("E", "move.md",        "Baseline promotion"),
    ("F", "validation.md",  "Validation"),
    ("G", "pr.md",          "PR Creation"),
]


def current_branch() -> str | None:
    try:
        result = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    branch = result.stdout.strip()
    return branch or None


def find_kmm_root(start: Path) -> Path | None:
    """Walk up from `start` looking for a .kmm/ directory."""
    for parent in [start, *start.parents]:
        candidate = parent / ".kmm"
        if candidate.is_dir():
            return candidate
    return None


def session_folder(kmm_root: Path, branch: str) -> Path | None:
    """Resolve session folder from branch name.

    Branch convention: `kmm/<feature>-<depth>` → folder
    `.kmm/migrations/kmm/<feature>-<depth>/`.
    """
    if not branch.startswith("kmm/"):
        return None
    suffix = branch[len("kmm/"):]
    candidate = kmm_root / "migrations" / "kmm" / suffix
    if candidate.is_dir():
        return candidate
    return None


def parse_phase_file(path: Path) -> dict | None:
    """Extract structured state from a phase file."""
    if not path.is_file():
        return None
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    status_match = re.search(r"^Status:\s*(.+?)\s*$", text, re.MULTILINE)
    status = status_match.group(1).strip().lower() if status_match else "unknown"

    updated_match = re.search(r"^Last updated:\s*(.+?)\s*$", text, re.MULTILINE)
    last_updated = updated_match.group(1).strip() if updated_match else None

    done = re.findall(r"^-\s*\[x\]\s*(.+?)\s*$", text, re.MULTILINE | re.IGNORECASE)
    pending = re.findall(r"^-\s*\[ \]\s*(.+?)\s*$", text, re.MULTILINE)

    # Decisions log: capture the chronological bullets after `## Decisions log`.
    decisions: list[str] = []
    dlog = re.search(
        r"^##\s*Decisions log[^\n]*\n(.*?)(?=^##\s|\Z)",
        text, re.MULTILINE | re.DOTALL,
    )
    if dlog:
        for line in dlog.group(1).splitlines():
            stripped = line.strip()
            if stripped.startswith("- ") and len(stripped) > 2:
                decisions.append(stripped[2:].strip())

    return {
        "status": status,
        "last_updated": last_updated,
        "done_count": len(done),
        "pending_count": len(pending),
        "next_pending": pending[0] if pending else None,
        "recent_decisions": decisions[-3:],
    }


def active_phase(states: dict[str, dict | None]) -> tuple[str, str, str] | None:
    """Pick the active phase: first non-complete in order; complete sentinel if all done."""
    for phase_id, filename, name in PHASES:
        s = states.get(phase_id)
        if s is None:
            return (phase_id, filename, name)
        if s["status"] != "complete":
            return (phase_id, filename, name)
    return None  # everything complete


def git_dirty() -> bool | None:
    """Returns True if there are uncommitted changes, False if clean, None on error."""
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain"],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return bool(result.stdout.strip())


def format_report(branch: str, folder: Path, states: dict[str, dict | None]) -> str:
    lines: list[str] = []
    lines.append("## KMM migration — resume report")
    lines.append("")
    lines.append(
        f"This report was generated by the `resume_session` hook from the "
        f"phase files in `{folder.relative_to(folder.parents[2]) if len(folder.parents) >= 3 else folder}/`. "
        f"Raw phase files are NOT in your context; pull them in on demand "
        f"when work resumes in a specific phase."
    )
    lines.append("")
    lines.append(f"- **Branch:** `{branch}`")
    lines.append(f"- **Session folder:** `{folder}/`")
    dirty = git_dirty()
    if dirty is True:
        lines.append("- **Working tree:** uncommitted changes present — review before continuing.")
    elif dirty is False:
        lines.append("- **Working tree:** clean.")
    lines.append("")

    # Phase status table
    lines.append("### Phase status")
    lines.append("")
    lines.append("| Phase | File | Status | Done / Pending | Last updated |")
    lines.append("|---|---|---|---|---|")
    for phase_id, filename, _name in PHASES:
        s = states.get(phase_id)
        if s is None:
            lines.append(f"| {phase_id} | `{filename}` | _not started_ | — | — |")
        else:
            ratio = f"{s['done_count']} / {s['pending_count']}"
            updated = s["last_updated"] or "—"
            lines.append(
                f"| {phase_id} | `{filename}` | {s['status']} | {ratio} | {updated} |"
            )
    lines.append("")

    # Active phase detail
    active = active_phase(states)
    if active is None:
        lines.append("### Active phase: **none — all phases complete**")
        lines.append("")
        lines.append(
            "All phases through G report `complete`. If the PR has not yet "
            "merged, the next action is verifying the merge / running the "
            "session retro. If the session is post-merge, offer worktree "
            "cleanup per Phase E post-session steps."
        )
    else:
        phase_id, filename, name = active
        lines.append(f"### Active phase: **{phase_id} — {name}**")
        lines.append("")
        s = states.get(phase_id)
        if s is None:
            lines.append(
                f"Phase {phase_id} has not been started yet (no `{filename}` "
                f"in the session folder). Begin Phase {phase_id} per "
                f"`references/phases/phase-{phase_id.lower()}-*.md`. Load that "
                f"phase reference now."
            )
        else:
            if s["next_pending"]:
                lines.append(f"- **Next pending task:** {s['next_pending']}")
            else:
                lines.append(
                    "- **Next pending task:** none recorded; phase shows "
                    "`in-progress` without pending checkboxes — inspect "
                    f"`{filename}` directly to find the next step."
                )
            lines.append(f"- **Active phase file:** `{folder.name}/{filename}` (load on demand)")

    # Cross-phase decision recap (most recent 5 across all phases)
    all_decisions: list[tuple[str, str]] = []
    for phase_id, _filename, _name in PHASES:
        s = states.get(phase_id)
        if s:
            for d in s["recent_decisions"]:
                all_decisions.append((phase_id, d))
    if all_decisions:
        lines.append("")
        lines.append("### Recent decisions (most recent first, across phases)")
        lines.append("")
        for phase_id, decision in reversed(all_decisions[-5:]):
            lines.append(f"- Phase {phase_id}: {decision}")

    lines.append("")
    lines.append(
        "**Resume action:** the active phase reference is the next file to "
        "load. Do NOT bulk-read other phase files — this report already "
        "contains their state."
    )

    return "\n".join(lines) + "\n"


def main() -> int:
    branch = current_branch()
    if not branch:
        return 0  # not in a git repo, or git missing → silent
    if not branch.startswith("kmm/"):
        return 0  # not a migration branch → silent

    kmm_root = find_kmm_root(Path.cwd())
    if kmm_root is None:
        # On kmm/ branch but no .kmm/ root — likely fresh worktree post-Phase-0-setup.
        print(
            f"## KMM migration — fresh worktree\n\n"
            f"On branch `{branch}` but `.kmm/` not yet initialized. "
            f"Phase 0 (`references/phases/phase-0-discovery.md`) should run "
            f"here to create `.kmm/migrations/{branch[len('kmm/'):]}/` and "
            f"begin discovery.\n"
        )
        return 0

    folder = session_folder(kmm_root, branch)
    if folder is None:
        suffix = branch[len("kmm/"):]
        print(
            f"## KMM migration — fresh session\n\n"
            f"On branch `{branch}` but no matching session folder at "
            f"`.kmm/migrations/{suffix}/`. Begin Phase 0 here.\n"
        )
        return 0

    # Parse every phase file present
    states: dict[str, dict | None] = {}
    for phase_id, filename, _name in PHASES:
        states[phase_id] = parse_phase_file(folder / filename)

    print(format_report(branch, folder, states))
    return 0


if __name__ == "__main__":
    sys.exit(main())

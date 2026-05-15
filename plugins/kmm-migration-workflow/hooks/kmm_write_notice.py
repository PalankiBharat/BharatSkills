#!/usr/bin/env python3
"""
PostToolUse hook for kmm-migration: surfaces every write to .kmm/ so silent
writes are at least visible in the transcript.

Why this exists (per SKILL.md cross-cutting "Diff-confirm protocol"):
  "No silent writes anywhere. The checklist ritual is not optional —
   skipping it is a discipline violation."
A stronger version of this would be a PreToolUse hook that blocks writes
without a matching pre-staged accept marker; that requires the skill to
cooperate by writing the marker before each user-confirmed write. This
advisory version simply emits a conspicuous transcript entry whenever a
.kmm/ write happens so a missed diff-confirm is auditable after the fact.

Exit codes:
  0  → silent (no .kmm/ write happened)
  0  → also for .kmm/ writes (with a notice printed to stderr)
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
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

    path_str = str(Path(raw_path))
    if "/.kmm/" not in path_str and not path_str.endswith("/.kmm") \
       and not path_str.startswith(".kmm/"):
        return 0

    # Inside .kmm/ — make the write visible.
    # Per SKILL.md, every .kmm/ write must have been preceded by a diff-confirm
    # prompt that the user accepted with `a` (or explicit accept). If the
    # current transcript shows a write to .kmm/ that wasn't preceded by such a
    # prompt, that's a protocol violation.
    print(
        f"\n[kmm_write_notice] .kmm/ write: {path_str}\n"
        f"  Audit: did this follow a diff-confirm prompt the user accepted "
        f"in the prior turn?  If not, this is a silent write — abort and "
        f"re-issue the diff prompt.\n",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

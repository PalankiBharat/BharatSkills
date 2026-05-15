#!/usr/bin/env python3
"""
post_review.py — Phase 7: post review to GitHub via the Reviews API.

Approval-gated by design — the orchestrator must ask the user before
invoking this script. One review per invocation with N inline comments +
a review body, posted via `gh api`.

Reads from <state_dir>:
  - pr_meta.json — owner/repo/number from `gh pr view --json`
  - findings.verified.json (or findings.merged.json fallback)

Args:
  --state <dir>           state directory (required)
  --verdict <verdict>     "Block" | "Request changes" | "Approve with nits"
                          | "Approve" (required)
  --dry-run               print the payload JSON, don't post

The orchestrator (Opus) is expected to pre-rewrite `why` and `suggestion`
on each finding into plain language before calling this script. The script
itself renders What/How verbatim from those fields — it does no rewriting.

Inline-eligibility: a finding posts inline only if its (file, line) falls
inside a `+` or context line of the PR's diff hunks (RIGHT side). Off-diff
findings fall back to the review body under "Other findings (outside the
diff)" — nothing is dropped.
"""

from __future__ import annotations
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

VERDICT_TO_EVENT = {
    "Block": "REQUEST_CHANGES",
    "Request changes": "REQUEST_CHANGES",
    "Approve with nits": "COMMENT",
    "Approve": "APPROVE",
}

HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
DIFF_RE = re.compile(r"^diff --git a/(.+) b/(.+)$")
PR_URL_RE = re.compile(r"https?://github\.com/([^/]+)/([^/]+)/pull/(\d+)")


def parse_diff_hunks(patch_text: str) -> dict[str, set[int]]:
    """Return {repo-relative path -> set of new-file line numbers covered by any diff hunk}."""
    by_path: dict[str, set[int]] = {}
    current_path: str | None = None
    new_line: int | None = None
    for line in patch_text.splitlines():
        m = DIFF_RE.match(line)
        if m:
            current_path = m.group(2)
            by_path.setdefault(current_path, set())
            new_line = None
            continue
        if current_path is None:
            continue
        if line.startswith("@@ "):
            hm = HUNK_RE.match(line)
            if hm:
                new_line = int(hm.group(1))
            continue
        if new_line is None:
            continue
        if line.startswith("+++") or line.startswith("---"):
            continue
        if line.startswith("+") or line.startswith(" "):
            by_path[current_path].add(new_line)
            new_line += 1
        # "-" lines and meta lines: don't advance the new-file cursor
    return by_path


def first_sentence(text: str, max_len: int = 110) -> str:
    text = (text or "").strip()
    m = re.search(r"[.!?](\s|$)", text)
    end = m.end() if m else len(text)
    s = text[:end].rstrip(".!? ")
    if len(s) > max_len:
        s = s[:max_len].rstrip() + "…"
    return s


def render_finding_body(finding: dict) -> str:
    why = (finding.get("why") or "").strip()
    suggestion = (finding.get("suggestion") or "").strip()
    source = (finding.get("source") or "").strip()
    severity = finding.get("severity", "")
    rule_id = finding.get("rule_id", "?")
    summary = first_sentence(why) or rule_id
    parts = [f"**[{severity} · {rule_id}] {summary}**", ""]
    if why:
        parts.append(f"**What:** {why}")
    if suggestion:
        parts.append(f"**How:** {suggestion}")
    parts.append("")
    if source:
        parts.append(f"**Source:** {source}")
    return "\n".join(parts).strip()


def load_findings(state_dir: Path) -> list[dict]:
    for name in ("findings.verified.json", "findings.merged.json"):
        p = state_dir / name
        if p.exists():
            data = json.loads(p.read_text())
            return data.get("findings") or []
    return []


def load_pr_target(state_dir: Path) -> tuple[str, str, int]:
    """Return (owner, repo, pr_number) from pr_meta.json."""
    pr_meta = json.loads((state_dir / "pr_meta.json").read_text())
    pr_num = pr_meta.get("number")
    pr_url = pr_meta.get("url", "")
    if not pr_num or not pr_url:
        raise SystemExit("pr_meta.json missing number/url; cannot post")
    m = PR_URL_RE.match(pr_url)
    if not m:
        raise SystemExit(f"cannot parse PR URL: {pr_url}")
    return m.group(1), m.group(2), int(pr_num)


def gh_pr_diff(owner: str, repo: str, pr_num: int) -> str:
    proc = subprocess.run(
        ["gh", "pr", "diff", str(pr_num), "--patch", "--repo", f"{owner}/{repo}"],
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise SystemExit(f"gh pr diff failed: {proc.stderr}")
    return proc.stdout


def build_payload(args, findings: list[dict], hunks: dict[str, set[int]]) -> dict:
    event = VERDICT_TO_EVENT[args.verdict]
    inline: list[dict] = []
    off_diff: list[dict] = []
    for f in findings:
        path = f.get("file") or ""
        line = f.get("line")
        if path in hunks and isinstance(line, int) and line in hunks[path]:
            inline.append({
                "path": path,
                "line": line,
                "side": "RIGHT",
                "body": render_finding_body(f),
            })
        else:
            off_diff.append(f)

    body_parts = [f"**Verdict:** {args.verdict}", ""]
    if not inline and not off_diff:
        body_parts.append("No findings.")
    if off_diff:
        body_parts.append("## Other findings (outside the diff)")
        body_parts.append("")
        for f in off_diff:
            body_parts.append(
                f"### `{f.get('file')}`:{f.get('line', '?')} — {f.get('rule_id', '?')}"
            )
            body_parts.append("")
            body_parts.append(render_finding_body(f))
            body_parts.append("")

    return {
        "event": event,
        "body": "\n".join(body_parts).strip(),
        "comments": inline,
    }, inline, off_diff


def post(owner: str, repo: str, pr_num: int, payload: dict) -> dict:
    proc = subprocess.run(
        ["gh", "api", "-X", "POST",
         f"/repos/{owner}/{repo}/pulls/{pr_num}/reviews",
         "--input", "-"],
        input=json.dumps(payload),
        capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise SystemExit(f"gh api failed: {proc.stderr}")
    return json.loads(proc.stdout)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", required=True, type=Path)
    ap.add_argument("--verdict", required=True, choices=list(VERDICT_TO_EVENT))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    state_dir: Path = args.state
    owner, repo, pr_num = load_pr_target(state_dir)
    findings = load_findings(state_dir)

    patch = gh_pr_diff(owner, repo, pr_num)
    hunks = parse_diff_hunks(patch)
    payload, inline, off_diff = build_payload(args, findings, hunks)

    if args.dry_run:
        print(json.dumps({
            "owner": owner, "repo": repo, "pr_number": pr_num,
            "inline_count": len(inline),
            "off_diff_count": len(off_diff),
            "payload": payload,
        }, indent=2))
        return

    response = post(owner, repo, pr_num, payload)
    print(json.dumps({
        "review_url": response.get("html_url"),
        "inline_count": len(inline),
        "off_diff_count": len(off_diff),
    }, indent=2))


if __name__ == "__main__":
    main()

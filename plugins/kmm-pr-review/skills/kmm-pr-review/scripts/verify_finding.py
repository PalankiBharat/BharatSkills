#!/usr/bin/env python3
"""
verify_finding.py — deterministic verification of a candidate finding.

For each rule_id, we have a programmatic check (grep, regex, AST sniff, file-existence)
that confirms or denies the finding. Returns "verified", "rejected", or "unknown" (no check
exists, or the check can't make a confident call).

The aggregator runs this before shipping any finding. Hallucinated findings are caught here.

Two invocation modes:

1) Single finding:
   verify_finding.py <state_dir> --rule S-TYPE-01 --file shared/.../X.kt --line 10
   
2) Batch (reads findings.merged.json, writes findings.verified.json):
   verify_finding.py <state_dir> --batch

Output for single mode: JSON to stdout with verdict + evidence.
Output for batch mode: writes findings.verified.json next to findings.merged.json.
"""

from __future__ import annotations
import argparse
import json
import re
import sys
from pathlib import Path
from typing import Optional, Callable


# ---- Verifier registry ----

VerifierResult = dict  # {"verdict": "verified"|"rejected"|"unknown", "evidence": str}


def _read_file(state_dir: Path, repo_root: Path, file_path: str) -> Optional[str]:
    """Reads the current PR version of the file from the repo root."""
    p = repo_root / file_path
    if p.exists() and p.is_file():
        try:
            return p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None
    return None


def _read_master(state_dir: Path, file_path: str) -> Optional[str]:
    """Reads the master baseline of the file from the state dir's master-baselines/."""
    p = state_dir / "master-baselines" / file_path
    if p.exists() and p.is_file():
        try:
            return p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return None
    return None


def _check_line_window(content: str, line: int, pattern: re.Pattern, window: int = 3) -> tuple[str, str]:
    """
    Check whether `pattern` matches at line ± window, anywhere in file, or nowhere.

    Returns (verdict, evidence):
      - "verified"  — pattern matched within line ± window. Reported line is correct (or close enough).
      - "unknown"   — pattern matched in the file but outside the line window. Rule applies but the
                      specialist reported the wrong line; user can find the real issue with grep.
      - "rejected"  — pattern not found anywhere in the file. The finding is hallucinated or stale.

    `window` is the tolerance in lines on each side of the reported line.
    """
    lines = content.split("\n")
    if not lines:
        return ("rejected", "Empty file.")
    # Indices are 0-based; the reported `line` is 1-based.
    lo = max(0, line - 1 - window)
    hi = min(len(lines), line + window)
    for i in range(lo, hi):
        if pattern.search(lines[i]):
            snippet = lines[i].strip()[:100]
            return ("verified", f"Match at line {i+1} (within window of reported line {line}): {snippet}")
    # Pattern not in the window — check the rest of the file
    for i, l in enumerate(lines):
        if pattern.search(l):
            snippet = l.strip()[:100]
            return ("unknown", f"Pattern found at line {i+1}, but reported line {line} is outside the window. Rule applies; line precision is wrong.")
    return ("rejected", "Pattern not found anywhere in the file.")


# Each verifier signature: (content, file_path, line, master_content, repo_root) -> VerifierResult


def v_jvm_imports_in_commonmain(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """S-TYPE-01 / NC-05 / VM-06 / REPO-03 / M-BUILD-01 — JVM/Android imports in commonMain."""
    if "/src/commonMain/" not in file_path:
        return {"verdict": "rejected", "evidence": "File is not in commonMain; rule does not apply here."}
    pat = re.compile(r"^\s*import\s+(java\.|javax\.|android\.|kotlin\.jvm\.)")
    verdict, evidence = _check_line_window(content, line, pat, window=2)
    return {"verdict": verdict, "evidence": evidence}


def v_at_throws_on_ios_suspend(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """S-CORO-03 / I-READY-04 / UC-04 / REPO-04 — public suspend exposed to iOS without @Throws."""
    if "/src/commonMain/" not in file_path and "iosMain" not in file_path:
        return {"verdict": "unknown", "evidence": "File not clearly in iOS-exposed surface; manual review required."}
    lines = content.split("\n")
    suspend_re = re.compile(r"^\s*(public\s+)?suspend\s+(operator\s+)?fun\s+\w+")
    throws_re = re.compile(r"^\s*@Throws\s*\(")
    candidates = []
    for i, l in enumerate(lines, start=1):
        if suspend_re.match(l):
            window = lines[max(0, i - 6):i - 1]
            if not any(throws_re.match(w) for w in window):
                candidates.append(i)
    if not candidates:
        return {"verdict": "rejected", "evidence": "All suspend functions in this file have @Throws (or no suspend functions exist)."}
    # Apply ±3 line tolerance to the reported line
    if any(abs(c - line) <= 3 for c in candidates):
        return {"verdict": "verified", "evidence": f"Suspend without @Throws at line {min(candidates, key=lambda c: abs(c - line))} (reported line {line}, within tolerance)."}
    return {"verdict": "unknown", "evidence": f"Unannotated suspend exists at lines {candidates} but reported line {line} is outside ±3 tolerance. Rule applies; line is wrong."}


def v_expect_body(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """S-EA-04 — expect declaration has a body."""
    pat = re.compile(r"^\s*expect\s+(fun|class|val|var|object)\s+\w+[^=\n]*(=\s*\S|\{)")
    verdict, evidence = _check_line_window(content, line, pat, window=2)
    return {"verdict": verdict, "evidence": evidence}


def v_stub_body(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """HYG-02 — stub function bodies (TODO(), NotImplementedError, etc.)."""
    pat = re.compile(r"\bTODO\(\s*\)|throw\s+NotImplementedError\b|error\(\s*[\"']not implemented")
    verdict, evidence = _check_line_window(content, line, pat, window=3)
    return {"verdict": verdict, "evidence": evidence}


def v_inline_value_class_in_public_api(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """I-READY-01 / S-TYPE-04 / MOD-04 — inline/value class or Result in public iOS-exposed API."""
    # Two patterns: @JvmInline value class declaration, or Result<...> in a function signature
    pat = re.compile(r"@JvmInline|value\s+class|\bResult<[^>]+>")
    verdict, evidence = _check_line_window(content, line, pat, window=3)
    if verdict == "verified":
        # Sanity-check: if it's Result<...>, must be in a signature (not body)
        lines = content.split("\n")
        idx = max(0, line - 1)
        nearby = "\n".join(lines[max(0, idx - 3):idx + 4])
        if "Result<" in nearby and "fun " not in nearby and "val " not in nearby and "var " not in nearby:
            return {"verdict": "unknown", "evidence": "Result<T> seen near the line but not clearly in a public signature; manual check needed."}
    return {"verdict": verdict, "evidence": evidence}


def v_skie_plugin_present(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """I-SKIE-01 / B-03 — SKIE Gradle plugin applied in :shared/build.gradle.kts."""
    # Look at the build.gradle.kts under shared/
    candidates = list(repo_root.glob("shared/build.gradle.kts")) + list(repo_root.glob("*/shared/build.gradle.kts"))
    if not candidates:
        # Try the file in the finding itself
        candidates = [repo_root / file_path] if (repo_root / file_path).exists() else []
    for c in candidates:
        try:
            txt = c.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if re.search(r'id\s*\(\s*[\"\']co\.touchlab\.skie[\"\']', txt):
            return {"verdict": "rejected", "evidence": f"{c}: SKIE plugin id present."}
        return {"verdict": "verified", "evidence": f"{c}: SKIE plugin id NOT present in plugins{{}} block."}
    return {"verdict": "unknown", "evidence": "Could not locate shared/build.gradle.kts; manual review required."}


def v_old_path_deleted(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """M-CLEANUP-01 — addition under :shared/commonMain without deletion of old android-only file."""
    # This check looks at the diff (not single file). The aggregator passes us a state_dir-relative diff.
    state_dir = Path(repo_root).parent if (Path(repo_root) / ".kmm-state").exists() else None
    # Heuristic fallback: check whether the basename also exists in app/src/main/
    basename = Path(file_path).name
    legacy_candidates = list(repo_root.glob(f"app/src/main/**/{basename}")) + list(repo_root.glob(f"androidApp/src/main/**/{basename}"))
    if legacy_candidates:
        return {"verdict": "verified", "evidence": f"Old file still present: {legacy_candidates[0]}"}
    return {"verdict": "rejected", "evidence": "No old android-only file with the same basename found."}


def v_no_hilt_annotations(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """DI-04 / M-CLEANUP-02 — Hilt/Dagger annotations on a class that shouldn't have them."""
    pat = re.compile(r"@Inject\s+constructor|@Module\b|@Provides\b|@Binds\b|@InstallIn\b|@HiltViewModel\b")
    verdict, evidence = _check_line_window(content, line, pat, window=5)
    return {"verdict": verdict, "evidence": evidence}


def v_top_level_function_in_ios_surface(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """I-READY-08 — top-level fun/val in commonMain (consumed from iOS)."""
    if "/src/commonMain/" not in file_path:
        return {"verdict": "rejected", "evidence": "Not in commonMain."}
    # Heuristic: a line starting at column 0 (or with `public ` prefix) that declares fun/val/var
    pat = re.compile(r"^(public\s+)?(fun|val|var)\s+\w+")
    verdict, evidence = _check_line_window(content, line, pat, window=2)
    return {"verdict": verdict, "evidence": evidence}


def v_freeze_patterns(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """S-CORO-05 — legacy freeze/Worker patterns."""
    pat = re.compile(r"\.freeze\s*\(|ensureNeverFrozen\s*\(|kotlin\.native\.concurrent\.AtomicReference|\bWorker\b")
    verdict, evidence = _check_line_window(content, line, pat, window=3)
    return {"verdict": verdict, "evidence": evidence}


def v_global_scope_in_viewmodel(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """VM-04 — ViewModel launches via GlobalScope or free CoroutineScope, not viewModelScope."""
    if not re.search(r":\s*ViewModel\s*\(", content):
        return {"verdict": "rejected", "evidence": "File is not a ViewModel."}
    pat = re.compile(r"\bGlobalScope\s*\.\s*launch|CoroutineScope\s*\(\s*Dispatchers")
    verdict, evidence = _check_line_window(content, line, pat, window=3)
    return {"verdict": verdict, "evidence": evidence}


def v_runblocking_in_test(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """T-02 — test uses runBlocking instead of runTest."""
    pat = re.compile(r"\brunBlocking\s*\{")
    verdict, evidence = _check_line_window(content, line, pat, window=3)
    return {"verdict": verdict, "evidence": evidence}


def v_collect_as_state(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """CS-04 — Compose uses collectAsState instead of collectAsStateWithLifecycle."""
    # If the file already uses the lifecycle variant, no finding (anywhere)
    if re.search(r"\.collectAsStateWithLifecycle\s*\(", content):
        return {"verdict": "rejected", "evidence": "collectAsStateWithLifecycle present in file; no fix needed."}
    pat = re.compile(r"\.collectAsState\s*\(")
    verdict, evidence = _check_line_window(content, line, pat, window=2)
    return {"verdict": verdict, "evidence": evidence}


def v_as_cast_on_skie_flow(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """SV-05 / I-SKIE-09 — Swift cast on SkieKotlin*Flow."""
    if not file_path.endswith(".swift"):
        return {"verdict": "rejected", "evidence": "Not a Swift file."}
    pat = re.compile(r"(as\s*[?!]|\bis\b)\s+SkieKotlin\w*Flow")
    verdict, evidence = _check_line_window(content, line, pat, window=2)
    return {"verdict": verdict, "evidence": evidence}


def v_long_function(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """NF-CLEAN-07 — function body >30 lines."""
    # Find the function starting at or just before `line`, count its body length.
    lines = content.split("\n")
    if line < 1 or line > len(lines):
        return {"verdict": "unknown", "evidence": "Line out of range."}
    # Find the opening brace of the function containing the reported line
    start = line - 1
    while start > 0 and not re.search(r"^\s*(public\s+|private\s+|internal\s+|protected\s+)?(suspend\s+)?(inline\s+)?(operator\s+)?fun\s+\w+", lines[start]):
        start -= 1
    # Count body lines until matching brace
    depth = 0
    body_lines = 0
    started = False
    for i in range(start, len(lines)):
        for ch in lines[i]:
            if ch == "{":
                depth += 1
                started = True
            elif ch == "}":
                depth -= 1
                if started and depth == 0:
                    if body_lines > 30:
                        return {"verdict": "verified", "evidence": f"Function body is {body_lines} lines (>30)."}
                    return {"verdict": "rejected", "evidence": f"Function body is {body_lines} lines (≤30)."}
        if started:
            body_lines += 1
    return {"verdict": "unknown", "evidence": "Could not parse function boundaries."}


def v_too_many_params(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """NF-CLEAN-08 — function with >5 parameters."""
    lines = content.split("\n")
    if line < 1 or line > len(lines):
        return {"verdict": "unknown", "evidence": "Line out of range."}
    # Try to find the fun declaration on or above the reported line
    accum = ""
    for i in range(max(0, line - 1), min(len(lines), line + 10)):
        accum += lines[i] + "\n"
        if ")" in lines[i]:
            break
    m = re.search(r"fun\s+\w+(?:<[^>]*>)?\s*\(([^)]*)\)", accum)
    if not m:
        return {"verdict": "unknown", "evidence": "Could not locate function signature."}
    params = [p.strip() for p in m.group(1).split(",") if p.strip()]
    if len(params) > 5:
        return {"verdict": "verified", "evidence": f"Function has {len(params)} parameters."}
    return {"verdict": "rejected", "evidence": f"Function has {len(params)} parameters (≤5)."}


def v_boolean_flag_param(content: str, file_path: str, line: int, master: Optional[str], repo_root: Path) -> VerifierResult:
    """NF-CLEAN-09 — boolean flag-style parameter."""
    lines = content.split("\n")
    if line < 1 or line > len(lines):
        return {"verdict": "unknown", "evidence": "Line out of range."}
    accum = ""
    for i in range(max(0, line - 1), min(len(lines), line + 10)):
        accum += lines[i] + "\n"
        if ")" in lines[i]:
            break
    m = re.search(r"fun\s+\w+\s*\(([^)]*)\)", accum)
    if not m:
        return {"verdict": "unknown", "evidence": "Could not locate function signature."}
    params = m.group(1)
    flag_pat = r"\b(is|should|use|skip|enable|disable|allow)\w*\s*:\s*Boolean\b"
    if re.search(flag_pat, params):
        return {"verdict": "verified", "evidence": "Boolean flag-like parameter detected."}
    return {"verdict": "rejected", "evidence": "No boolean flag-like parameter detected."}


# The registry mapping rule_id -> verifier function
VERIFIERS: dict[str, Callable] = {
    # Type leakage / KMP build correctness
    "S-TYPE-01": v_jvm_imports_in_commonmain,
    "NC-05": v_jvm_imports_in_commonmain,
    "VM-06": v_jvm_imports_in_commonmain,
    "REPO-03": v_jvm_imports_in_commonmain,
    "M-BUILD-01": v_jvm_imports_in_commonmain,
    # Suspend @Throws
    "S-CORO-03": v_at_throws_on_ios_suspend,
    "I-READY-04": v_at_throws_on_ios_suspend,
    "UC-04": v_at_throws_on_ios_suspend,
    "REPO-04": v_at_throws_on_ios_suspend,
    # expect/actual
    "S-EA-04": v_expect_body,
    # Stubs
    "HYG-02": v_stub_body,
    # Inline / value classes
    "I-READY-01": v_inline_value_class_in_public_api,
    "S-TYPE-04": v_inline_value_class_in_public_api,
    "MOD-04": v_inline_value_class_in_public_api,
    # SKIE plugin
    "I-SKIE-01": v_skie_plugin_present,
    "B-03": v_skie_plugin_present,
    # Migration cleanup
    "M-CLEANUP-01": v_old_path_deleted,
    # Hilt annotations
    "DI-04": v_no_hilt_annotations,
    "M-CLEANUP-02": v_no_hilt_annotations,
    # Top-level in iOS surface
    "I-READY-08": v_top_level_function_in_ios_surface,
    # Legacy freeze
    "S-CORO-05": v_freeze_patterns,
    # ViewModel scope
    "VM-04": v_global_scope_in_viewmodel,
    # Test idioms
    "T-02": v_runblocking_in_test,
    # Compose
    "CS-04": v_collect_as_state,
    # Swift / SKIE casts
    "SV-05": v_as_cast_on_skie_flow,
    "I-SKIE-09": v_as_cast_on_skie_flow,
    # Clean code
    "NF-CLEAN-07": v_long_function,
    "NF-CLEAN-08": v_too_many_params,
    "NF-CLEAN-09": v_boolean_flag_param,
}


def verify_one(state_dir: Path, repo_root: Path, finding: dict) -> dict:
    rule_id = finding.get("rule_id", "")
    if rule_id.startswith("AD-HOC-"):
        return {"verdict": "unknown", "evidence": "Ad-hoc finding; no programmatic verifier registered."}
    verifier = VERIFIERS.get(rule_id)
    if verifier is None:
        return {"verdict": "unknown", "evidence": f"No verifier registered for rule {rule_id}; rule may be subjective or judgment-based."}
    file_path = finding["file"]
    content = _read_file(state_dir, repo_root, file_path)
    if content is None:
        return {"verdict": "unknown", "evidence": f"Could not read file {file_path}."}
    master = _read_master(state_dir, file_path)
    line = finding.get("line", 1)
    try:
        return verifier(content, file_path, line, master, repo_root)
    except Exception as exc:
        return {"verdict": "unknown", "evidence": f"Verifier raised {type(exc).__name__}: {exc}"}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("state_dir")
    p.add_argument("--batch", action="store_true")
    p.add_argument("--rule")
    p.add_argument("--file")
    p.add_argument("--line", type=int)
    args = p.parse_args()

    state_dir = Path(args.state_dir)
    ingest = json.loads((state_dir / "ingest.json").read_text())
    repo_root = Path(ingest["repo_root"])

    if args.batch:
        merged_path = state_dir / "findings.merged.json"
        if not merged_path.exists():
            print("ERROR: findings.merged.json not found. Run dedupe first.", file=sys.stderr)
            sys.exit(1)
        merged = json.loads(merged_path.read_text())
        for f in merged["findings"]:
            result = verify_one(state_dir, repo_root, f)
            f["verified"] = result["verdict"]
            f["verification_evidence"] = result["evidence"]
        verified_path = state_dir / "findings.verified.json"
        verified_path.write_text(json.dumps(merged, indent=2))
        counts = {"verified": 0, "rejected": 0, "unknown": 0}
        for f in merged["findings"]:
            counts[f["verified"]] = counts.get(f["verified"], 0) + 1
        print(json.dumps({"output": str(verified_path), **counts}, indent=2))
    else:
        if not (args.rule and args.file):
            p.error("--rule and --file are required without --batch")
        finding = {"rule_id": args.rule, "file": args.file, "line": args.line or 1}
        result = verify_one(state_dir, repo_root, finding)
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()

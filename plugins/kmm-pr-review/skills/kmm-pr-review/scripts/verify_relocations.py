#!/usr/bin/env python3
"""
verify_relocations.py — Phase 3a deterministic sweep for haiku-1 RELOCATIONs.

Replaces the haiku-1 LLM tier with a script. For every plan.json entry with
swarm_tier == "haiku-1" and status == "pending", runs:

Path checks (every RELOCATION):
  - source-set/extension consistency (.kt -> src/<X>Main/ or Test/; .swift -> iosApp/)
  - test filename in test directory
  - M-CLEANUP-01 sanity: old path under app/src/main/** must not still exist in HEAD

Content greps (commonMain landings only):
  - S-TYPE-01 — `import java.|javax.|android.`
  - S-TYPE-02 — `import androidx.` not on the conservative KMP allowlist
  - S-TYPE-01 — qualified `java.util.{Date|Calendar|Locale|UUID|Optional|TimeZone}` usage
  - M-CLEANUP-02 — Hilt/Dagger annotations

Each entry's findings:
  - written to findings/<content_hash>.json (empty array if clean)
  - mirrored to cache/<content_hash>-<rules_hash>.json
  - plan.json entry's status flips to "done"

Usage: verify_relocations.py <state_dir>
"""

from __future__ import annotations
import json
import re
import subprocess
import sys
from pathlib import Path

# Conservative allowlist of androidx artifacts known to be KMP-published.
# On miss, we prefer a false positive (P1 with confidence:medium) over silence.
ANDROIDX_KMP_ALLOWLIST = (
    "androidx.annotation",
    "androidx.collection",
    "androidx.paging",
    "androidx.lifecycle.viewmodel",
)

VALID_SOURCE_SET_RE = re.compile(
    r"/src/([A-Za-z0-9]+Main|[A-Za-z0-9]+Test|[A-Za-z0-9]+UnitTest|test|main)/"
)
TEST_FILENAME_RE = re.compile(r".*(Test|Tests|Spec)\.(kt|swift)$")
TEST_DIR_RE = re.compile(r"(/[Tt]est/|/[Tt]ests/|UnitTest/|androidTest/)")

JVM_IMPORT_RE = re.compile(
    r"^\s*import\s+(java\.|javax\.|android\.[a-zA-Z_])", re.MULTILINE
)
ANDROIDX_IMPORT_RE = re.compile(r"^\s*import\s+(androidx\.[A-Za-z0-9._]+)")
JVM_QUALIFIED_USE_RE = re.compile(
    r"\bjava\.util\.(Date|Calendar|Locale|UUID|Optional|TimeZone)\b"
)
HILT_ANNOT_RE = re.compile(
    r"@(Inject|Module|Provides|Singleton|Binds|InstallIn|HiltViewModel)\b"
)


def make_finding(rule_id, file, line, severity, why, suggestion, source,
                 *, ios_blocking=False, confidence="high"):
    f = {
        "rule_id": rule_id,
        "file": file,
        "line": line,
        "severity": severity,
        "why": why,
        "suggestion": suggestion,
        "source": source,
        "attribution": "pr-induced",
        "specialist": "haiku-relocation",
        "confidence": confidence,
    }
    if ios_blocking:
        f["iOS_blocking"] = True
    return f


def is_kmp_androidx(import_path: str) -> bool:
    return any(import_path.startswith(p) for p in ANDROIDX_KMP_ALLOWLIST)


def check_path(entry):
    """Source-set/extension + test-dir checks. Returns list of findings (line=1)."""
    findings = []
    p = entry["file"]

    if p.endswith(".kt"):
        if "/src/" in p and not VALID_SOURCE_SET_RE.search(p):
            findings.append(make_finding(
                "AD-HOC-rel-source-set-mismatch",
                p, 1, "P1",
                (f"Kotlin file moved to '{p}' which has a /src/ segment but no "
                 f"recognized Kotlin source set (expected src/<name>Main/ or "
                 f"src/<name>Test/)."),
                ("Verify the destination source set. KMP files belong under "
                 "module/src/<targetName>Main/ (or commonMain/); tests under "
                 "the matching Test/ folder."),
                "https://kotlinlang.org/docs/multiplatform/multiplatform-discover-project.html",
                confidence="medium",
            ))
        elif "/src/" not in p:
            findings.append(make_finding(
                "AD-HOC-rel-source-set-mismatch",
                p, 1, "P1",
                (f"Kotlin file moved to '{p}' which is outside any /src/ "
                 f"directory. KMP source sets live under module/src/<name>Main/."),
                "Move the file under the correct module's src/ source set.",
                "https://kotlinlang.org/docs/multiplatform/multiplatform-discover-project.html",
                confidence="medium",
            ))
    elif p.endswith(".swift"):
        if not (p.startswith("iosApp/") or "/Sources/" in p):
            findings.append(make_finding(
                "AD-HOC-rel-source-set-mismatch",
                p, 1, "P1",
                (f"Swift file moved to '{p}' but is not under iosApp/ or a "
                 f"Swift Package Sources/ directory."),
                ("Verify the destination — Swift sources belong under iosApp/ "
                 "or a Swift Package's Sources/ directory."),
                "https://developer.apple.com/documentation/swift_packages",
                confidence="medium",
            ))

    if TEST_FILENAME_RE.match(Path(p).name) and not TEST_DIR_RE.search(p):
        findings.append(make_finding(
            "AD-HOC-rel-test-dir-mismatch",
            p, 1, "P2",
            (f"Filename '{Path(p).name}' suggests a test but the file is not "
             f"under a recognized test directory."),
            ("Move the test under src/commonTest/, src/androidUnitTest/, "
             "src/iosTest/, or the matching test source set."),
            "https://kotlinlang.org/api/core/kotlin-test/",
            confidence="medium",
        ))

    return findings


def check_companion_leftover(entry, head_files_set):
    """M-CLEANUP-01 sanity: a RELOCATION's old path should not still exist in HEAD."""
    old = entry.get("old_file") or ""
    new = entry["file"]
    if not old.startswith(("app/src/main/", "androidApp/src/main/")):
        return []
    if old in head_files_set:
        return [make_finding(
            "M-CLEANUP-01",
            new, 1, "P0",
            (f"RELOCATION shows the old file at '{old}' was renamed to '{new}', "
             f"but a file at the old path still exists in HEAD. Two sources of "
             f"truth — Android consumers may resolve the old class."),
            ("Verify the rename. If a copy was intended, delete the old file or "
             "replace it with a typealias to the new path (with @Deprecated + "
             "ReplaceWith)."),
            "references/rules/migration-drift.md#m-cleanup-01",
        )]
    return []


def check_content_commonmain(entry, content):
    """Cheap content greps applied only when the destination is commonMain."""
    findings = []
    p = entry["file"]
    lines = content.splitlines()

    for i, line in enumerate(lines, start=1):
        if JVM_IMPORT_RE.match(line):
            findings.append(make_finding(
                "S-TYPE-01",
                p, i, "P0",
                (f"commonMain file imports a JVM/Android type: `{line.strip()}`. "
                 f"commonMain compiles for Kotlin/Native — JDK/Android types "
                 f"don't exist there, breaking the iOS build."),
                ("Move the file (or this dependency) to androidMain, or replace "
                 "with a multiplatform equivalent: java.time.* → kotlinx-datetime, "
                 "java.io.* → okio/kotlinx-io."),
                "references/rules/_base.md#s-type-01",
                ios_blocking=True,
            ))

        m = ANDROIDX_IMPORT_RE.match(line)
        if m and not is_kmp_androidx(m.group(1)):
            findings.append(make_finding(
                "S-TYPE-02",
                p, i, "P1",
                (f"commonMain file imports `{m.group(1)}` which is not on the "
                 f"verified KMP-published androidx allowlist (androidx.annotation, "
                 f"androidx.collection, androidx.paging, "
                 f"androidx.lifecycle.viewmodel)."),
                ("Verify against the Android KMP support matrix. If the artifact "
                 "is not KMP-published, move the file (or this dependency) to "
                 "androidMain."),
                "references/rules/_base.md#s-type-02",
                ios_blocking=True,
                confidence="medium",
            ))

        if not line.lstrip().startswith("import ") and JVM_QUALIFIED_USE_RE.search(line):
            findings.append(make_finding(
                "S-TYPE-01",
                p, i, "P1",
                (f"commonMain file uses a JVM type: `{line.strip()[:120]}`. "
                 f"java.util.Date/Calendar/Locale/UUID/Optional/TimeZone don't "
                 f"exist on Kotlin/Native."),
                ("Replace with multiplatform equivalents: java.util.Date → "
                 "kotlinx-datetime LocalDate/Instant; java.util.UUID → "
                 "kotlinx.uuid; java.util.Locale → app-defined locale model."),
                "references/rules/_base.md#s-type-01",
                ios_blocking=True,
            ))

        if HILT_ANNOT_RE.search(line):
            findings.append(make_finding(
                "M-CLEANUP-02",
                p, i, "P1",
                (f"commonMain file carries a Hilt/Dagger annotation: "
                 f"`{line.strip()[:120]}`. Hilt is JVM/Android-only — @Inject "
                 f"and similar don't resolve in commonMain."),
                ("Remove the Hilt annotations and re-wire via Koin "
                 "(team convention)."),
                "references/rules/migration-drift.md#m-cleanup-02",
            ))

    return findings


def build_head_files_set(repo_root: Path) -> set[str]:
    """All tracked files in HEAD, used for M-CLEANUP-01 leftover detection."""
    try:
        proc = subprocess.run(
            ["git", "-C", str(repo_root), "ls-files"],
            capture_output=True, text=True, timeout=30,
        )
        if proc.returncode != 0:
            return set()
        return set(l.strip() for l in proc.stdout.splitlines() if l.strip())
    except (OSError, subprocess.TimeoutExpired):
        return set()


def main() -> None:
    if len(sys.argv) != 2:
        print("usage: verify_relocations.py <state_dir>", file=sys.stderr)
        sys.exit(2)
    state_dir = Path(sys.argv[1])
    plan_path = state_dir / "plan.json"
    plan = json.loads(plan_path.read_text())
    ingest = json.loads((state_dir / "ingest.json").read_text())
    repo_root = Path(ingest["repo_root"])

    findings_dir = state_dir / "findings"
    cache_dir = state_dir / "cache"
    findings_dir.mkdir(parents=True, exist_ok=True)
    cache_dir.mkdir(parents=True, exist_ok=True)

    haiku_entries = [
        e for e in plan["files"]
        if e.get("swarm_tier") == "haiku-1" and e.get("status") == "pending"
    ]

    if not haiku_entries:
        print(json.dumps({"checked": 0, "with_findings": 0, "marked_done": 0}, indent=2))
        return

    head_files = build_head_files_set(repo_root)

    checked = 0
    with_findings = 0
    for entry in haiku_entries:
        per_file: list[dict] = []
        per_file.extend(check_path(entry))
        per_file.extend(check_companion_leftover(entry, head_files))

        if entry.get("surface") == "SHARED_COMMON":
            content_path = repo_root / entry["file"]
            if content_path.exists() and content_path.is_file():
                try:
                    content = content_path.read_text(encoding="utf-8", errors="replace")
                except OSError:
                    content = ""
                if content:
                    per_file.extend(check_content_commonmain(entry, content))

        out = {"findings": per_file}
        ch = entry["content_hash"]
        rh = entry["rules_hash"]
        (findings_dir / f"{ch}.json").write_text(json.dumps(out, indent=2))
        (cache_dir / f"{ch}-{rh}.json").write_text(json.dumps(out, indent=2))

        entry["status"] = "done"
        entry["findings_file"] = str(findings_dir / f"{ch}.json")

        checked += 1
        if per_file:
            with_findings += 1

    plan_path.write_text(json.dumps(plan, indent=2))

    print(json.dumps({
        "checked": checked,
        "with_findings": with_findings,
        "marked_done": checked,
    }, indent=2))


if __name__ == "__main__":
    main()

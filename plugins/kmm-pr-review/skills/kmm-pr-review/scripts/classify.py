#!/usr/bin/env python3
"""
classify.py — Phase 1 of kmm-pr-review.

Reads:
  - <state_dir>/ingest.json — repo metadata
  - <state_dir>/diff.namestatus — git diff --name-status output
  - <repo_root>/<file>      — current content (for content_hash)

Writes:
  - <state_dir>/plan.json — validated against schemas/plan.schema.json

Determines per file: surface, role, change_type, swarm_tier, rules_to_load, content_hash, rules_hash.
Detects migration (pair deletions+additions where Android-only file moves to commonMain).

Usage: classify.py <state_dir> <skill_dir>
"""

from __future__ import annotations
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# ---- Surface detection ----

SURFACE_PATTERNS = [
    (re.compile(r".*/src/commonMain/.*"), "SHARED_COMMON"),
    (re.compile(r".*/src/(android|ios|jvm|js|native|linux|mingw|macos|watchos|tvos)([A-Za-z0-9]*)Main/.*"), "SHARED_PLATFORM"),
    (re.compile(r"(androidApp|app)/src/main/.*"), "ANDROID_CONSUMER"),
    (re.compile(r"iosApp/.*"), "IOS_CONSUMER"),
    (re.compile(r".*\.swift$"), "IOS_CONSUMER"),
    (re.compile(r".*(build\.gradle(\.kts)?|settings\.gradle(\.kts)?|libs\.versions\.toml|Podfile|Package\.swift)$"), "BUILD"),
    (re.compile(r".*/src/(common|android|ios)([A-Za-z0-9]*)?(Test|UnitTest)/.*"), "TESTS"),
    (re.compile(r".*/src/test/.*"), "TESTS"),
]

def detect_surface(path: str) -> str:
    for pat, s in SURFACE_PATTERNS:
        if pat.match(path):
            return s
    if path.endswith(".swift"):
        return "IOS_CONSUMER"
    return "ANDROID_CONSUMER"  # safe default for kotlin files outside known patterns

# ---- Role detection ----

ROLE_BY_SUFFIX = [
    (re.compile(r".*UseCase\.kt$|.*Interactor\.kt$"), "usecase"),
    (re.compile(r".*ViewModel\.kt$|.*VM\.kt$"), "viewmodel"),
    (re.compile(r".*Repository(Impl)?\.kt$"), "repository"),
    (re.compile(r".*(Model|Entity|Dto)\.kt$"), "model"),
    (re.compile(r".*(Module|DiModule|KoinModule)\.kt$"), "di-module"),
    (re.compile(r".*(Screen|Composable)\.kt$"), "compose-screen"),
    (re.compile(r".*View\.swift$"), "swiftui-view"),
    (re.compile(r".*(Test|Tests|Spec)\.(kt|swift)$"), "test"),
    (re.compile(r".*(build\.gradle(\.kts)?|settings\.gradle(\.kts)?|libs\.versions\.toml|Podfile|Package\.swift)$"), "build"),
]

ROLE_FOLDER_HINTS = {
    "usecase": [r"/domain/", r"/usecase/"],
    "viewmodel": [r"/presentation/", r"/ui/"],
    "repository": [r"/data/", r"/repository/"],
    "model": [r"/domain/", r"/model/", r"/entity/"],
    "di-module": [r"/di/", r"/injection/"],
    "compose-screen": [r"/presentation/", r"/ui/", r"/screens/"],
    "swiftui-view": [r"iosApp/", r"/Views/"],
    "test": [r"/commonTest/", r"/androidUnitTest/", r"/iosTest/", r"/src/test/"],
}

CONTENT_SNIFFS = {
    "usecase": [r"operator fun invoke\("],
    "viewmodel": [r"class \w+\s*\(.*\)\s*:\s*ViewModel\(", r"androidx\.lifecycle\.ViewModel", r"@HiltViewModel"],
    "repository": [r"interface \w+\s*:\s*\w*Repository", r"class \w+\(.*\)\s*:\s*\w*Repository"],
    "model": [r"^\s*data class\b", r"^\s*sealed (class|interface)\b", r"^\s*enum class\b", r"@Serializable"],
    "di-module": [r"val\s+\w+\s*=\s*module\s*\{", r"@Module", r"@InstallIn"],
    "compose-screen": [r"@Composable", r"import\s+androidx\.compose\.runtime"],
    "swiftui-view": [r"struct\s+\w+\s*:\s*View\s*\{", r"import\s+SwiftUI"],
    "test": [r"@Test\b", r"import\s+kotlin\.test", r"import\s+org\.junit", r"import\s+XCTest"],
}

def detect_role(path: str, content: Optional[str]) -> str:
    # 1) Suffix
    for pat, role in ROLE_BY_SUFFIX:
        if pat.match(path):
            return role
    # 2) Folder hints
    folder_role_match = []
    for role, hints in ROLE_FOLDER_HINTS.items():
        for h in hints:
            if re.search(h, path):
                folder_role_match.append(role)
                break
    if len(folder_role_match) == 1:
        return folder_role_match[0]
    # 3) Content sniff
    if content:
        sniff_matches = []
        for role, sniffs in CONTENT_SNIFFS.items():
            for s in sniffs:
                if re.search(s, content, re.MULTILINE):
                    sniff_matches.append(role)
                    break
        if len(sniff_matches) == 1:
            return sniff_matches[0]
        # Disambiguate folder vs sniff if exactly one folder role is in sniff matches
        for role in folder_role_match:
            if role in sniff_matches:
                return role
    return "unknown"

# ---- change_type from git status ----

def change_type_from_status(status: str) -> str:
    if status == "A":
        return "NEW"
    if status == "M":
        return "MODIFIED"
    if status == "D":
        return "DELETED"
    if status.startswith("R"):
        try:
            similarity = int(status[1:])
        except ValueError:
            similarity = 100
        return "RELOCATION" if similarity >= 95 else "RENAMED_MODIFIED"
    if status == "T":
        return "MODIFIED"
    return "MODIFIED"

# ---- Migration detection ----

def detect_migration(diff_entries: list[dict], pr_meta: Optional[dict] = None) -> tuple[bool, list[str], list[dict]]:
    """
    Returns (migration_detected, list of new-file paths that are part of the migration, ambiguous_cases).
    
    ambiguous_cases: renames in the 80-94% similarity range moving android-only -> commonMain
    that the orchestrator should interview the user about.
    """
    migrated_paths = set()
    ambiguous = []
    # Rule 1: deletion in app/src/main paired with addition in :shared/src/commonMain with matching basename
    deletions = {Path(e["file"]).name: e["file"] for e in diff_entries if e["change_type"] == "DELETED" and e["file"].startswith(("app/src/main/", "androidApp/src/main/"))}
    for e in diff_entries:
        if e["change_type"] == "NEW" and "/src/commonMain/" in e["file"]:
            basename = Path(e["file"]).name
            if basename in deletions:
                migrated_paths.add(e["file"])
                for d in diff_entries:
                    if d["file"] == deletions[basename]:
                        migrated_paths.add(d["file"])
    # Rule 2: rename moving android-only path → commonMain
    for e in diff_entries:
        if e["change_type"] in ("RELOCATION", "RENAMED_MODIFIED") and e.get("old_file"):
            if e["old_file"].startswith(("app/src/main/", "androidApp/src/main/")) and "/src/commonMain/" in e["file"]:
                # Extract similarity from status (e.g. R85 means 85% similar)
                status = e.get("status", "R100")
                try:
                    sim = int(status[1:]) if status.startswith("R") else 100
                except ValueError:
                    sim = 100
                if sim >= 95:
                    migrated_paths.add(e["file"])
                elif sim >= 80:
                    # Ambiguous — let the orchestrator ask the user
                    ambiguous.append({
                        "file": e["file"],
                        "old_file": e["old_file"],
                        "similarity_percent": sim,
                        "reason": f"Rename {sim}% similar from android-only to commonMain (below 95% threshold)",
                    })
    # Rule 3: PR title/body keywords
    pr_keyword_match = False
    if pr_meta:
        text = (pr_meta.get("title", "") + " " + pr_meta.get("body", "")).lower()
        for kw in ["migrat", "move to shared", "move to :shared", "move to commonmain", "move to kmm", "move to kmp"]:
            if kw in text:
                pr_keyword_match = True
                break
    # When PR text says it's a migration, lower the path-heuristic bar: include the ambiguous-similarity renames automatically
    if pr_keyword_match and ambiguous:
        for a in ambiguous:
            migrated_paths.add(a["file"])
        ambiguous = []  # promoted to migration, no longer ambiguous
    
    return (len(migrated_paths) > 0, sorted(migrated_paths), ambiguous)

# ---- Swarm tier + rules-to-load ----

def determine_swarm_tier(change_type: str, surface: str, is_migration_file: bool) -> str:
    if is_migration_file:
        return "sonnet-3-migration"
    if change_type == "RELOCATION":
        return "haiku-1"
    if surface in ("TESTS", "BUILD"):
        return "sonnet-1"
    if change_type == "NEW" and surface == "SHARED_COMMON":
        return "sonnet-3-new"
    return "sonnet-2"

def determine_rules_to_load(change_type: str, surface: str, role: str, is_migration_file: bool) -> list[str]:
    rules = ["_base.md", "hygiene.md"]
    if surface in ("SHARED_COMMON", "SHARED_PLATFORM") or is_migration_file:
        rules.append("ios-readiness.md")
    if role != "unknown":
        rules.append(f"{role}.md")
    if change_type == "NEW" and surface == "SHARED_COMMON":
        rules.append("new-commonmain-file.md")
    if change_type == "NEW":
        rules.append("new-file-clean-code.md")
    if is_migration_file:
        rules.append("migration-drift.md")
    # Dedupe preserving order
    seen = set()
    out = []
    for r in rules:
        if r not in seen:
            seen.add(r)
            out.append(r)
    return out

# ---- Hashing ----

def sha256_text(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8", errors="replace")).hexdigest()[:16]

def rules_hash(skill_dir: Path, rule_files: list[str]) -> str:
    h = hashlib.sha256()
    for r in rule_files:
        p = skill_dir / "references" / "rules" / r
        if p.exists():
            h.update(p.read_bytes())
        h.update(b"\n---\n")
    return h.hexdigest()[:16]

# ---- Diff parser ----

def parse_diff_namestatus(diff_file: Path) -> list[dict]:
    entries = []
    with diff_file.open() as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            status = parts[0]
            if status.startswith("R") and len(parts) >= 3:
                entries.append({"status": status, "file": parts[2], "old_file": parts[1]})
            elif status.startswith("C") and len(parts) >= 3:
                entries.append({"status": "A", "file": parts[2], "old_file": parts[1]})
            else:
                entries.append({"status": status, "file": parts[1]})
    # Project to change_type
    for e in entries:
        e["change_type"] = change_type_from_status(e["status"])
    return entries

# ---- Main ----

def find_sibling_baselines(repo_root: Path, base_ref: str, file_path: str, role: str, package_dir: str, max_n: int = 5) -> list[str]:
    """
    Find up to max_n sibling files in master that share the same package directory and the same role suffix.
    Returns a list of repo-relative paths. Falls back to package-only siblings if role match is empty.
    """
    import subprocess
    if not package_dir:
        return []
    try:
        proc = subprocess.run(
            ["git", "-C", str(repo_root), "ls-tree", "-r", "--name-only", base_ref, package_dir],
            capture_output=True, text=True, timeout=10,
        )
        if proc.returncode != 0:
            return []
        all_in_pkg = [p for p in proc.stdout.splitlines() if p and p != file_path]
    except (OSError, subprocess.TimeoutExpired):
        return []
    # Prefer same-role siblings
    role_suffixes = {
        "usecase": ("UseCase.kt", "Interactor.kt"),
        "viewmodel": ("ViewModel.kt", "VM.kt"),
        "repository": ("Repository.kt", "RepositoryImpl.kt"),
        "model": ("Model.kt", "Entity.kt", "Dto.kt"),
        "di-module": ("Module.kt",),
        "compose-screen": ("Screen.kt", "Composable.kt"),
    }
    suffixes = role_suffixes.get(role)
    same_role = [p for p in all_in_pkg if suffixes and any(p.endswith(s) for s in suffixes)] if suffixes else []
    # Rank by basename similarity to target (simple string-distance proxy: shared prefix length)
    target_base = Path(file_path).stem
    def score(p: str) -> int:
        pb = Path(p).stem
        common = 0
        for a, b in zip(pb, target_base):
            if a == b:
                common += 1
            else:
                break
        return -common  # ascending sort = best first
    ranked = sorted(same_role or all_in_pkg, key=score)
    return ranked[:max_n]


def main():
    if len(sys.argv) != 3:
        print("usage: classify.py <state_dir> <skill_dir>", file=sys.stderr)
        sys.exit(2)
    state_dir = Path(sys.argv[1])
    skill_dir = Path(sys.argv[2])

    ingest = json.loads((state_dir / "ingest.json").read_text())
    repo_root = Path(ingest["repo_root"])
    diff_file = state_dir / "diff.namestatus"
    base_ref = ingest["base_ref"]
    
    # Load PR meta if present
    pr_meta = None
    pr_meta_path = ingest.get("pr_meta_file")
    if pr_meta_path and Path(pr_meta_path).exists():
        try:
            pr_meta = json.loads(Path(pr_meta_path).read_text())
            if not pr_meta:  # empty {} → treat as none
                pr_meta = None
        except (json.JSONDecodeError, OSError):
            pr_meta = None

    diff_entries = parse_diff_namestatus(diff_file)

    migration_detected, migrated_paths, ambiguous_cases = detect_migration(diff_entries, pr_meta)
    migrated_set = set(migrated_paths)

    # Write ambiguous cases for the orchestrator to interview the user about
    (state_dir / "ambiguous_migrations.json").write_text(json.dumps(ambiguous_cases, indent=2))

    files = []
    for e in diff_entries:
        path = e["file"]
        change_type = e["change_type"]
        if change_type == "DELETED":
            continue
        surface = detect_surface(path)
        content_path = repo_root / path
        content = None
        content_hash = "missing"
        if content_path.exists() and content_path.is_file():
            try:
                content = content_path.read_text(encoding="utf-8", errors="replace")
                content_hash = sha256_text(content)
            except OSError:
                pass
        role = detect_role(path, content)
        is_migration_file = path in migrated_set
        swarm_tier = determine_swarm_tier(change_type, surface, is_migration_file)
        rules_to_load = determine_rules_to_load(change_type, surface, role, is_migration_file)
        rh = rules_hash(skill_dir, rules_to_load)
        entry = {
            "file": path,
            "change_type": change_type,
            "surface": surface,
            "role": role,
            "swarm_tier": swarm_tier,
            "rules_to_load": rules_to_load,
            "content_hash": content_hash,
            "rules_hash": rh,
            "status": "pending",
            "is_migration_file": is_migration_file,
        }
        if e.get("old_file"):
            entry["old_file"] = e["old_file"]
        # For sonnet-3-new tier (NEW in commonMain): attach sibling baselines (capped at 5)
        if swarm_tier == "sonnet-3-new":
            package_dir = str(Path(path).parent)
            entry["sibling_baselines"] = find_sibling_baselines(repo_root, base_ref, path, role, package_dir, max_n=5)
        files.append(entry)

    plan = {
        "repo_hash": ingest["repo_hash"],
        "branch": ingest["branch"],
        "base_ref": ingest["base_ref"],
        "head_sha": ingest["head_sha"],
        "created_at": datetime.now(timezone.utc).isoformat(),
        "migration_detected": migration_detected,
        "files": files,
    }
    (state_dir / "plan.json").write_text(json.dumps(plan, indent=2))
    print(json.dumps({
        "plan_file": str(state_dir / "plan.json"),
        "files_planned": len(files),
        "migration_detected": migration_detected,
        "ambiguous_migrations": len(ambiguous_cases),
        "tiers": {t: sum(1 for f in files if f["swarm_tier"] == t) for t in {f["swarm_tier"] for f in files}},
    }, indent=2))

if __name__ == "__main__":
    main()

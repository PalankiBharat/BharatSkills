#!/usr/bin/env python3
"""PreToolUse guard for kmm-pipeline migrations.

Armed only while `.kmm/migrations/ACTIVE` exists (project dir, or any
ancestor of the edited file). Denies tool calls that break the
mechanically-checkable Migration Law rules and this repo's mined
mistake taxonomy. Deny is reported via permissionDecision JSON;
any internal failure falls open (exit 0, no output) so the guard can
never wedge a session.
"""
import json
import os
import re
import sys
from collections import Counter

BANNED_PLATFORM_TOKENS = {"android", "ios", "apple", "darwin"}
CODE_SUFFIXES = (".kt", ".kts", ".swift")
BUILD_SUFFIXES = (".gradle", ".gradle.kts", ".toml")

COMMENT_LINE = re.compile(r"^\s*(//|/\*|\*/|\*(\s|$))")
LOG_CALL = re.compile(r"\b(Log|Timber|Napier|NSLog|os_log)[.(]")
DECL_NAME = re.compile(
    r"\b(?:class|object|interface|fun|val|var|typealias|struct|enum|protocol|func|actor|let)\s+`?([A-Za-z_]\w*)"
)
CATCH_BROAD = re.compile(r"catch\s*\(\s*\w+\s*:\s*(?:Exception|Throwable)\b")
RAW_VIEWMODEL_LAUNCH = re.compile(r"viewModelScope\.launch\s*[({]")
WALL_CLOCK = re.compile(r"Clock\.System\.now\s*\(")
IGNORE_BLOCK = re.compile(r"@Ignore\b\s*(\([^()]*\))?", re.S)
TRACKING_REF = re.compile(r"#\d+|https?://")
UNPORTABLE_TEST_NAME = re.compile(r"fun\s+`[^`]*[,()./\\\[\]<>][^`]*`")
PRERELEASE_VERSION = re.compile(
    r"[\"'][^\"']*\d+\.\d+[^\"']*(alpha|beta|rc[.\-0-9]|snapshot|-local)[^\"']*[\"']", re.I
)
RAW_COORDINATE = re.compile(r"[\"'][A-Za-z_][\w.\-]*:[\w.\-]+:[\w.\-+]*\d[\w.\-+]*[\"']")
IDENTIFIER_TOKENS = re.compile(r"[A-Z]+(?![a-z])|[A-Z][a-z0-9]*|[a-z0-9]+")


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "kmm-pipeline guard: " + reason,
        }
    }))
    sys.exit(0)


def has_active_marker(directory):
    return os.path.isfile(os.path.join(directory, ".kmm", "migrations", "ACTIVE"))


def nearest_active_root(start, max_levels=12):
    current = os.path.abspath(start)
    for _ in range(max_levels):
        if has_active_marker(current):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return None
        current = parent
    return None


def repo_root_of(path, max_levels=12):
    current = os.path.abspath(path)
    for _ in range(max_levels):
        if os.path.exists(os.path.join(current, "settings.gradle")) or os.path.isdir(
            os.path.join(current, ".git")
        ):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return None
        current = parent
    return None


def name_has_banned_platform_token(name):
    tokens = IDENTIFIER_TOKENS.findall(name)
    return any(token.lower() in BANNED_PLATFORM_TOKENS for token in tokens)


def line_delta(old_text, new_text):
    old_counts = Counter(old_text.splitlines())
    new_counts = Counter(new_text.splitlines())
    added, removed = [], []
    for line in set(old_counts) | set(new_counts):
        diff = new_counts[line] - old_counts[line]
        if diff > 0:
            added.extend([line] * diff)
        elif diff < 0:
            removed.extend([line] * -diff)
    return added, removed


def count_matching(lines, pattern):
    return sum(1 for line in lines if pattern.search(line))


def edit_pairs(tool, tool_input):
    if tool == "Write":
        path = tool_input.get("file_path", "")
        old = ""
        if os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as handle:
                    old = handle.read()
            except OSError:
                old = ""
        return [(old, tool_input.get("content", ""))]
    if tool == "Edit":
        return [(tool_input.get("old_string", ""), tool_input.get("new_string", ""))]
    return [
        (edit.get("old_string", ""), edit.get("new_string", ""))
        for edit in tool_input.get("edits", [])
    ]


def app_source_has_basename(repo_root, basename):
    app_src = os.path.join(repo_root, "app", "src")
    for directory, _, files in os.walk(app_src):
        if basename in files:
            return True
    return False


def guard_file_tool(tool, tool_input, project_dir):
    path = tool_input.get("file_path", "")
    if not path:
        return
    normalized = os.path.abspath(path).replace("\\", "/")
    if not (has_active_marker(project_dir) or nearest_active_root(os.path.dirname(normalized))):
        return

    if normalized.endswith(".broken"):
        deny("Rule 9: tests are never silenced by renaming to .broken — fix or quarantine via @Ignore with a tracking issue.")
    if "objectbox-models/" in normalized and normalized.endswith(".json"):
        deny("M2: the ObjectBox schema is frozen during a migration — a type change under an unchanged uid has wiped user data here before. Route through a G3 gate.")

    in_code_scope = (
        any(segment in normalized for segment in ("/app/src/", "/shared/src/"))
        or "/Punch/" in normalized
    ) and normalized.endswith(CODE_SUFFIXES)
    is_build_file = normalized.endswith(BUILD_SUFFIXES)
    if not in_code_scope and not is_build_file:
        return

    pairs = edit_pairs(tool, tool_input)
    added_all, comment_delta, log_delta = [], 0, 0
    for old, new in pairs:
        added, removed = line_delta(old, new)
        added_all.extend(added)
        comment_delta += count_matching(added, COMMENT_LINE) - count_matching(removed, COMMENT_LINE)
        log_delta += count_matching(removed, LOG_CALL) - count_matching(added, LOG_CALL)
    added_text = "\n".join(added_all)

    if is_build_file:
        if PRERELEASE_VERSION.search(added_text):
            deny("M10: no alpha/beta/rc/SNAPSHOT/-local versions inside a migration — pin a stable release or take it to a gate.")
        if not normalized.endswith(".toml"):
            for line in added_all:
                match = RAW_COORDINATE.search(line)
                if match and "/" not in match.group(0):
                    deny("M10: dependency coordinates go through the version catalog (libs.versions.toml), not raw group:artifact:version literals.")
        if not in_code_scope:
            return

    is_new_file = tool == "Write" and not os.path.isfile(normalized)
    basename = os.path.basename(normalized)
    if is_new_file and name_has_banned_platform_token(os.path.splitext(basename)[0]):
        deny("Rule 4: no new file names with android/ios/apple/darwin affixes — platform variants keep the SAME name in different source sets.")
    if is_new_file and "/shared/src/" in normalized and normalized.endswith(".kt"):
        repo_root = repo_root_of(os.path.dirname(normalized))
        if repo_root and app_source_has_basename(repo_root, basename):
            deny("Rule 1: " + basename + " exists under app/src — relocations are `git mv`, never a fresh Write (copy severs history and invites drift).")

    for line in added_all:
        declaration_scan = re.sub(r"\"[^\"]*\"", "\"\"", line)
        for declaration in DECL_NAME.finditer(declaration_scan):
            if name_has_banned_platform_token(declaration.group(1)):
                deny("Rule 4: new declaration '" + declaration.group(1) + "' carries a platform affix — express the platform split via source sets, not names.")
    for annotation in IGNORE_BLOCK.finditer(added_text):
        if not TRACKING_REF.search(annotation.group(1) or ""):
            deny("Rule 9: @Ignore requires a tracking reference in its message, e.g. @Ignore(\"flaky — #123\").")

    if comment_delta > 0:
        deny("Rule 5: no comment additions during a migration — moved code keeps its comments byte-for-byte, new code self-explains.")
    if log_delta > 0:
        deny("M13: existing log calls are never deleted in a migration diff — they may belong to live investigations.")
    if "/shared/src/" in normalized and CATCH_BROAD.search(added_text) and "CancellationException" not in added_text:
        deny("M3: a broad catch in shared code must rethrow CancellationException first — swallowing it has shipped 5 identical review blockers here.")
    if "/shared/src/commonMain/" in normalized and WALL_CLOCK.search(added_text):
        deny("M14: no Clock.System.now() in commonMain production code — inject a Clock so baselines can pin time.")
    if (
        "/shared/src/commonMain/" in normalized
        and RAW_VIEWMODEL_LAUNCH.search(added_text)
        and "safeLaunch" not in added_text
    ):
        deny("kn-fatal-coroutine: raw viewModelScope.launch in commonMain — an escaping exception is fatal on Kotlin/Native (10 of 12 blockers in the #439 review). Use the KMMViewModel safeLaunch primitive.")
    if "/shared/src/commonTest/" in normalized and UNPORTABLE_TEST_NAME.search(added_text):
        deny("M4: backtick test names with ,()./\\[]<> break Kotlin/Native test compilation — use plain words.")


def bash_segments(command):
    return re.split(r"[;&|]+", command)


def guard_bash(tool_input, project_dir):
    if not has_active_marker(project_dir):
        return
    command = tool_input.get("command", "")
    if "--rerun-tasks" in command:
        deny("repo gotcha: --rerun-tasks fails this build (KMP strict checkers); run incrementally and verify via JUnit XML.")
    for segment in bash_segments(command):
        if re.search(r"(^|\s)cp\s", segment) and "app/src" in segment and "shared/" in segment:
            deny("Rule 1: copying from app/src into shared/ is forbidden — use `git mv` so the diff stays a rename.")
        without_git_mv = re.sub(r"git(\s+-C\s+\S+)?\s+mv", "", segment)
        if re.search(r"(^|\s)mv\s", without_git_mv) and "app/src" in segment and "shared/" in segment:
            deny("Rule 1: plain mv loses git history — relocations use `git mv`.")
        for match in re.finditer(r"git(?:\s+-C\s+\S+)?\s+mv\s+([^;&|]+)", segment):
            arguments = [argument.strip("\"'") for argument in match.group(1).split()]
            flags_stripped = [argument for argument in arguments if not argument.startswith("-")]
            if not flags_stripped:
                continue
            target = flags_stripped[-1]
            target_name = os.path.splitext(os.path.basename(target))[0]
            if target.endswith(".broken"):
                deny("Rule 9: renaming a test to .broken silences it — fix or quarantine via @Ignore with a tracking issue.")
            if name_has_banned_platform_token(target_name):
                deny("Rule 4: move target '" + os.path.basename(target) + "' carries a platform affix — keep the original name; source sets express the platform.")
        if (
            re.search(r"(^|\s)rm\s+(-\w*r|\-\-recursive)", segment)
            and ".kmm/migrations" in segment
            and "_archive" not in segment
        ):
            deny("state protection: migration state is archived (mv to _archive), never rm -r'd — resume depends on it.")


def main():
    payload = json.load(sys.stdin)
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR") or payload.get("cwd") or os.getcwd()
    if tool in ("Write", "Edit", "MultiEdit"):
        guard_file_tool(tool, tool_input, project_dir)
    elif tool == "Bash":
        guard_bash(tool_input, project_dir)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)

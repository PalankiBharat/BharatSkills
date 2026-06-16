#!/usr/bin/env bash
set -u
GUARD="$(cd "$(dirname "$0")/.." && pwd)/scripts/migration_guard.py"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/.kmm/migrations" \
  "$ROOT/app/src/main/java/com/x" \
  "$ROOT/shared/src/commonMain/kotlin/com/x" \
  "$ROOT/shared/src/commonTest/kotlin/com/x" \
  "$ROOT/Punch/Punch/Screens" \
  "$ROOT/app/objectbox-models" \
  "$ROOT/gradle"
touch "$ROOT/settings.gradle"
printf 'demo-feature\nstate=%s/.kmm/migrations/demo-feature\n' "$ROOT" > "$ROOT/.kmm/migrations/ACTIVE"
printf 'package com.x\nclass LoginPresenter {\n    fun load() { Napier.e("boom") }\n}\n' > "$ROOT/app/src/main/java/com/x/LoginPresenter.kt"
printf '{}\n' > "$ROOT/app/objectbox-models/default.json"
printf 'plugins {}\n' > "$ROOT/app/build.gradle"
printf '[versions]\nfoo = "1.0.0"\n' > "$ROOT/gradle/libs.versions.toml"

export CLAUDE_PROJECT_DIR="$ROOT"
pass=0
fail=0

run_case() {
  local name="$1" expect="$2" payload="$3" out decision
  out=$(printf '%s' "$payload" | python3 "$GUARD" 2>&1)
  if printf '%s' "$out" | grep -q '"permissionDecision": "deny"'; then
    decision="deny"
  else
    decision="allow"
  fi
  if [ "$decision" = "$expect" ]; then
    pass=$((pass + 1))
    echo "PASS  $name"
  else
    fail=$((fail + 1))
    echo "FAIL  $name (expected $expect, got $decision)"
    [ -n "$out" ] && echo "      output: $out"
  fi
}

write_payload() {
  python3 - "$1" "$2" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Write", "tool_input": {"file_path": sys.argv[1], "content": sys.argv[2]}}))
PY
}

edit_payload() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Edit", "tool_input": {"file_path": sys.argv[1], "old_string": sys.argv[2], "new_string": sys.argv[3]}}))
PY
}

bash_payload() {
  python3 - "$1" <<'PY'
import json, sys
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": sys.argv[1]}}))
PY
}

multiedit_payload() {
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
print(json.dumps({"tool_name": "MultiEdit", "tool_input": {"file_path": sys.argv[1], "edits": [{"old_string": sys.argv[2], "new_string": sys.argv[3]}]}}))
PY
}

run_case "D1 copy-instead-of-move into shared" deny \
  "$(write_payload "$ROOT/shared/src/commonMain/kotlin/com/x/LoginPresenter.kt" 'package com.x')"
run_case "D2 banned affix in new filename" deny \
  "$(write_payload "$ROOT/shared/src/commonMain/kotlin/com/x/AndroidThing.kt" 'package com.x')"
run_case "D3 banned affix in new declaration" deny \
  "$(write_payload "$ROOT/shared/src/commonMain/kotlin/com/x/Bridge.kt" 'package com.x
class IosBridge')"
run_case "D4 comment addition" deny \
  "$(edit_payload "$ROOT/app/src/main/java/com/x/LoginPresenter.kt" 'fun load()' '// relocated for KMM
fun load()')"
run_case "D5 .broken write" deny \
  "$(write_payload "$ROOT/shared/src/commonTest/kotlin/com/x/FooTest.kt.broken" 'x')"
run_case "D6 @Ignore without tracking ref" deny \
  "$(edit_payload "$ROOT/shared/src/commonTest/kotlin/com/x/T.kt" 'fun a()' '@Ignore("flaky")
fun a()')"
run_case "D7 broad catch without CancellationException" deny \
  "$(edit_payload "$ROOT/shared/src/commonMain/kotlin/com/x/R.kt" 'val x = 1' 'val x = 1
try { load() } catch (e: Exception) { emit(Empty) }')"
run_case "D8 wall clock in commonMain" deny \
  "$(edit_payload "$ROOT/shared/src/commonMain/kotlin/com/x/U.kt" 'val a = 1' 'val now = Clock.System.now()')"
run_case "D9 log deletion" deny \
  "$(edit_payload "$ROOT/app/src/main/java/com/x/LoginPresenter.kt" 'fun load() { Napier.e("boom") }' 'fun load() { }')"
run_case "D10 objectbox schema edit" deny \
  "$(edit_payload "$ROOT/app/objectbox-models/default.json" '{}' '{"a":1}')"
run_case "D11 unportable backtick test name" deny \
  "$(edit_payload "$ROOT/shared/src/commonTest/kotlin/com/x/T.kt" 'class T' 'class T {
fun `loads, then fails`() {}
}')"
run_case "D12 prerelease version in build file" deny \
  "$(edit_payload "$ROOT/app/build.gradle" 'plugins {}' 'plugins {}
implementation("com.squareup:thing:1.2.3-alpha2")')"
run_case "D13 raw coordinate outside catalog" deny \
  "$(edit_payload "$ROOT/app/build.gradle" 'plugins {}' 'plugins {}
implementation("com.foo:bar:1.2.3")')"
run_case "D14 --rerun-tasks" deny \
  "$(bash_payload "./gradlew :shared:compileKotlinIosArm64 --rerun-tasks")"
run_case "D15 cp app to shared" deny \
  "$(bash_payload "cp app/src/main/java/com/x/LoginPresenter.kt shared/src/commonMain/kotlin/com/x/")"
run_case "D16 plain mv app to shared" deny \
  "$(bash_payload "mv app/src/main/java/com/x/LoginPresenter.kt shared/src/commonMain/kotlin/com/x/")"
run_case "D17 git mv to banned name" deny \
  "$(bash_payload "git mv shared/src/commonMain/kotlin/com/x/Colors.kt shared/src/commonMain/kotlin/com/x/AndroidColors.kt")"
run_case "D18 rm -r on migration state" deny \
  "$(bash_payload "rm -rf .kmm/migrations/demo-feature")"

run_case "D19 raw viewModelScope.launch in commonMain" deny \
  "$(edit_payload "$ROOT/shared/src/commonMain/kotlin/com/x/V.kt" 'class V' 'class V {
fun load() { viewModelScope.launch { fetch() } }
}')"
run_case "D20 git mv test to .broken" deny \
  "$(bash_payload "git mv shared/src/commonTest/kotlin/com/x/T.kt shared/src/commonTest/kotlin/com/x/T.kt.broken")"
run_case "D21 comment addition via MultiEdit" deny \
  "$(multiedit_payload "$ROOT/app/src/main/java/com/x/LoginPresenter.kt" 'fun load()' '// migrated
fun load()')"

run_case "A1 write outside guarded scope" allow \
  "$(write_payload "$ROOT/.kmm/migrations/demo-feature/state.json" '{"phase":0}')"
run_case "A2 clean new shared file" allow \
  "$(write_payload "$ROOT/shared/src/commonMain/kotlin/com/x/SessionClock.kt" 'package com.x
class SessionClock')"
run_case "A3 comment-neutral edit" allow \
  "$(edit_payload "$ROOT/app/src/main/java/com/x/LoginPresenter.kt" '// keep
fun load()' '// keep
fun load(force: Boolean)')"
run_case "A4 git mv same basename" allow \
  "$(bash_payload "git mv app/src/main/java/com/x/LoginPresenter.kt shared/src/commonMain/kotlin/com/x/LoginPresenter.kt")"
run_case "A5 stable version in catalog" allow \
  "$(edit_payload "$ROOT/gradle/libs.versions.toml" 'foo = "1.0.0"' 'foo = "1.2.0"')"
run_case "A6 clean swift addition" allow \
  "$(edit_payload "$ROOT/Punch/Punch/Screens/Login.swift" 'var body: some View' 'var body: some View
func bindState()')"
run_case "A7 rm ACTIVE marker (close-out)" allow \
  "$(bash_payload "rm .kmm/migrations/ACTIVE")"
run_case "A11 @Ignore with tracking ref" allow \
  "$(edit_payload "$ROOT/shared/src/commonTest/kotlin/com/x/T.kt" 'fun a()' '@Ignore("flaky — #123")
fun a()')"

run_case "A10 safeLaunch in commonMain" allow \
  "$(edit_payload "$ROOT/shared/src/commonMain/kotlin/com/x/V.kt" 'class V' 'class V {
fun load() { safeLaunch(onError = ::show) { fetch() } }
}')"

run_case "A8 catch with rethrow" allow \
  "$(edit_payload "$ROOT/shared/src/commonMain/kotlin/com/x/R.kt" 'val x = 1' 'val x = 1
try { load() } catch (e: CancellationException) { throw e } catch (e: Exception) { log(e) }')"

rm "$ROOT/.kmm/migrations/ACTIVE"
run_case "A9 unarmed: comment addition allowed" allow \
  "$(edit_payload "$ROOT/app/src/main/java/com/x/LoginPresenter.kt" 'fun load()' '// note
fun load()')"

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]

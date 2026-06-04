#!/usr/bin/env bash
# Tiny bash assertions for harness tests. Source via: . "$(dirname "$0")/_assert.sh"
# Each test script exits 0 on pass, non-0 on first failure.
set -eu
_FAIL() { printf 'FAIL [%s:%s]: %s\n' "${BASH_SOURCE[1]##*/}" "${BASH_LINENO[0]}" "$1" >&2; exit 1; }
assert_eq()       { [ "$1" = "$2" ] || _FAIL "expected '$2' got '$1'"; }
assert_ne()       { [ "$1" != "$2" ] || _FAIL "expected not '$2'"; }
assert_contains() { case "$1" in *"$2"*) ;; *) _FAIL "'$1' does not contain '$2'";; esac; }
assert_file()     { [ -f "$1" ] || _FAIL "missing file: $1"; }
assert_dir()      { [ -d "$1" ] || _FAIL "missing dir: $1"; }

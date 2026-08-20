#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; exit 1; }
pass() { printf '\033[1;32mok\033[0m   %s\n' "$1"; }
skip() { printf '\033[1;33mskip\033[0m %s\n' "$1"; }

command -v jq >/dev/null || fail "jq not found"
command -v node >/dev/null || fail "node not found"
command -v omarchy >/dev/null || fail "omarchy not found"

bash -n "$ROOT/control.sh"
pass "control script parses"

grep -F 'omarchy-apple-music/chromium' "$ROOT/control.sh" >/dev/null
grep -F 'relative = false' "$ROOT/control.sh" >/dev/null
pass "launcher uses writable profile and absolute Hyprland geometry"

omarchy plugin validate "$ROOT" >/dev/null
pass "manifest validates"

node --test "$ROOT/tests/model.test.js"
pass "model tests pass"

"$ROOT/tests/control.test.sh"
pass "window lifecycle commands pass"

if state=$("$ROOT/control.sh" state 2>/dev/null); then
  jq -e '.client == null or (.client | type == "object")' <<<"$state" >/dev/null
  jq -e '.monitors | type == "array"' <<<"$state" >/dev/null
  jq -e '.open | type == "boolean"' <<<"$state" >/dev/null
  pass "live Hyprland state is readable"
else
  skip "no live Hyprland session"
fi

if status=$(omarchy-shell apple-music status 2>/dev/null); then
  jq -e '.rulesInstalled | type == "boolean"' <<<"$status" >/dev/null
  jq -e '.opened | type == "boolean"' <<<"$status" >/dev/null
  pass "installed service responds"
else
  skip "plugin is not enabled in the running shell"
fi

printf '\n\033[1;32mall good\033[0m\n'

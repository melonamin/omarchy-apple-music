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

grep -F 'PROFILE_DIR="$DATA_DIR/chromium"' "$ROOT/control.sh" >/dev/null
grep -F -- '--load-extension=' "$ROOT/control.sh" >/dev/null
grep -F 'relative = false' "$ROOT/control.sh" >/dev/null
grep -F 'omarchy-image-selector' "$ROOT/Service.qml" >/dev/null
grep -F 'wait-theme' "$ROOT/Service.qml" >/dev/null
pass "launcher uses a writable profile, bundled extension, and absolute Hyprland geometry"

jq -e '
  .manifest_version == 3
  and .content_scripts[0].matches == ["https://music.apple.com/*"]
  and .content_scripts[0].run_at == "document_start"
  and (.permissions == null)
  and (.host_permissions == null)
' "$ROOT/extension/manifest.json" >/dev/null
grep -F 'window.addEventListener("focus", refreshAfterWake' "$ROOT/extension/content.js" >/dev/null
grep -F 'document.addEventListener("visibilitychange"' "$ROOT/extension/content.js" >/dev/null
grep -F 'const pollInterval = 100' "$ROOT/extension/content.js" >/dev/null
pass "browser extension is scoped to Apple Music without extra permissions"

omarchy plugin validate "$ROOT" >/dev/null
pass "manifest validates"

node --test "$ROOT/tests/model.test.js"
pass "model tests pass"

node --test "$ROOT/tests/extension.test.js"
pass "theme model tests pass"

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
  jq -e '.themeReady | type == "boolean"' <<<"$status" >/dev/null
  pass "installed service responds"
else
  skip "plugin is not enabled in the running shell"
fi

printf '\n\033[1;32mall good\033[0m\n'

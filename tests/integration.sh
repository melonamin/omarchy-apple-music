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
  and .version == "0.1.2"
  and .permissions == ["storage"]
  and (.background == null)
  and .content_scripts[0].matches == ["https://music.apple.com/*"]
  and .content_scripts[0].run_at == "document_start"
  and .content_scripts[0].world == "MAIN"
  and .content_scripts[0].js == ["player-model.js", "player-bridge.js"]
  and .content_scripts[1].matches == ["https://music.apple.com/*"]
  and .content_scripts[1].run_at == "document_start"
  and (.host_permissions == null)
' "$ROOT/extension/manifest.json" >/dev/null
grep -F 'window.addEventListener("focus", refreshAfterWake' "$ROOT/extension/content.js" >/dev/null
grep -F 'document.addEventListener("visibilitychange"' "$ROOT/extension/content.js" >/dev/null
grep -F 'const pollInterval = 100' "$ROOT/extension/content.js" >/dev/null
grep -F 'function suppressStatusUrls(root)' "$ROOT/extension/content.js" >/dev/null
grep -F 'document.addEventListener("keydown", activateFromKeyboard' "$ROOT/extension/content.js" >/dev/null
grep -F '[data-testid="navigation"] .navigation__native-cta' "$ROOT/extension/content.css" >/dev/null
grep -F 'border-inline-end: 1px solid var(--omarchy-divider) !important' "$ROOT/extension/content.css" >/dev/null
grep -F 'chrome.storage.local.set({ panelView })' "$ROOT/extension/content.js" >/dev/null
grep -F 'DEFAULT_ZOOM_LEVEL="-0.5778829311823857"' "$ROOT/control.sh" >/dev/null
grep -F '.partition.default_zoom_level.x = $level' "$ROOT/control.sh" >/dev/null
grep -F 'document.addEventListener(commandEvent, command)' "$ROOT/extension/player-bridge.js" >/dev/null
grep -F 'instance.changeToMediaAtIndex(Number(request.value))' "$ROOT/extension/player-bridge.js" >/dev/null
grep -F ':root[data-omarchy-apple-music-view="queue"]' "$ROOT/extension/content.css" >/dev/null
grep -F 'document.querySelector('"'"'[data-testid="navigation"] [data-testid="search"]'"'"')' "$ROOT/extension/content.js" >/dev/null
grep -F 'window.location.assign(`${window.location.origin}${storefront}/search`)' "$ROOT/extension/content.js" >/dev/null
grep -F '[data-testid="navigation"] [data-testid="logo"]' "$ROOT/extension/content.css" >/dev/null
grep -F '[data-testid="navigation-item"]:has([data-testid="search"])' "$ROOT/extension/content.css" >/dev/null
grep -F '[data-testid="navigation-content"]' "$ROOT/extension/content.css" >/dev/null
grep -F '.omarchy-play-button [data-icon="play"] svg' "$ROOT/extension/content.css" >/dev/null
grep -F '[data-testid="content-scope-bar-controls"]' "$ROOT/extension/content.css" >/dev/null
grep -F 'footer[data-testid="footer"]' "$ROOT/extension/content.css" >/dev/null
grep -F '*::-webkit-scrollbar' "$ROOT/extension/content.css" >/dev/null
grep -F -- '--omarchy-sidebar-width: 260px' "$ROOT/extension/content.css" >/dev/null
grep -F -- '--omarchy-plugin-rail-height: 64.4444px' "$ROOT/extension/content.css" >/dev/null
grep -F 'grid-template-columns: minmax(360px, 42%) minmax(300px, 1fr)' "$ROOT/extension/content.css" >/dev/null
grep -F '[data-testid="header-component-model"]' "$ROOT/extension/content.css" >/dev/null
grep -F '.header:has([data-testid="header-title"])' "$ROOT/extension/content.css" >/dev/null
grep -F 'omarchy-shared-view-switcher' "$ROOT/extension/content.js" >/dev/null
grep -F 'omarchy-brand-mark' "$ROOT/extension/content.js" >/dev/null
grep -F 'omarchy-search-slot' "$ROOT/extension/content.js" >/dev/null
grep -F 'transform: scale(1.1111)' "$ROOT/extension/content.css" >/dev/null
pass "browser extension is scoped to Apple Music with local-only view persistence"

omarchy plugin validate "$ROOT" >/dev/null
pass "manifest validates"

node --test "$ROOT/tests/model.test.js"
pass "model tests pass"

node --test "$ROOT/tests/extension.test.js"
pass "theme model tests pass"

node --test "$ROOT/tests/player-model.test.js"
pass "player model tests pass"

node --test "$ROOT/tests/player-bridge.test.js"
pass "player bridge tests pass"

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

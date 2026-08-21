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
bash -n "$ROOT/spectrum.sh"
pass "control script parses"

node - "$ROOT/BarWidget.qml" <<'NODE'
const assert = require("node:assert")
const fs = require("node:fs")

const source = fs.readFileSync(process.argv[2], "utf8")
const label = source.match(/Text\s*\{\s*id:\s*labelText\b[\s\S]*?\n\s*\}/)
assert.ok(label, "bar metadata label is missing")
assert.match(label[0], /textFormat:\s*Text\.PlainText\b/,
  "bar metadata must render as plain text")

const tooltip = source.match(/onEntered:[\s\S]*?onExited:/)
assert.ok(tooltip, "bar tooltip handler is missing")
assert.doesNotMatch(tooltip[0], /statusText|root\.(?:title|artist)/,
  "untrusted MPRIS metadata must not reach the shared tooltip renderer")
NODE
pass "MPRIS metadata is confined to a plain-text renderer"

plugin_version=$(jq -r '.version // empty' "$ROOT/manifest.json")
extension_version=$(jq -r '.version // empty' "$ROOT/extension/chromium-manifest.json")
[[ -n $plugin_version ]] || fail "plugin manifest has no version"
[[ $plugin_version == "$extension_version" ]] ||
  fail "manifest versions differ: plugin $plugin_version, extension $extension_version"
pass "both manifests declare version $plugin_version"

jq -e '
  .manifest_version == 3
  and .permissions == ["storage"]
  and (.background == null)
  and .content_scripts[0].matches == ["https://music.apple.com/*"]
  and .content_scripts[0].run_at == "document_start"
  and .content_scripts[0].world == "MAIN"
  and .content_scripts[0].js == ["player-model.js", "player-bridge.js"]
  and .content_scripts[1].matches == ["https://music.apple.com/*"]
  and .content_scripts[1].run_at == "document_start"
  and .web_accessible_resources[0].resources == ["theme.json", "spectrum.json"]
  and .web_accessible_resources[0].matches == ["https://music.apple.com/*"]
  and (.host_permissions == null)
' "$ROOT/extension/chromium-manifest.json" >/dev/null
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

"$ROOT/tests/spectrum.test.sh"
pass "system spectrum analyser tests pass"

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

E2E_CLASS="melonamin.apple-music"
E2E_WORKSPACE="special:melonamin-apple-music"
E2E_TMP=""
E2E_ADDRESS=""
E2E_UNITS=""

# Mirrors control.sh: a stale HYPRLAND_INSTANCE_SIGNATURE is recovered from the
# running compositor instead of failing the call. hyprctl reports connection
# errors on stdout, so the reply is buffered and only emitted once it succeeded.
e2e_hypr_json() {
  local command=$1 output signature
  if output=$(hyprctl -j "$command" 2>/dev/null); then
    printf '%s' "$output"
    return
  fi

  signature=$(hyprctl instances -j 2>/dev/null | jq -r 'first(.[] | select(.pid > 0) | .instance) // empty')
  [[ -n $signature ]] || return 1
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl -j "$command"
}

e2e_hypr_call() {
  if hyprctl "$@" >/dev/null 2>&1; then
    return
  fi

  local signature
  signature=$(hyprctl instances -j 2>/dev/null | jq -r 'first(.[] | select(.pid > 0) | .instance) // empty')
  [[ -n $signature ]] || return 1
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl "$@" >/dev/null
}

e2e_plugin_addresses() {
  e2e_hypr_json clients | jq -r --arg class "$E2E_CLASS" '.[] | select(
      ((.class // "") == $class)
      or ((.initialClass // "") == $class)
      or ((.class // "") | contains("music.apple.com__"))
      or ((.initialClass // "") | contains("music.apple.com__"))
    ) | .address'
}

e2e_units() {
  systemctl --user list-units --plain --no-legend 'omarchy-apple-music-*' 2>/dev/null |
    awk '{print $1}'
}

# Runs on every exit, so a failed or interrupted run never leaves the disposable
# window, its transient unit, or its throwaway profile behind.
e2e_cleanup() {
  local attempt unit

  if [[ -n $E2E_ADDRESS ]]; then
    e2e_hypr_call dispatch "hl.dsp.window.close({ window = \"address:$E2E_ADDRESS\" })" || true
    for (( attempt = 0; attempt < 100; attempt++ )); do
      e2e_hypr_json clients 2>/dev/null |
        jq -e --arg address "$E2E_ADDRESS" 'any(.[]; .address == $address)' >/dev/null 2>&1 || break
      sleep 0.2
    done
    E2E_ADDRESS=""
  fi

  while read -r unit; do
    [[ -n $unit ]] || continue
    [[ $E2E_UNITS == *"|$unit|"* ]] && continue
    systemctl --user stop "$unit" >/dev/null 2>&1 || true
  done < <(e2e_units)

  if [[ -n $E2E_TMP ]]; then
    rm -rf -- "$E2E_TMP"
    E2E_TMP=""
  fi

  return 0
}

if [[ ${OMARCHY_APPLE_MUSIC_E2E:-} != "1" ]]; then
  skip "end-to-end launch/hide/close (set OMARCHY_APPLE_MUSIC_E2E=1 to enable)"
elif ! e2e_hypr_json clients >/dev/null 2>&1; then
  skip "end-to-end launch/hide/close needs a live Hyprland session"
elif ! command -v chromium >/dev/null ||
  ! command -v uwsm-app >/dev/null ||
  ! command -v systemd-run >/dev/null; then
  skip "end-to-end launch/hide/close needs chromium, uwsm-app, and systemd-run"
elif [[ -n $(e2e_plugin_addresses) ]]; then
  skip "end-to-end launch/hide/close skipped: an Apple Music window is already open"
else
  trap e2e_cleanup EXIT
  E2E_UNITS="|$(e2e_units | paste -sd '|' - || true)|"
  E2E_TMP=$(mktemp -d)

  XDG_DATA_HOME="$E2E_TMP" "$ROOT/control.sh" launch

  # Chromium relabels the app window from --class to chrome-music.apple.com__-*
  # within a frame or two, so the window is matched exactly the way control.sh
  # matches it. The guard above proved no other match existed before the launch.
  for (( attempt = 0; attempt < 100; attempt++ )); do
    E2E_ADDRESS=$(e2e_plugin_addresses 2>/dev/null | head -n 1 || true)
    [[ -n $E2E_ADDRESS ]] && break
    sleep 0.2
  done
  [[ -n $E2E_ADDRESS ]] || fail "launched Apple Music window never appeared in Hyprland"

  "$ROOT/control.sh" hide "$E2E_ADDRESS"

  for (( attempt = 0; attempt < 100; attempt++ )); do
    workspace=$(e2e_hypr_json clients 2>/dev/null |
      jq -r --arg address "$E2E_ADDRESS" \
        'first(.[] | select(.address == $address) | .workspace.name) // empty' || true)
    [[ $workspace == "$E2E_WORKSPACE" ]] && break
    sleep 0.2
  done
  [[ $workspace == "$E2E_WORKSPACE" ]] ||
    fail "hidden Apple Music window did not park on $E2E_WORKSPACE (workspace: ${workspace:-none})"

  e2e_cleanup
  [[ -z $(e2e_plugin_addresses) ]] || fail "Apple Music window survived the cleanup close"
  trap - EXIT
  pass "end-to-end launch, hide, and close work against a live session"
fi

printf '\n\033[1;32mall good\033[0m\n'

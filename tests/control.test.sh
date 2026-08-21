#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

export MOCK_LOG="$TEST_DIR/hyprctl.log"

MOCK_HYPRCTL="$TEST_DIR/hyprctl"
cat >"$MOCK_HYPRCTL" <<'MOCK'
#!/bin/bash
set -euo pipefail

if [[ ${1:-} == "-j" && ${2:-} == "clients" ]]; then
  printf '[{"address":"0xabc","class":"chrome-music.apple.com__-Default","initialClass":"chrome-music.apple.com__-Default","pid":4242,"monitor":0,"workspace":{"id":2,"name":"%s"},"size":[900,700],"at":[10,20]}]' "${MOCK_CLIENT_WORKSPACE:-2}"
elif [[ ${1:-} == "-j" && ${2:-} == "monitors" ]]; then
  printf '[{"id":0,"name":"DP-5","width":5120,"height":2880,"scale":2,"x":0,"y":0,"reserved":[0,26,0,0],"activeWorkspace":{"id":2,"name":"2"},"specialWorkspace":{"id":0,"name":""}}]'
elif [[ ${1:-} == "-j" && ${2:-} == "cursorpos" ]]; then
  printf '{"x":2100,"y":13}'
else
  printf '%s\n' "$*" >>"$MOCK_LOG"
fi
MOCK
chmod +x "$MOCK_HYPRCTL"

PATH="$TEST_DIR:$PATH" MOCK_CLIENT_WORKSPACE="special:melonamin-apple-music" \
  "$ROOT/control.sh" state | jq -e '.open == false and .openScreen == ""' >/dev/null

PATH="$TEST_DIR:$PATH" MOCK_CLIENT_WORKSPACE="2" \
  "$ROOT/control.sh" state | jq -e '.open == true and .openScreen == "DP-5"' >/dev/null

: >"$MOCK_LOG"
PATH="$TEST_DIR:$PATH" "$ROOT/control.sh" show 0xabc DP-5 1200 80 900 700
grep -F 'hl.dsp.window.move({ window = "address:0xabc", workspace = "2", follow = false })' "$MOCK_LOG" >/dev/null
grep -F 'hl.dsp.window.resize({ window = "address:0xabc", x = 900, y = 700, relative = false })' "$MOCK_LOG" >/dev/null
grep -F 'hl.dsp.window.move({ window = "address:0xabc", x = 1200, y = 80, relative = false })' "$MOCK_LOG" >/dev/null
grep -F 'hl.dsp.cursor.move({ x = 2100, y = 13 })' "$MOCK_LOG" >/dev/null

: >"$MOCK_LOG"
PATH="$TEST_DIR:$PATH" "$ROOT/control.sh" hide 0xabc
grep -F 'hl.dsp.window.move({ window = "address:0xabc", workspace = "special:melonamin-apple-music", follow = false })' "$MOCK_LOG" >/dev/null

: >"$MOCK_LOG"
PATH="$TEST_DIR:$PATH" "$ROOT/control.sh" focus 0xabc
grep -F 'hl.dsp.focus({ window = "address:0xabc" })' "$MOCK_LOG" >/dev/null
grep -F 'hl.dsp.cursor.move({ x = 2100, y = 13 })' "$MOCK_LOG" >/dev/null

revision=$(XDG_DATA_HOME="$TEST_DIR/data" XDG_RUNTIME_DIR="$TEST_DIR/runtime" "$ROOT/control.sh" theme \
  '#222222' '#c2c2b0' '#78824b' '#78824b' '#666666' '#685742' dark)
[[ $revision =~ ^[0-9]+$ ]]

RUNTIME_EXTENSION="$TEST_DIR/runtime/omarchy-apple-music/extension"
for name in manifest.json theme-model.js player-model.js player-bridge.js content.js content.css theme.json spectrum.json; do
  [[ -f $RUNTIME_EXTENSION/$name ]]
done
jq -e --arg revision "$revision" '
  .schemaVersion == 1
  and .revision == $revision
  and .mode == "dark"
  and .colors.background == "#222222"
  and .colors.foreground == "#c2c2b0"
  and .colors.border == "#78824b"
  and .colors.accent == "#78824b"
  and .colors.muted == "#666666"
  and .colors.urgent == "#685742"
' "$RUNTIME_EXTENSION/theme.json" >/dev/null
jq -e '.schemaVersion == 1 and .active == false and .bands == []' "$RUNTIME_EXTENSION/spectrum.json" >/dev/null

touch "$RUNTIME_EXTENSION/background.js"
XDG_DATA_HOME="$TEST_DIR/data" XDG_RUNTIME_DIR="$TEST_DIR/runtime" "$ROOT/control.sh" theme \
  '#222222' '#c2c2b0' '#78824b' '#78824b' '#666666' '#685742' dark >/dev/null
[[ ! -e $RUNTIME_EXTENSION/background.js ]]
[[ -f $RUNTIME_EXTENSION/theme.json ]]

grep -F 'load_extension_paths' "$ROOT/control.sh" >/dev/null
grep -F 'chromium-flags.conf' "$ROOT/control.sh" >/dev/null

MOCK_SYSTEMD_RUN="$TEST_DIR/systemd-run"
cat >"$MOCK_SYSTEMD_RUN" <<'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$MOCK_SYSTEMD_RUN"

MOCK_CHROMIUM="$TEST_DIR/chromium"
cat >"$MOCK_CHROMIUM" <<'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$MOCK_CHROMIUM"

XDG_DATA_HOME="$TEST_DIR/launch-data" XDG_RUNTIME_DIR="$TEST_DIR/launch-runtime" PATH="$TEST_DIR:$PATH" "$ROOT/control.sh" launch
PROFILE_PREFERENCES="$TEST_DIR/launch-data/omarchy-apple-music/chromium/Default/Preferences"
jq -e '.partition.default_zoom_level.x == -0.5778829311823857' "$PROFILE_PREFERENCES" >/dev/null

CORRUPT_PREFERENCES="$TEST_DIR/corrupt-data/omarchy-apple-music/chromium/Default/Preferences"
mkdir -p "$(dirname "$CORRUPT_PREFERENCES")"
printf 'not json\n' >"$CORRUPT_PREFERENCES"
XDG_DATA_HOME="$TEST_DIR/corrupt-data" XDG_RUNTIME_DIR="$TEST_DIR/corrupt-runtime" PATH="$TEST_DIR:$PATH" "$ROOT/control.sh" launch
jq -e '.partition.default_zoom_level.x == -0.5778829311823857' "$CORRUPT_PREFERENCES" >/dev/null

if XDG_DATA_HOME="$TEST_DIR/data" XDG_RUNTIME_DIR="$TEST_DIR/runtime" "$ROOT/control.sh" theme \
  red '#c2c2b0' '#78824b' '#78824b' '#666666' '#685742' dark 2>/dev/null; then
  echo "invalid colors must be rejected" >&2
  exit 1
fi

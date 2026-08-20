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

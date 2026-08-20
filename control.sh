#!/bin/bash
set -euo pipefail

WINDOW_CLASS="melonamin.apple-music"
SPECIAL_NAME="melonamin-apple-music"
SPECIAL_WORKSPACE="special:$SPECIAL_NAME"
APPLE_MUSIC_URL="https://music.apple.com"

hypr_json() {
  local command=$1 output signature
  if output=$(hyprctl -j "$command" 2>/dev/null); then
    printf '%s' "$output"
    return
  fi

  signature=$(hyprctl instances -j 2>/dev/null | jq -r 'first(.[] | select(.pid > 0) | .instance) // empty')
  [[ -n $signature ]] || return 1
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl -j "$command"
}

hypr_call() {
  if hyprctl "$@" >/dev/null 2>&1; then
    return
  fi

  local signature
  signature=$(hyprctl instances -j 2>/dev/null | jq -r 'first(.[] | select(.pid > 0) | .instance) // empty')
  [[ -n $signature ]] || return 1
  HYPRLAND_INSTANCE_SIGNATURE=$signature hyprctl "$@" >/dev/null
}

state() {
  local clients monitors
  clients=$(hypr_json clients)
  monitors=$(hypr_json monitors)

  jq -cn \
    --arg class "$WINDOW_CLASS" \
    --arg workspace "$SPECIAL_WORKSPACE" \
    --argjson clients "$clients" \
    --argjson monitors "$monitors" \
    '(first($clients[] | select(
        ((.class // "") == $class)
        or ((.initialClass // "") == $class)
        or ((.class // "") | contains("music.apple.com__"))
        or ((.initialClass // "") | contains("music.apple.com__"))
      )) // null) as $client |
    {
      client: $client,
      monitors: $monitors,
      open: ($client != null and ($client.workspace.name // "") != $workspace),
      openScreen: (if $client != null and ($client.workspace.name // "") != $workspace
        then (first($monitors[] | select(.id == $client.monitor) | .name) // "")
        else ""
      end)
    }'
}

browser_executable() {
  local browser executable
  browser=$(env -u BROWSER xdg-settings get default-web-browser 2>/dev/null || true)
  case $browser in
  google-chrome* | brave* | microsoft-edge* | opera* | vivaldi* | helium* | chromium*) ;;
  *) browser="chromium.desktop" ;;
  esac

  executable=$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' \
    "$HOME/.local/share/applications/$browser" \
    "$HOME/.nix-profile/share/applications/$browser" \
    "/usr/share/applications/$browser" 2>/dev/null | head -1)
  [[ -n $executable ]] || executable="chromium"
  command -v "$executable"
}

launch() {
  local executable profile_dir unit
  executable=$(browser_executable)
  profile_dir="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-apple-music/chromium"
  unit="omarchy-apple-music-$(date +%s%N)"

  umask 077
  mkdir -p "$profile_dir"

  systemd-run --user --quiet --collect --unit="$unit" \
    --property=StandardOutput=null --property=StandardError=null \
    uwsm-app -- "$executable" \
      --user-data-dir="$profile_dir" \
      --class="$WINDOW_CLASS" \
      --app="$APPLE_MUSIC_URL" \
      --no-first-run
}

show_window() {
  local address=$1 screen=$2 x=$3 y=$4 width=$5 height=$6

  [[ $address =~ ^0x[0-9a-fA-F]+$ ]] || return 2
  [[ $screen =~ ^[[:alnum:]_.:-]+$ ]] || return 2
  [[ $x =~ ^-?[0-9]+$ && $y =~ ^-?[0-9]+$ ]] || return 2
  [[ $width =~ ^[0-9]+$ && $height =~ ^[0-9]+$ ]] || return 2

  local current workspace cursor_json cursor_x cursor_y
  cursor_json=$(hypr_json cursorpos 2>/dev/null || true)
  cursor_x=$(jq -r '(.x // empty) | floor' <<<"$cursor_json" 2>/dev/null || true)
  cursor_y=$(jq -r '(.y // empty) | floor' <<<"$cursor_json" 2>/dev/null || true)
  if [[ ! $cursor_x =~ ^-?[0-9]+$ || ! $cursor_y =~ ^-?[0-9]+$ ]]; then
    cursor_x=""
    cursor_y=""
  fi

  current=$(hypr_json monitors | jq -r --arg workspace "$SPECIAL_WORKSPACE" \
    'first(.[] | select((.specialWorkspace.name // "") == $workspace) | .name) // empty')
  workspace=$(hypr_json monitors | jq -r --arg screen "$screen" \
    'first(.[] | select(.name == $screen) | .activeWorkspace.name) // empty')
  [[ -n $workspace && $workspace != *$'\n'* && $workspace != *'"'* && $workspace != *'\\'* ]] || return 2

  hypr_call dispatch "hl.dsp.window.move({ window = \"address:$address\", workspace = \"$workspace\", follow = false })"

  if [[ -n $current ]]; then
    hypr_call dispatch "hl.dsp.focus({ monitor = \"$current\" })"
    hypr_call dispatch "hl.dsp.workspace.toggle_special(\"$SPECIAL_NAME\")"
  fi

  hypr_call dispatch "hl.dsp.focus({ monitor = \"$screen\" })"
  hypr_call dispatch "hl.dsp.window.resize({ window = \"address:$address\", x = $width, y = $height, relative = false })"
  hypr_call dispatch "hl.dsp.window.move({ window = \"address:$address\", x = $x, y = $y, relative = false })"
  hypr_call dispatch "hl.dsp.focus({ window = \"address:$address\" })"

  if [[ -n $cursor_x ]]; then
    hypr_call dispatch "hl.dsp.cursor.move({ x = $cursor_x, y = $cursor_y })"
  fi
}

hide_window() {
  local address=${1:-}
  if [[ -z $address ]]; then
    address=$(state | jq -r '.client.address // empty')
  fi
  [[ $address =~ ^0x[0-9a-fA-F]+$ ]] || return
  hypr_call dispatch "hl.dsp.window.move({ window = \"address:$address\", workspace = \"$SPECIAL_WORKSPACE\", follow = false })"
}

install_rules() {
  local lua_path=$1 force=${2:-false} code
  [[ -f $lua_path ]]
  code="dofile('$(printf '%s' "$lua_path" | sed "s/'/\\\\'/g")'); omarchy_apple_music.install($force)"
  hypr_call eval "$code"
}

case ${1:-} in
state) state ;;
launch) launch ;;
show)
  (( $# == 7 )) || { echo "usage: $0 show <address> <screen> <x> <y> <width> <height>" >&2; exit 2; }
  show_window "$2" "$3" "$4" "$5" "$6" "$7"
  ;;
hide) hide_window "${2:-}" ;;
rules)
  (( $# >= 2 )) || { echo "usage: $0 rules <lua-path> [true|false]" >&2; exit 2; }
  install_rules "$2" "${3:-false}"
  ;;
*)
  echo "usage: $0 <state|launch|show|hide|rules>" >&2
  exit 2
  ;;
esac

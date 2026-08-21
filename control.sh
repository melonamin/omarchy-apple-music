#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WINDOW_CLASS="melonamin.apple-music"
SPECIAL_NAME="melonamin-apple-music"
SPECIAL_WORKSPACE="special:$SPECIAL_NAME"
APPLE_MUSIC_URL="https://music.apple.com"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-apple-music"
PROFILE_DIR="$DATA_DIR/chromium"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-$DATA_DIR/runtime}/omarchy-apple-music"
EXTENSION_DIR="$RUNTIME_DIR/extension"
EXTENSION_FILES=(manifest.json theme-model.js player-model.js player-bridge.js content.js content.css)
EXTENSION_MANIFEST_SOURCE="chromium-manifest.json"
DEFAULT_ZOOM_LEVEL="-0.5778829311823857"

write_theme_file() {
  local background=$1 foreground=$2 border=$3 accent=$4 muted=$5 urgent=$6 mode=$7
  local revision tmp
  revision=$(date +%s%N)
  tmp=$(mktemp "$EXTENSION_DIR/.theme.XXXXXX")

  if ! jq -n \
    --arg revision "$revision" \
    --arg mode "$mode" \
    --arg background "$background" \
    --arg foreground "$foreground" \
    --arg border "$border" \
    --arg accent "$accent" \
    --arg muted "$muted" \
    --arg urgent "$urgent" \
    '{schemaVersion: 1, revision: $revision, mode: $mode, colors: {
      background: $background,
      foreground: $foreground,
      border: $border,
      accent: $accent,
      muted: $muted,
      urgent: $urgent
    }}' >"$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi

  chmod 0600 "$tmp"
  mv -f -- "$tmp" "$EXTENSION_DIR/theme.json"
  printf '%s\n' "$revision"
}

prepare_extension() {
  local name entry known keep
  umask 077
  mkdir -p "$EXTENSION_DIR"
  for name in "${EXTENSION_FILES[@]}"; do
    if [[ $name == "manifest.json" ]]; then
      install -m 0644 "$ROOT/extension/$EXTENSION_MANIFEST_SOURCE" "$EXTENSION_DIR/$name"
    else
      install -m 0644 "$ROOT/extension/$name" "$EXTENSION_DIR/$name"
    fi
  done

  # Files dropped by newer plugin versions must not linger in deployed profiles.
  for entry in "$EXTENSION_DIR"/*; do
    [[ -e $entry ]] || continue
    name=${entry##*/}
    [[ $name == theme.json || $name == spectrum.json ]] && continue
    keep=false
    for known in "${EXTENSION_FILES[@]}"; do
      [[ $name == "$known" ]] && { keep=true; break; }
    done
    [[ $keep == true ]] || rm -rf -- "$entry"
  done

  if [[ ! -f $EXTENSION_DIR/theme.json ]]; then
    write_theme_file "#1f1f1f" "#f5f5f7" "#555555" "#fa586a" "#98989d" "#ff453a" "dark" >/dev/null
  fi
  if [[ ! -f $EXTENSION_DIR/spectrum.json ]]; then
    printf '{"schemaVersion":1,"active":false,"revision":0,"bands":[]}\n' >"$EXTENSION_DIR/spectrum.json"
    chmod 0600 "$EXTENSION_DIR/spectrum.json"
  fi
}

configure_profile() {
  local preferences="$PROFILE_DIR/Default/Preferences" current tmp
  umask 077
  mkdir -p "$PROFILE_DIR/Default"

  if [[ -f $preferences ]] && current=$(jq -r '.partition.default_zoom_level.x // empty' "$preferences" 2>/dev/null); then
    [[ $current == "$DEFAULT_ZOOM_LEVEL" ]] && return
    tmp=$(mktemp "$PROFILE_DIR/Default/.Preferences.XXXXXX")
    if ! jq --argjson level "$DEFAULT_ZOOM_LEVEL" '.partition.default_zoom_level.x = $level' "$preferences" >"$tmp"; then
      rm -f -- "$tmp"
      return 1
    fi
  else
    tmp=$(mktemp "$PROFILE_DIR/Default/.Preferences.XXXXXX")
    if ! jq -n --argjson level "$DEFAULT_ZOOM_LEVEL" '{partition: {default_zoom_level: {x: $level}}}' >"$tmp"; then
      rm -f -- "$tmp"
      return 1
    fi
  fi

  chmod 0600 "$tmp"
  mv -f -- "$tmp" "$preferences"
}

publish_theme() {
  (( $# == 7 )) || { echo "usage: $0 theme <background> <foreground> <border> <accent> <muted> <urgent> <dark|light>" >&2; return 2; }
  local color
  for color in "${@:1:6}"; do
    [[ $color =~ ^#[0-9a-fA-F]{6}$ ]] || { echo "invalid theme color: $color" >&2; return 2; }
  done
  [[ $7 == "dark" || $7 == "light" ]] || { echo "invalid theme mode: $7" >&2; return 2; }

  prepare_extension
  write_theme_file "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

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
  command -v chromium
}

load_extension_paths() {
  local file line value paths=""
  for file in "/etc/chromium/chromium-flags.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/chromium-flags.conf"; do
    [[ -f $file ]] || continue
    while IFS= read -r line; do
      if [[ $line =~ ^[[:space:]]*--load-extension=(.+)$ ]]; then
        value=${BASH_REMATCH[1]}
        value=${value#\"}
        value=${value%\"}
        value=${value#\'}
        value=${value%\'}
        paths+="${paths:+,}$value"
      fi
    done <"$file"
  done
  printf '%s%s%s\n' "$paths" "${paths:+,}" "$EXTENSION_DIR"
}

launch() {
  local executable extension_paths unit
  executable=$(browser_executable)
  extension_paths=$(load_extension_paths)
  unit="omarchy-apple-music-$(date +%s%N)"

  prepare_extension
  configure_profile

  systemd-run --user --quiet --collect --unit="$unit" \
    --property=StandardOutput=null --property=StandardError=null \
    uwsm-app -- "$executable" \
      --user-data-dir="$PROFILE_DIR" \
      --load-extension="$extension_paths" \
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

focus_window() {
  local address=$1 cursor_json cursor_x cursor_y
  [[ $address =~ ^0x[0-9a-fA-F]+$ ]] || return 2

  cursor_json=$(hypr_json cursorpos 2>/dev/null || true)
  cursor_x=$(jq -r '(.x // empty) | floor' <<<"$cursor_json" 2>/dev/null || true)
  cursor_y=$(jq -r '(.y // empty) | floor' <<<"$cursor_json" 2>/dev/null || true)
  if [[ ! $cursor_x =~ ^-?[0-9]+$ || ! $cursor_y =~ ^-?[0-9]+$ ]]; then
    cursor_x=""
    cursor_y=""
  fi

  hypr_call dispatch "hl.dsp.focus({ window = \"address:$address\" })"
  if [[ -n $cursor_x ]]; then
    hypr_call dispatch "hl.dsp.cursor.move({ x = $cursor_x, y = $cursor_y })"
  fi
}

wait_for_theme() {
  local attempt observed=0
  for (( attempt = 0; attempt < 300; attempt++ )); do
    if pgrep -u "$UID" -f '[o]marchy-theme-set([[:space:]]|$)' >/dev/null; then
      observed=1
    elif (( observed )); then
      sleep 1
      return
    elif (( attempt >= 15 )); then
      return
    fi
    sleep 0.1
  done
  sleep 1
}

install_rules() {
  local lua_path=$1 force=${2:-false} code
  [[ -f $lua_path ]]
  code="dofile('$(printf '%s' "$lua_path" | sed "s/'/\\\\'/g")'); omarchy_apple_music.install($force)"
  hypr_call eval "$code"
}

run_spectrum() {
  local browser_pid=$1
  [[ $browser_pid =~ ^[0-9]+$ ]] || return 2
  prepare_extension
  exec "$ROOT/spectrum.sh" "$browser_pid" "$EXTENSION_DIR/spectrum.json"
}

case ${1:-} in
state) state ;;
launch) launch ;;
show)
  (( $# == 7 )) || { echo "usage: $0 show <address> <screen> <x> <y> <width> <height>" >&2; exit 2; }
  show_window "$2" "$3" "$4" "$5" "$6" "$7"
  ;;
hide) hide_window "${2:-}" ;;
focus)
  (( $# == 2 )) || { echo "usage: $0 focus <address>" >&2; exit 2; }
  focus_window "$2"
  ;;
wait-theme) wait_for_theme ;;
theme)
  shift
  publish_theme "$@"
  ;;
rules)
  (( $# >= 2 )) || { echo "usage: $0 rules <lua-path> [true|false]" >&2; exit 2; }
  install_rules "$2" "${3:-false}"
  ;;
spectrum)
  (( $# == 2 )) || { echo "usage: $0 spectrum <browser-pid>" >&2; exit 2; }
  run_spectrum "$2"
  ;;
*)
  echo "usage: $0 <state|launch|show|hide|focus|wait-theme|theme|rules|spectrum>" >&2
  exit 2
  ;;
esac

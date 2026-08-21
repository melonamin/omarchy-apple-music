#!/bin/bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BROWSER_PID=${1:-}
OUTPUT=${2:-}
SAMPLE_RATE=24000
FRAME_SAMPLES=1024
BAR_COUNT=32
PIPE_DIR=""
PAREC_PID=""
OD_PID=""
AWK_PID=""

[[ $BROWSER_PID =~ ^[0-9]+$ && -n $OUTPUT ]] || {
  echo "usage: $0 <browser-pid> <output-json>" >&2
  exit 2
}

publish_inactive() {
  printf '{"schemaVersion":1,"active":false,"revision":0,"bands":[]}\n' >"$OUTPUT"
}

cleanup() {
  local process
  for process in "$PAREC_PID" "$OD_PID" "$AWK_PID"; do
    [[ $process =~ ^[0-9]+$ ]] && kill "$process" 2>/dev/null || true
  done
  if [[ -n $PIPE_DIR && -d $PIPE_DIR ]]; then
    rm -rf -- "$PIPE_DIR"
  fi
  publish_inactive
}

stop() {
  exit 0
}

trap cleanup EXIT
trap stop INT TERM

is_descendant() {
  local process=$1 parent depth
  for (( depth = 0; depth < 16; depth++ )); do
    [[ $process == "$BROWSER_PID" ]] && return 0
    [[ $process =~ ^[0-9]+$ && -r /proc/$process/stat ]] || return 1
    parent=$(awk '{ print $4 }' "/proc/$process/stat" 2>/dev/null) || return 1
    [[ $parent != "$process" ]] || return 1
    process=$parent
  done
  return 1
}

find_sink_input() {
  local index process
  while IFS=$'\t' read -r index process; do
    [[ $index =~ ^[0-9]+$ && $process =~ ^[0-9]+$ ]] || continue
    if is_descendant "$process"; then
      printf '%s\n' "$index"
      return 0
    fi
  done < <(pactl -f json list sink-inputs 2>/dev/null | jq -r '.[] | [.index, .properties["application.process.id"]] | @tsv' 2>/dev/null)
  return 1
}

mkdir -p "$(dirname "$OUTPUT")"
publish_inactive

while [[ -d /proc/$BROWSER_PID ]]; do
  sinkInput=$(find_sink_input || true)
  if [[ -z $sinkInput ]]; then
    sleep 0.25
    continue
  fi

  PIPE_DIR=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/omarchy-apple-spectrum.XXXXXX")
  mkfifo "$PIPE_DIR/pcm" "$PIPE_DIR/samples"

  parec \
    --monitor-stream="$sinkInput" \
    --rate="$SAMPLE_RATE" \
    --channels=1 \
    --format=s16le \
    --latency-msec=50 \
    --process-time-msec=42 \
    --raw >"$PIPE_DIR/pcm" 2>/dev/null &
  PAREC_PID=$!
  od -An -v -w$((FRAME_SAMPLES * 2)) -t d2 <"$PIPE_DIR/pcm" >"$PIPE_DIR/samples" &
  OD_PID=$!
  awk \
    -v output="$OUTPUT" \
    -v rate="$SAMPLE_RATE" \
    -v bars="$BAR_COUNT" \
    -f "$ROOT/spectrum.awk" <"$PIPE_DIR/samples" &
  AWK_PID=$!
  wait "$AWK_PID" 2>/dev/null || true

  for process in "$PAREC_PID" "$OD_PID"; do
    [[ $process =~ ^[0-9]+$ ]] && kill "$process" 2>/dev/null || true
  done
  wait "$PAREC_PID" "$OD_PID" 2>/dev/null || true
  rm -rf -- "$PIPE_DIR"
  PIPE_DIR=""
  PAREC_PID=""
  OD_PID=""
  AWK_PID=""

  publish_inactive
  sleep 0.15
done

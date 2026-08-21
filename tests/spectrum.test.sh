#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

bash -n "$ROOT/spectrum.sh"
[[ -x $ROOT/spectrum.sh ]]

awk 'BEGIN {
  pi = atan2(0, -1)
  for (sample = 0; sample < 1024; sample++) {
    value = int(sin(2 * pi * 1000 * sample / 24000) * 26000)
    printf "%d%s", value, sample == 1023 ? "\n" : " "
  }
}' | awk -v output="$TEST_DIR/spectrum.json" -v rate=24000 -v bars=32 -f "$ROOT/spectrum.awk"

jq -e '.schemaVersion == 1 and .active == true and (.bands | length) == 32' "$TEST_DIR/spectrum.json" >/dev/null
dominant=$(jq -r '.bands | to_entries | max_by(.value) | .key' "$TEST_DIR/spectrum.json")
(( dominant >= 16 && dominant <= 19 ))

if "$ROOT/spectrum.sh" invalid "$TEST_DIR/invalid.json" 2>/dev/null; then
  echo "invalid browser PIDs must be rejected" >&2
  exit 1
fi

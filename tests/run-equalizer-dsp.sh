#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BIN="$(mktemp "${TMPDIR:-/tmp}/spotify6-eq-test.XXXXXX")"
trap 'rm -f "$BIN"' EXIT HUP INT TERM
${CC:-clang} -std=c99 -Wall -Wextra -Werror \
  "$ROOT/tests/test-equalizer-dsp.c" "$ROOT/music/Spot/MMEqualizerDSP.c" \
  -lm -o "$BIN"
"$BIN"

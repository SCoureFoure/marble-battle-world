#!/usr/bin/env bash
# The membrane. Run ONE headless test suite and exit non-zero unless it genuinely passed.
#
# `godot --headless --script X` exits 0 even when X fails to PARSE, so a bare exit-code
# check would read a broken test as green. A pass here requires ALL of:
#   - the godot process exited 0
#   - stdout contains ALL_PASS
#   - stdout contains no parse/script error and no FAILURES= line
#
# A --import pass runs first so newly added class_name scripts are visible.
#
# Usage: bash tools/verify.sh <test_basename> [round]
#   e.g. bash tools/verify.sh test_spatial_hash 2
# Writes full output to .warboss-horde/out/<test_basename>-r<round>.txt

set -uo pipefail

GODOT="${GODOT:-C:/Users/SCora/Desktop/Godot_v4.7-stable_win64.exe}"
TEST="${1:?usage: verify.sh <test_basename> [round]}"
ROUND="${2:-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTDIR="$ROOT/.warboss-horde/out"
OUT="$OUTDIR/${TEST}-r${ROUND}.txt"

mkdir -p "$OUTDIR"

"$GODOT" --headless --path "$ROOT" --import >"$OUTDIR/import.txt" 2>&1
# A script that fails to load can leave godot's main loop running with no quit(); bound it.
timeout 120 "$GODOT" --headless --path "$ROOT" --script "res://scripts/tests/${TEST}.gd" >"$OUT" 2>&1
RC=$?

fail() { echo "VERDICT=RED reason=$1 file=$OUT"; exit 1; }

[ "$RC" -eq 0 ] || fail "exit_$RC"
grep -qE 'Parse Error|SCRIPT ERROR|Failed to load script|Compile Error' "$OUT" && fail "parse_error"
grep -q 'FAILURES=' "$OUT" && fail "assertions_failed"
grep -q 'ALL_PASS' "$OUT" || fail "no_all_pass"

echo "VERDICT=GREEN file=$OUT"

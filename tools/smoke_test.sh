#!/usr/bin/env bash
# Smoke test: clone the committed state fresh (no editor cache, like a new
# checkout), launch it, and fail on ANY script/engine error. Also checks the
# committed class cache is current. Run before every push.
#   GODOT=/path/to/godot tools/smoke_test.sh
set -u
GODOT="${GODOT:-godot}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone -q "$REPO" "$TMP/p" || exit 1
cd "$TMP/p"
echo "== $("$GODOT" --version)"

echo "== 1. fresh launch, no import (what you get after git clone / pull)"
OUT1="$(timeout 120 "$GODOT" --headless --path . --fixed-fps 60 --quit-after 600 -- --bot --seed=1 2>&1)"
E1="$(echo "$OUT1" | grep -E "SCRIPT ERROR|^ERROR|Parse Error" )"

echo "== 2. 2-minute simulated playthrough"
OUT2="$(timeout 300 "$GODOT" --headless --path . --fixed-fps 60 --quit-after 7200 -- --bot --seed=7 2>&1)"
E2="$(echo "$OUT2" | grep -E "SCRIPT ERROR|^ERROR|Parse Error" )"
echo "$OUT2" | grep -E "\[director\]|WON|refit done" | head -8

echo "== 3. committed class cache is up to date"
STALE=""
if ! git diff --quiet -- .godot/global_script_class_cache.cfg; then STALE="yes"; fi

if [ -n "$E1$E2" ] || [ -n "$STALE" ]; then
  echo "FAIL"
  [ -n "$E1" ] && echo "-- fresh launch errors:" && echo "$E1" | sort -u | head -30
  [ -n "$E2" ] && echo "-- playthrough errors:" && echo "$E2" | sort -u | head -30
  [ -n "$STALE" ] && echo "-- .godot/global_script_class_cache.cfg is stale: run the game/editor once and commit it"
  exit 1
fi
echo "PASS"

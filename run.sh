#!/usr/bin/env bash
# Launch LastGears. Uses ~/bin/godot unless GODOT is set.
cd "$(dirname "$0")"
GODOT="${GODOT:-$HOME/bin/godot}"
if [ ! -d .godot/imported ]; then
  echo "First run: importing project..."
  "$GODOT" --headless --path . --import >/dev/null 2>&1
fi
exec "$GODOT" --path . "$@"

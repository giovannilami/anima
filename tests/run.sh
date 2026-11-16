#!/usr/bin/env bash
set -euo pipefail
# Usage: bash tests/run.sh /path/to/lua /path/to/norns [original Animator] [Crow output.lua]
animator_lua=${1:-lua}
animator_norns=${2:?provide norns source root}
animator_data=$(mktemp -d /private/tmp/anima-tests.XXXXXX)
trap 'rm -rf "$animator_data"' EXIT
for test in snapshots grid_pages playback persistence modulation lfo_menu; do
  "$animator_lua" "tests/$test.lua" "$animator_norns" "$animator_data"
done
"$animator_lua" tests/history_grid.lua "$animator_norns"
"$animator_lua" tests/freeze_simulation.lua "$animator_norns"
"$animator_lua" tests/outputs.lua
"$animator_lua" tests/runtime.lua "$animator_norns" "$animator_data" nb
"$animator_lua" tests/runtime.lua "$animator_norns" "$animator_data" absent
"$animator_lua" tests/lifecycle.lua "$animator_norns"
"$animator_lua" tests/patterns.lua "$animator_norns"
if [ -n "${3:-}" ]; then
  "$animator_lua" tests/crow_compat.lua "$animator_norns" "$3"
  "$animator_lua" tests/original_import.lua "$animator_norns" "$3" "$animator_data"
fi
if [ -n "${4:-}" ]; then
  "$animator_lua" tests/crow_device.lua "$animator_norns" "$4"
fi

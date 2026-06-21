#!/usr/bin/env bash
# Fixture test for ryoku-monitor's Ryoku Settings surface: explicit apply, named
# hardware-keyed profiles, and the identity remap that makes a profile survive a
# connector rename. Runs the script in fixture mode (RYOKU_MONITOR_JSON), so no
# live compositor is needed.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
mon="$here/../system/hardware/display/ryoku-monitor"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

conf="$tmp/monitors.lua"
profiles="$tmp/profiles"

# Two distinct displays, Dell on DP-1 and LG on DP-2.
cat >"$tmp/two.json" <<'JSON'
[
  {"name":"DP-1","make":"Dell","model":"U2720Q","serial":"ABC123","width":3840,"height":2160,"refreshRate":60.0,"x":0,"y":0,"scale":1.5,"transform":0,"vrr":false,"disabled":false,"focused":true,"mirrorOf":"none","availableModes":["3840x2160@60.00Hz","2560x1440@60.00Hz"]},
  {"name":"DP-2","make":"LG","model":"27GL850","serial":"XYZ789","width":2560,"height":1440,"refreshRate":144.0,"x":3840,"y":0,"scale":1.0,"transform":0,"vrr":true,"disabled":false,"focused":false,"mirrorOf":"none","availableModes":["2560x1440@144.00Hz"]}
]
JSON

# The same two displays, but the connectors have swapped (DP reshuffle).
cat >"$tmp/swapped.json" <<'JSON'
[
  {"name":"DP-2","make":"Dell","model":"U2720Q","serial":"ABC123","width":3840,"height":2160,"refreshRate":60.0,"x":0,"y":0,"scale":1.0,"transform":0,"vrr":false,"disabled":false,"focused":true,"mirrorOf":"none","availableModes":["3840x2160@60.00Hz"]},
  {"name":"DP-1","make":"LG","model":"27GL850","serial":"XYZ789","width":2560,"height":1440,"refreshRate":144.0,"x":0,"y":0,"scale":1.0,"transform":0,"vrr":false,"disabled":false,"focused":false,"mirrorOf":"none","availableModes":["2560x1440@144.00Hz"]}
]
JSON

layout='[
  {"id":"Dell|U2720Q|ABC123","output":"DP-1","mode":"3840x2160@60","position":"0x0","scale":1.5,"transform":0,"vrr":0,"mirror":"none","disabled":false},
  {"id":"LG|27GL850|XYZ789","output":"DP-2","mode":"2560x1440@144","position":"2560x0","scale":1,"transform":1,"vrr":1,"mirror":"none","disabled":false}
]'

run() { RYOKU_MONITOR_JSON="$tmp/two.json" RYOKU_MONITORS_CONF="$conf" RYOKU_MONITORS_DIR="$profiles" "$mon" "$@"; }
fail() { echo "FAIL: $1" >&2; exit 1; }
has() { grep -qF -- "$2" "$1" || fail "$3"; }

# --- list -----------------------------------------------------------------
n="$(run list | jq 'length')"
[[ $n == 2 ]] || fail "list returned $n monitors, want 2"
run list | jq -e '.[0].id == "Dell|U2720Q|ABC123"' >/dev/null || fail "list missing hardware id"
run list | jq -e '(.[0].modes | length) == 2' >/dev/null || fail "list missing available modes"

# --- apply: explicit modes preserved (not highrr) -------------------------
run apply "$layout" >/dev/null
has "$conf" 'mode = "3840x2160@60"' "apply did not keep the chosen 4K mode"
has "$conf" 'mode = "2560x1440@144"' "apply did not keep the chosen LG mode"
has "$conf" 'transform = 1' "apply dropped the transform"
has "$conf" 'vrr = 1' "apply dropped vrr"
has "$conf" 'position = "2560x0"' "apply dropped the position"
has "$conf" 'output = "", mode = "highrr"' "apply omitted the hotplug catch-all"
grep -q 'highrr' <(grep 'DP-1' "$conf") && fail "DP-1 was written as highrr, not its explicit mode"

# --- save + profiles ------------------------------------------------------
run save desk "$layout" >/dev/null
[[ -f "$profiles/desk.json" ]] || fail "save did not write the profile file"
run profiles | jq -e '.[0].name == "desk" and .[0].matches == true' >/dev/null \
  || fail "profiles did not report desk as matching the connected set"

# A non-matching profile (one display) must not match the two-display set.
echo '{"monitors":[{"id":"Other|Mon|0","output":"DP-9","mode":"highrr","position":"0x0","scale":1}]}' >"$profiles/laptop.json"
run profiles | jq -e '[.[] | select(.name=="laptop")][0].matches == false' >/dev/null \
  || fail "single-display profile wrongly matched the two-display set"

# --- load with a reshuffle: identity remap --------------------------------
RYOKU_MONITOR_JSON="$tmp/swapped.json" RYOKU_MONITORS_CONF="$conf" RYOKU_MONITORS_DIR="$profiles" "$mon" load desk >/dev/null
# Dell's 4K mode must now be written against DP-2 (where Dell now lives), and the
# LG 144Hz mode against DP-1.
grep -q 'output = "DP-2", mode = "3840x2160@60"' "$conf" || fail "load did not remap Dell to its new connector DP-2"
grep -q 'output = "DP-1", mode = "2560x1440@144"' "$conf" || fail "load did not remap LG to its new connector DP-1"

echo "monitor-profiles: all checks passed"

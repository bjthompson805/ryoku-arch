#!/usr/bin/env bash
# Fixture test for ryoku-cmd-game-mode: the one-click competitive toggle. Stubs
# hyprctl and pkexec on PATH and points the state + sysfs scan at a tmp dir, so the
# real compositor and the real WiFi radio are never touched. Verifies the toggle
# lifecycle, that the compositor goes through `hyprctl eval` (not the keyword path
# the Lua parser rejects) with tearing + the immediate rule and reverts via reload,
# that WiFi power-save is delegated to the privileged ryoku-wifi-powersave helper
# through pkexec (off on start, on on stop), and that it is a clean no-op when
# there is no WiFi device or the helper is absent.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
gm="$here/../ryoku/hyprland/scripts/ryoku-cmd-game-mode"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bin="$tmp/bin"; mkdir -p "$bin"
calls="$tmp/calls.log"

cat >"$bin/hyprctl" <<EOF
#!/usr/bin/env bash
echo "hyprctl \$*" >>"$calls"
exit 0
EOF
cat >"$bin/pkexec" <<EOF
#!/usr/bin/env bash
echo "pkexec \$*" >>"$calls"
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/notify-send"
printf '#!/usr/bin/env bash\nexit 0\n' >"$bin/ryoku-wifi-powersave"
chmod +x "$bin"/*

# Fake sysfs with one WiFi device (overridable per-test).
net="$tmp/net"; mkdir -p "$net/wlan0/wireless" "$net/eth0"
nonet="$tmp/nonet"; mkdir -p "$nonet/eth0"

export PATH="$bin:$PATH"
export RYOKU_STATE_PATH="$tmp/state"
export RYOKU_GAMEMODE_STATE_FILE="$tmp/state/game-mode.enabled"
export RYOKU_NET_SYSFS="$net"
state="$RYOKU_GAMEMODE_STATE_FILE"

fail() { echo "FAIL: $1" >&2; exit 1; }
on() { [[ -f $state ]]; }

"$gm" status && fail "status reported on before any start"

# --- start: compositor via eval + WiFi helper off ---------------------------
: >"$calls"
"$gm" start
on || fail "start did not persist the request"
grep -qF 'hyprctl eval' "$calls" || fail "compositor did not go through hyprctl eval"
grep -qF 'keyword' "$calls" && fail "used the keyword path the Lua parser rejects"
grep -qF 'allow_tearing = true' "$calls" || fail "eval lua did not enable tearing"
grep -qF 'immediate = true' "$calls" || fail "eval lua did not add the immediate rule"
grep -qE 'pkexec .*ryoku-wifi-powersave off' "$calls" || fail "WiFi helper not asked to disable power-save"
"$gm" status || fail "status reported off while on"

# --- stop: reload + WiFi helper on ------------------------------------------
: >"$calls"
"$gm" stop
on && fail "stop did not clear the request"
grep -qF 'hyprctl reload' "$calls" || fail "stop did not reload to revert the compositor"
grep -qE 'pkexec .*ryoku-wifi-powersave on' "$calls" || fail "WiFi helper not asked to restore power-save"
"$gm" status && fail "status reported on after stop"

# --- toggle flips both ways --------------------------------------------------
"$gm" toggle; on || fail "toggle did not turn on"
"$gm" toggle; on && fail "toggle did not turn off"

# --- no WiFi device: compositor still applies, WiFi is a clean no-op ---------
: >"$calls"
RYOKU_NET_SYSFS="$nonet" "$gm" start
on || fail "start failed on a no-WiFi host"
grep -qF 'hyprctl eval' "$calls" || fail "compositor did not apply on a no-WiFi host"
grep -qF 'ryoku-wifi-powersave' "$calls" && fail "touched WiFi on a host with no WiFi device"
RYOKU_NET_SYSFS="$nonet" "$gm" stop

# --- helper absent: WiFi is skipped even with a WiFi device ------------------
rm -f "$bin/ryoku-wifi-powersave"
: >"$calls"
"$gm" start
grep -qF 'hyprctl eval' "$calls" || fail "compositor did not apply when helper absent"
grep -qF 'ryoku-wifi-powersave' "$calls" && fail "tried to call an absent WiFi helper"
"$gm" stop

echo "game-mode: all checks passed"

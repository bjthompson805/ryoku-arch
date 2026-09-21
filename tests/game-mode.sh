#!/usr/bin/env bash
# fixture test for ryoku-cmd-game-mode (the one-click competitive toggle). stubs
# hyprctl + pkexec on PATH, points state + sysfs scan at a tmp dir, so the real
# compositor + the real wifi radio are never touched. verifies:
#   - toggle lifecycle
#   - compositor goes through `hyprctl eval` (not the keyword path the Lua
#     parser rejects), with tearing + the immediate rule, reverts via reload
#   - wifi power-save delegated to the privileged ryoku-wifi-powersave via
#     pkexec (off on start, on on stop)
#   - clean no-op when there's no wifi device or the helper is missing
#   - the flags.json options (visuals / tearing / wifi) each gate their part of
#     the tune, and `reapply` moves a running tune to the current options
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

# fake sysfs with one wifi device (overridable per-test).
net="$tmp/net"; mkdir -p "$net/wlan0/wireless" "$net/eth0"
nonet="$tmp/nonet"; mkdir -p "$nonet/eth0"

export PATH="$bin:$PATH"
export RYOKU_STATE_PATH="$tmp/state"
export RYOKU_GAMEMODE_STATE_FILE="$tmp/state/game-mode.enabled"
export RYOKU_NET_SYSFS="$net"
export RYOKU_FLAGS_FILE="$tmp/state/flags.json"
export RYOKU_GAMEMODE_WIFI_MARK="$tmp/wifi.mark"
state="$RYOKU_GAMEMODE_STATE_FILE"
flags="$RYOKU_FLAGS_FILE"

fail() { echo "FAIL: $1" >&2; exit 1; }
on() { [[ -f $state ]]; }

"$gm" status && fail "status reported on before any start"

# --- start: compositor via eval + wifi helper off --------------------------
: >"$calls"
"$gm" start
on || fail "start did not persist the request"
grep -qF 'hyprctl eval' "$calls" || fail "compositor did not go through hyprctl eval"
grep -qF 'keyword' "$calls" && fail "used the keyword path the Lua parser rejects"
grep -qF 'allow_tearing = true' "$calls" || fail "eval lua did not enable tearing"
grep -qF 'immediate = true' "$calls" || fail "eval lua did not add the immediate rule"
grep -qE 'pkexec .*ryoku-wifi-powersave off' "$calls" || fail "WiFi helper not asked to disable power-save"
"$gm" status || fail "status reported off while on"

# --- stop: reload + wifi helper on -----------------------------------------
: >"$calls"
"$gm" stop
on && fail "stop did not clear the request"
grep -qF 'hyprctl reload' "$calls" || fail "stop did not reload to revert the compositor"
grep -qE 'pkexec .*ryoku-wifi-powersave on' "$calls" || fail "WiFi helper not asked to restore power-save"
"$gm" status && fail "status reported on after stop"

# --- toggle flips both ways ------------------------------------------------
"$gm" toggle; on || fail "toggle did not turn on"
"$gm" toggle; on && fail "toggle did not turn off"

# --- no wifi device: compositor still applies, wifi is a clean no-op -------
: >"$calls"
RYOKU_NET_SYSFS="$nonet" "$gm" start
on || fail "start failed on a no-WiFi host"
grep -qF 'hyprctl eval' "$calls" || fail "compositor did not apply on a no-WiFi host"
grep -qF 'ryoku-wifi-powersave' "$calls" && fail "touched WiFi on a host with no WiFi device"
RYOKU_NET_SYSFS="$nonet" "$gm" stop

# --- options: each switch gates its own part of the tune ------------------
setflags() { mkdir -p "$tmp/state"; printf '%s\n' "$1" >"$flags"; }
count() { grep -cF -- "$1" "$calls" || true; }

setflags '{"gameModeVisuals": false}'
: >"$calls"
"$gm" start
grep -qF 'allow_tearing = true' "$calls" || fail "visuals off dropped the tearing half too"
grep -qF 'blur' "$calls" && fail "visuals off still stripped blur"
grep -qF 'animations' "$calls" && fail "visuals off still stripped animations"
"$gm" stop

setflags '{"gameModeTearing": false}'
: >"$calls"
"$gm" start
grep -qF 'blur = { enabled = false }' "$calls" || fail "tearing off dropped the visuals half too"
grep -qF 'allow_tearing' "$calls" && fail "tearing off still enabled tearing"
grep -qF 'immediate' "$calls" && fail "tearing off still added the immediate rule"
grep -qF 'vrr' "$calls" && fail "tearing off still set vrr"
"$gm" stop

setflags '{"gameModeVisuals": false, "gameModeTearing": false, "gameModeWifi": false}'
: >"$calls"
"$gm" start
on || fail "start with every option off did not persist the request"
grep -qF 'hyprctl eval' "$calls" && fail "compositor touched with visuals and tearing both off"
grep -qF 'pkexec' "$calls" && fail "wifi touched with the wifi option off"
: >"$calls"
"$gm" stop
grep -qF 'pkexec' "$calls" && fail "stop restored a wifi setting it never changed"

# --- reapply: a running tune follows the options ----------------------------
setflags '{}'
: >"$calls"
"$gm" reapply
[[ -s $calls ]] && fail "reapply while off touched something"

"$gm" start
[[ $(count 'ryoku-wifi-powersave off') == 1 ]] || fail "start did not turn wifi power-save off once"
: >"$calls"
"$gm" reapply
reload_at="$(grep -nF 'hyprctl reload' "$calls" | head -1 | cut -d: -f1)"
eval_at="$(grep -nF 'hyprctl eval' "$calls" | head -1 | cut -d: -f1)"
[[ -n $reload_at && -n $eval_at && $reload_at -lt $eval_at ]] || fail "reapply did not reload then re-eval"
grep -qF 'ryoku-wifi-powersave off' "$calls" && fail "reapply re-saved wifi state it already holds"

setflags '{"gameModeWifi": false}'
: >"$calls"
"$gm" reapply
grep -qE 'pkexec .*ryoku-wifi-powersave on' "$calls" || fail "dropping the wifi option mid-game did not restore power-save"
: >"$calls"
"$gm" stop
grep -qF 'ryoku-wifi-powersave' "$calls" && fail "stop restored wifi twice"

setflags '{}'
"$gm" start
setflags '{"gameModeWifi": false}'
"$gm" reapply
setflags '{}'
: >"$calls"
"$gm" reapply
grep -qE 'pkexec .*ryoku-wifi-powersave off' "$calls" || fail "re-enabling the wifi option mid-game did not turn power-save off"
"$gm" stop
rm -f "$flags"

# --- helper absent: wifi skipped even with a wifi device -------------------
rm -f "$bin/ryoku-wifi-powersave"
: >"$calls"
"$gm" start
grep -qF 'hyprctl eval' "$calls" || fail "compositor did not apply when helper absent"
grep -qF 'ryoku-wifi-powersave' "$calls" && fail "tried to call an absent WiFi helper"
"$gm" stop

echo "game-mode: all checks passed"

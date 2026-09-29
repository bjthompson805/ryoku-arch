#!/usr/bin/env bash
# fixture test for ryoku-charge-limit: the battery popout's charge-limit helper.
# busctl, udevadm, and systemctl are stubbed on PATH, and the sysfs scan + udev
# rule point at a tmp dir = no real battery or upower touched, no root needed.
# covers battery discovery (peripheral cells and mains skipped); that `status`
# reports UPower's threshold properties; that `on`/`off` call
# EnableChargeThreshold on the right device; that `set` writes the rule and
# restarts upower; that `set` rejects anything but an in-range whole number;
# and that `release` lifts the firmware thresholds only when full-when-off is on.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
helper="$here/../system/hardware/power/ryoku-charge-limit"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bin="$tmp/bin"; mkdir -p "$bin"
calls="$tmp/calls"; : >"$calls"

# fake sysfs: the laptop battery, a Bluetooth mouse cell, and the AC adapter.
ps="$tmp/power_supply"
mkdir -p "$ps/BAT1" "$ps/hidpp_battery_0" "$ps/ADP1"
echo Battery >"$ps/BAT1/type"
echo Battery >"$ps/hidpp_battery_0/type"
echo Device >"$ps/hidpp_battery_0/scope"
echo Mains >"$ps/ADP1/type"

# busctl stub: answers the threshold properties, logs every call.
cat >"$bin/busctl" <<EOF
#!/usr/bin/env bash
echo "busctl \$*" >>"$calls"
if [[ \$1 == "get-property" ]]; then
  case "\$5" in
    ChargeThresholdSupported) echo "b true" ;;
    ChargeThresholdEnabled) echo "b true" ;;
    ChargeEndThreshold) echo "u 65" ;;
  esac
fi
exit 0
EOF
for c in udevadm systemctl; do
  printf '#!/usr/bin/env bash\necho "%s $*" >>"%s"\nexit 0\n' "$c" "$calls" >"$bin/$c"
done
chmod +x "$bin"/*

export PATH="$bin:$PATH"
export RYOKU_POWER_SYSFS="$ps"
export RYOKU_CHARGE_LIMIT_RULE="$tmp/61-ryoku-charge-limit.rules"
rule="$RYOKU_CHARGE_LIMIT_RULE"
export RYOKU_CHARGE_LIMIT_FULL_FLAG="$tmp/etc/ryoku/charge-limit-full-when-off"
flag="$RYOKU_CHARGE_LIMIT_FULL_FLAG"

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- status reads UPower's properties off the laptop battery -----------------
out="$("$helper" status)"
grep -qx "supported true" <<<"$out" || fail "status missing supported"
grep -qx "enabled true" <<<"$out" || fail "status missing enabled"
grep -qx "end 65" <<<"$out" || fail "status missing end"
grep -qx "min 50" <<<"$out" || fail "status missing min"
grep -qx "full_when_off false" <<<"$out" || fail "status missing full_when_off"
grep -q "devices/battery_BAT1 " "$calls" || fail "status did not query battery_BAT1"
grep -q "hidpp" "$calls" && fail "status queried a peripheral battery"

# --- on / off toggle EnableChargeThreshold -----------------------------------
: >"$calls"
"$helper" off
grep -q "call org.freedesktop.UPower /org/freedesktop/UPower/devices/battery_BAT1 org.freedesktop.UPower.Device EnableChargeThreshold b false" "$calls" \
  || fail "off did not disable the threshold"
"$helper" on
grep -q "EnableChargeThreshold b true" "$calls" || fail "on did not enable the threshold"

# --- set writes the rule for the laptop battery only, then reloads -----------
: >"$calls"
"$helper" set 70
grep -qx 'SUBSYSTEM=="power_supply", KERNEL=="BAT1", ENV{CHARGE_LIMIT}="65,70"' "$rule" \
  || fail "set did not write the BAT1 rule"
grep -q "hidpp\|ADP1" "$rule" && fail "set wrote a rule for a non-laptop battery"
[[ -e $rule.tmp ]] && fail "set left its temp file behind"
grep -q "udevadm control --reload" "$calls" || fail "set did not reload udev rules"
grep -q "udevadm trigger --subsystem-match=power_supply --action=change" "$calls" || fail "set did not retrigger power_supply"
grep -q "systemctl restart upower" "$calls" || fail "set did not restart upower"

# --- set accepts the range ends and normalizes a leading zero ----------------
"$helper" set 50
grep -q 'CHARGE_LIMIT}="45,50"' "$rule" || fail "set rejected the lower bound"
"$helper" set 100
grep -q 'CHARGE_LIMIT}="95,100"' "$rule" || fail "set rejected the upper bound"
"$helper" set 080
grep -q 'CHARGE_LIMIT}="75,80"' "$rule" || fail "set did not read 080 as 80"

# --- set rejects bad input and leaves the rule alone -------------------------
before="$(cat "$rule")"
for bad in 49 101 "" abc "65; touch $tmp/pwned" 6.5 -70 1000; do
  : >"$calls"
  if "$helper" set "$bad" 2>/dev/null; then
    fail "set accepted '$bad'"
  fi
  [[ $(cat "$rule") == "$before" ]] || fail "set '$bad' changed the rule"
  [[ -s $calls ]] && fail "set '$bad' still ran a command"
done
[[ -e $tmp/pwned ]] && fail "set ran injected input"

# --- no battery: every action fails instead of writing anything --------------
empty="$tmp/empty"; mkdir -p "$empty"
out="$(RYOKU_POWER_SYSFS="$empty" "$helper" status)"
grep -qx "supported false" <<<"$out" || fail "status without a battery did not report unsupported"
RYOKU_POWER_SYSFS="$empty" "$helper" on 2>/dev/null && fail "on without a battery succeeded"
RYOKU_POWER_SYSFS="$empty" "$helper" set 70 2>/dev/null && fail "set without a battery succeeded"

# --- release: a no-op until full-when-off is on ------------------------------
echo 65 >"$ps/BAT1/charge_control_end_threshold"
echo 60 >"$ps/BAT1/charge_control_start_threshold"
echo 80 >"$ps/hidpp_battery_0/charge_control_end_threshold"
"$helper" release || fail "release without the opt-in failed"
[[ $(cat "$ps/BAT1/charge_control_end_threshold") == 65 ]] || fail "release lifted the limit without the opt-in"

# --- full-when-off toggles the flag that status reports ----------------------
"$helper" full-when-off on
[[ -e $flag ]] || fail "full-when-off on did not create the flag"
"$helper" status | grep -qx "full_when_off true" || fail "status did not report full_when_off on"
"$helper" full-when-off bogus 2>/dev/null && fail "full-when-off accepted a bad argument"

# --- release with the opt-in: end to 100, start to 0, laptop battery only -----
"$helper" release || fail "release failed"
[[ $(cat "$ps/BAT1/charge_control_end_threshold") == 100 ]] || fail "release did not raise the end threshold"
[[ $(cat "$ps/BAT1/charge_control_start_threshold") == 0 ]] || fail "release did not lower the start threshold"
[[ $(cat "$ps/hidpp_battery_0/charge_control_end_threshold") == 80 ]] || fail "release touched a peripheral battery"

# --- end-only hardware (no start threshold file) still releases --------------
rm "$ps/BAT1/charge_control_start_threshold"
echo 65 >"$ps/BAT1/charge_control_end_threshold"
"$helper" release || fail "release failed without a start threshold"
[[ $(cat "$ps/BAT1/charge_control_end_threshold") == 100 ]] || fail "release skipped end-only hardware"

"$helper" full-when-off off
[[ -e $flag ]] && fail "full-when-off off did not remove the flag"

echo "charge-limit: all checks passed"

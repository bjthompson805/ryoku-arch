#!/usr/bin/env bash
# fixture test for ryoku-cmd-caffeine's inhibitor scope. systemd-run, systemctl,
# pgrep, and pkill are stubbed on PATH around a fake "running inhibitor" file, and
# state + flags point at a tmp dir, so no real inhibitor is taken. verifies:
#   - the default holds idle + sleep
#   - keepAwakeScreen=false in flags.json narrows a re-run `start` to sleep only
#   - switching back widens it again, and the old inhibitor is replaced not stacked
#   - stop releases it
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cc="$here/../ryoku/hyprland/scripts/ryoku-cmd-caffeine"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bin="$tmp/bin"; mkdir -p "$bin"
running="$tmp/running"
calls="$tmp/calls.log"

cat >"$bin/systemd-run" <<EOF2
#!/usr/bin/env bash
echo "systemd-run \$*" >>"$calls"
what=""
for a in "\$@"; do [[ \$a == --what=* ]] && what="\$a"; done
echo "systemd-inhibit \$what --who=Ryoku --why=Ryoku caffeine mode bash -c exec -a ryoku-caffeine-inhibit sleep infinity" >"$running"
EOF2
cat >"$bin/systemctl" <<EOF2
#!/usr/bin/env bash
case "\$*" in
  *is-active*) [[ -f "$running" ]] ;;
  *stop*) rm -f "$running" ;;
esac
EOF2
cat >"$bin/pgrep" <<EOF2
#!/usr/bin/env bash
[[ -f "$running" ]] && grep -Eq -- "\$2" "$running"
EOF2
cat >"$bin/pkill" <<EOF2
#!/usr/bin/env bash
rm -f "$running"
EOF2
chmod +x "$bin"/*

export PATH="$bin:$PATH"
export RYOKU_STATE_PATH="$tmp/state"
export RYOKU_CAFFEINE_STATE_FILE="$tmp/state/caffeine.enabled"
export RYOKU_CAFFEINE_LOCK_FILE="$tmp/caffeine.lock"
export RYOKU_FLAGS_FILE="$tmp/state/flags.json"
mkdir -p "$tmp/state"
flags="$RYOKU_FLAGS_FILE"

fail() { echo "FAIL: $1" >&2; exit 1; }
held() { grep -oE -- '--what=[a-z:]+' "$running" 2>/dev/null || true; }

"$cc" status && fail "status reported active before any start"

"$cc" start
[[ $(held) == "--what=idle:sleep" ]] || fail "default did not hold idle + sleep (got: $(held))"
"$cc" status || fail "status reported inactive while held"

printf '{"keepAwakeScreen": false}\n' >"$flags"
: >"$calls"
"$cc" start
[[ $(held) == "--what=sleep" ]] || fail "keepAwakeScreen=false did not narrow to sleep only (got: $(held))"
grep -qF 'systemd-run' "$calls" || fail "re-run start did not replace the inhibitor"
"$cc" status || fail "status reported inactive after narrowing"

: >"$calls"
"$cc" start
grep -qF 'systemd-run' "$calls" && fail "start with an unchanged option restarted the inhibitor"

printf '{"keepAwakeScreen": true}\n' >"$flags"
"$cc" start
[[ $(held) == "--what=idle:sleep" ]] || fail "keepAwakeScreen=true did not widen back to idle + sleep (got: $(held))"

rm -f "$flags"
"$cc" stop
"$cc" status && fail "status reported active after stop"
[[ -f $RYOKU_CAFFEINE_STATE_FILE ]] && fail "stop did not clear the request"

echo "caffeine: all checks passed"

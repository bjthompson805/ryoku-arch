#!/usr/bin/env bash
# Deploy the handful of Ryoku files that have to live outside $HOME: root-owned
# system paths a dev checkout has no user-space equivalent for. Everything else
# (the CLI, shell/hub/rashin daemons, Hyprland plugins, Ryoku.Blobs, quickshell
# config) is handled by ryoku/shell/deploy.sh with no root needed.
#
# Idempotent: safe to re-run after every git pull. Sourced straight from this
# checkout -- the same files ryoku-desktop's PKGBUILD packages, just placed
# directly instead of going through pacman.
#
#   sudo system/deploy-root.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "deploy-root.sh: must run as root (sudo)" >&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/.." && pwd)"
say() { printf '  %s\n' "$*"; }

# WirePlumber Bluetooth codec policy (mSBC calls, hi-fi A2DP). User-overridable
# from ~/.config/wireplumber/wireplumber.conf.d/.
install -Dm644 "$repo/ryoku/apps/wireplumber/wireplumber.conf.d/51-ryoku-bluetooth.conf" \
  /etc/wireplumber/wireplumber.conf.d/51-ryoku-bluetooth.conf
say "installed wireplumber bluetooth policy"

# Windows dual-boot: cross-drive detector + the limine-entry-tool post.d hook
# that re-asserts the chainload entry whenever the boot menu regenerates.
install -Dm755 "$repo/system/boot/limine/ryoku-windows-entry" /usr/bin/ryoku-windows-entry
install -Dm755 "$repo/system/boot/limine/45-ryoku-windows" /etc/boot/hooks/post.d/45-ryoku-windows
say "installed Windows dual-boot hook"

# GPU primary-renderer udev rule: boot-stable /dev/dri/ryoku-gpu-* symlinks
# that ryoku-gpu pins via AQ_DRM_DEVICES. /etc, not /usr/lib: this file is no
# longer pacman-tracked, and /etc/udev/rules.d is udev's own local-override
# location, read ahead of /usr/lib/udev/rules.d.
install -Dm644 "$repo/system/hardware/gpu/90-ryoku-gpu.rules" /etc/udev/rules.d/90-ryoku-gpu.rules
udevadm control --reload-rules
udevadm trigger
say "installed GPU udev rule and reloaded udev"

# Game Mode wifi power-save. The polkit rule is pinned to the exact path
# /usr/bin/ryoku-wifi-powersave (see the rule's own comment), so the helper
# must live there -- unlike deploy.sh's other hardware helpers, a $HOME copy
# would never get the passwordless grant, so deploy.sh never installs this one.
install -Dm755 "$repo/system/hardware/network/ryoku-wifi-powersave" /usr/bin/ryoku-wifi-powersave
install -Dm644 "$repo/system/hardware/network/49-ryoku-wifi-powersave.rules" \
  /etc/polkit-1/rules.d/49-ryoku-wifi-powersave.rules
say "installed wifi power-save helper and polkit rule"

# Webcam kill-switch. Same reasoning as the wifi helper above: the polkit
# rule is pinned to /usr/bin/ryoku-webcam, so deploy.sh never installs this
# one to a $HOME bindir.
install -Dm755 "$repo/system/hardware/camera/ryoku-webcam" /usr/bin/ryoku-webcam
install -Dm644 "$repo/system/hardware/camera/50-ryoku-webcam.rules" \
  /etc/polkit-1/rules.d/50-ryoku-webcam.rules
say "installed webcam kill-switch helper and polkit rule"

# markdown-writer: not part of upstream's deploy-root.sh, added for this fork.
# Fetches and installs the latest GitHub release every run, so re-running this
# script also keeps it current -- see system/extras/ryoku-pkg-markdown-writer.
# Placed last so a network hiccup here never blocks the root-owned installs above.
"$repo/system/extras/ryoku-pkg-markdown-writer"
say "installed markdown-writer"

say "done. re-run after every git pull to pick up changes to these files."

#!/usr/bin/env bash
# preflight: refuse to start unless we're root, in UEFI mode, and pointed at a
# big-enough disk. under dry-run the checks just narrate and never abort, so the
# flow can be exercised on a dev box with no real target disk.

# min target disk: 32 GiB.
RYOKU_MIN_DISK_BYTES=34359738368

ryoku_preflight() {
  # dry-run never touches the machine, so narrate and return; we'd just probe
  # hardware that might not be on the dev box.
  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    log "preflight: would require root, UEFI (/sys/firmware/efi), and $RYOKU_DISK >= 32 GiB"
    log "preflight: would require the repo payload at $RYOKU_REPO and a working DNS resolver before any disk write"
    log "preflight: ok (profile=$RYOKU_PROFILE, strategy=$RYOKU_DISK_STRATEGY, encrypt=${RYOKU_ENCRYPT:-0})"
    return 0
  fi

  # root: partitioning, mkfs, pacstrap, arch-chroot all need it.
  [[ $EUID -eq 0 ]] || die "must run as root"

  # UEFI: boot chain is Limine + an ESP.
  [[ -d /sys/firmware/efi ]] || die "not booted in UEFI mode (/sys/firmware/efi missing)"

  # target disk has to exist and be a block device.
  [[ -b $RYOKU_DISK ]] || die "target $RYOKU_DISK is not a block device"

  # target disk has to be >= 32 GiB.
  local size
  size=$(blockdev --getsize64 "$RYOKU_DISK")
  (( size >= RYOKU_MIN_DISK_BYTES )) || \
    die "$RYOKU_DISK is $(( size / 1024 / 1024 / 1024 )) GiB; need at least 32 GiB"

  # the pacstrap set and the whole desktop payload live under $RYOKU_REPO; without
  # it pacstrap dies at "missing package list". check HERE, before the disk is
  # wiped, so a missing or mispointed payload aborts with the disk intact instead
  # of after the wipe.
  local base_list="$RYOKU_REPO/system/packages/base.packages"
  [[ -f $base_list ]] || die "repo payload missing: $base_list not found (RYOKU_REPO=$RYOKU_REPO). The installer image is incomplete or RYOKU_REPO is wrong; the disk has not been touched."

  log "preflight: $RYOKU_DISK is $(( size / 1024 / 1024 / 1024 )) GiB"
  log "preflight: ok (profile=$RYOKU_PROFILE, strategy=$RYOKU_DISK_STRATEGY, encrypt=${RYOKU_ENCRYPT:-0})"
}

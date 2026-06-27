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

  log "preflight: $RYOKU_DISK is $(( size / 1024 / 1024 / 1024 )) GiB"
  log "preflight: ok (profile=$RYOKU_PROFILE, strategy=$RYOKU_DISK_STRATEGY, encrypt=${RYOKU_ENCRYPT:-0})"
}

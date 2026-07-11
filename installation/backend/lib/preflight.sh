#!/usr/bin/env bash
# preflight: refuse to start unless we're root, in UEFI mode with Secure Boot
# off, and pointed at a big-enough WHOLE disk. under dry-run the checks just
# narrate and never abort, so the flow can be exercised on a dev box with no
# real target disk.

# min target disk: 32 GiB.
RYOKU_MIN_DISK_BYTES=34359738368

# ryoku_secureboot_enabled: true when firmware Secure Boot is currently ON. the
# SecureBoot efivar payload is a 4-byte attribute prefix + a 1-byte value; the
# last byte is the state (1 = enabled). an absent var reads as not enabled.
# RYOKU_SB_VAR overrides the efivar path (tests only).
ryoku_secureboot_enabled() {
  local var=${RYOKU_SB_VAR:-/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c}
  [[ -e $var ]] || return 1
  local last
  last=$(tail -c1 "$var" 2>/dev/null | od -An -tu1 2>/dev/null | tr -d '[:space:]' || true)
  [[ $last == 1 ]]
}

ryoku_preflight() {
  # dry-run never touches the machine, so narrate and return; we'd just probe
  # hardware that might not be on the dev box.
  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    log "preflight: would require root, UEFI (/sys/firmware/efi) with Secure Boot off (override RYOKU_ALLOW_SECUREBOOT=1), and $RYOKU_DISK a whole disk >= 32 GiB"
    log "preflight: would log the disk's logical sector size (blockdev --getss)"
    log "preflight: would require the repo payload at $RYOKU_REPO and a working DNS resolver before any disk write"
    log "preflight: ok (profile=$RYOKU_PROFILE, strategy=$RYOKU_DISK_STRATEGY, encrypt=${RYOKU_ENCRYPT:-0})"
    return 0
  fi

  # root: partitioning, mkfs, pacstrap, arch-chroot all need it.
  [[ $EUID -eq 0 ]] || die "must run as root"

  # UEFI: boot chain is Limine + an ESP.
  [[ -d /sys/firmware/efi ]] || die "not booted in UEFI mode (/sys/firmware/efi missing)"

  # Secure Boot: Limine ships unsigned, so a machine enforcing Secure Boot
  # refuses to run it. Fail HERE with firmware guidance instead of installing a
  # system that then dies at a security violation on first boot.
  # RYOKU_ALLOW_SECUREBOOT=1 overrides (e.g. the user enrolled their own keys).
  if [[ ${RYOKU_ALLOW_SECUREBOOT:-} != 1 ]] && ryoku_secureboot_enabled; then
    die "Secure Boot is enabled and Limine is unsigned, so the installed system will not boot. Disable Secure Boot in your firmware (UEFI) setup screen, then retry. Set RYOKU_ALLOW_SECUREBOOT=1 only if you have enrolled your own keys."
  fi

  # target disk has to exist and be a block device.
  [[ -b $RYOKU_DISK ]] || die "target $RYOKU_DISK is not a block device"

  # target must be a WHOLE disk, not a partition: repartitioning a partition
  # device is nonsense and 'whole' would wipe its parent's table. lsblk TYPE
  # separates a disk from a part/lvm/crypt node.
  local dtype
  dtype=$(lsblk -dno TYPE "$RYOKU_DISK" 2>/dev/null || true)
  [[ $dtype == disk ]] || die "target $RYOKU_DISK is a '${dtype:-unknown}', not a whole disk. Pass a disk (e.g. /dev/nvme0n1 or /dev/sda), not a partition."

  # target disk has to be >= 32 GiB.
  local size
  size=$(blockdev --getsize64 "$RYOKU_DISK")
  (( size >= RYOKU_MIN_DISK_BYTES )) || \
    die "$RYOKU_DISK is $(( (size + 536870912) / 1073741824 )) GiB; need at least 32 GiB"

  # the pacstrap set and the whole desktop payload live under $RYOKU_REPO; without
  # it pacstrap dies at "missing package list". check HERE, before the disk is
  # wiped, so a missing or mispointed payload aborts with the disk intact instead
  # of after the wipe.
  local base_list="$RYOKU_REPO/system/packages/base.packages"
  [[ -f $base_list ]] || die "repo payload missing: $base_list not found (RYOKU_REPO=$RYOKU_REPO). The installer image is incomplete or RYOKU_REPO is wrong; the disk has not been touched."

  log "preflight: $RYOKU_DISK is $(( size / 1024 / 1024 / 1024 )) GiB, $(blockdev --getss "$RYOKU_DISK")-byte logical sectors"
  log "preflight: ok (profile=$RYOKU_PROFILE, strategy=$RYOKU_DISK_STRATEGY, encrypt=${RYOKU_ENCRYPT:-0})"
}

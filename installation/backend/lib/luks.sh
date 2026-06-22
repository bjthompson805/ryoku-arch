#!/usr/bin/env bash
# shellcheck shell=bash
# Optional LUKS2 encryption of the root partition. When RYOKU_ENCRYPT=1 the root
# partition is formatted as a LUKS2 container and opened as /dev/mapper/root, so
# the filesystem lives on the mapper device. Always sets ROOT_DEV; sets LUKS_PART
# when encrypting (used later for crypttab and the kernel cmdline).

ryoku_luks() {
  if [[ ${RYOKU_ENCRYPT:-} != 1 ]]; then
    ROOT_DEV=$ROOT_PART
    log "encryption: off (root on $ROOT_DEV)"
    return 0
  fi
  [[ -n ${RYOKU_LUKS_PASSPHRASE:-} ]] || die "RYOKU_ENCRYPT=1 but RYOKU_LUKS_PASSPHRASE is unset"

  # Hard safety: LUKS must only ever format ROOT_PART. If ROOT_PART is unset,
  # equals the whole disk, or matches the reused ESP, the partition step set
  # something dangerous and we refuse to luksFormat. Better to abort than to
  # luksFormat a Windows partition or the ESP.
  [[ -n ${ROOT_PART:-} ]] || die "LUKS: ROOT_PART is unset; refusing to format."
  [[ $ROOT_PART != "${RYOKU_DISK:-}" ]] || die "LUKS: refusing to format whole disk ($ROOT_PART); ROOT_PART must be a partition."
  [[ $ROOT_PART != "${ESP_DEV:-}" ]] || die "LUKS: refusing to format ESP ($ROOT_PART); ROOT_PART must be the new root partition."

  LUKS_PART=$ROOT_PART
  log "encryption: LUKS2 on $LUKS_PART -> /dev/mapper/root"

  # Passphrase travels on stdin only, never on the command line or in any log.
  printf '%s' "$RYOKU_LUKS_PASSPHRASE" | run_secret \
    "cryptsetup luksFormat --type luks2 --batch-mode $LUKS_PART (passphrase via stdin)" \
    cryptsetup luksFormat --type luks2 --batch-mode "$LUKS_PART"
  printf '%s' "$RYOKU_LUKS_PASSPHRASE" | run_secret \
    "cryptsetup open $LUKS_PART root (passphrase via stdin)" \
    cryptsetup open "$LUKS_PART" root

  ROOT_DEV=/dev/mapper/root
}

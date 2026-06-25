#!/usr/bin/env bash
# Partition the target disk. Two strategies, both setting ESP_DEV and ROOT_PART:
#
#   whole     Wipe the disk and lay a fresh GPT: an EFI System Partition plus a
#             root that takes the rest. Destroys everything on the disk.
#   alongside Keep the existing partitions for dual-booting (e.g. Windows on the
#             same drive): reuse the existing EFI System Partition and create the
#             Ryoku root in the largest free region. Nothing existing is wiped or
#             moved, so the user makes room first by shrinking Windows.

# Largest contiguous free region 'alongside' must find for the Ryoku root: a base
# system closure plus the swapfile, which lives inside root (@swap subvolume).
ryoku_min_root_gib() { echo $(( 15 + ${RYOKU_SWAP_GIB:-0} )); }

ryoku_partition() {
  case ${RYOKU_DISK_STRATEGY:-} in
    whole)     ryoku_partition_whole ;;
    alongside) ryoku_partition_alongside ;;
    '')        die "RYOKU_DISK_STRATEGY is required (use 'whole' or 'alongside'); refusing to wipe disk on empty strategy." ;;
    *)         die "disk strategy '$RYOKU_DISK_STRATEGY' not supported (use 'whole' or 'alongside')" ;;
  esac
}

# ryoku_release_disk frees the target disk so the wipe cannot fail with "Device
# or resource busy". On the live medium the target is often held by something we
# did not put there: a partition auto-mounted by udisks, a still-mounted /mnt or
# an open LUKS/dm mapper left by a previous failed run, or auto-enabled swap. The
# kernel refuses to re-read or wipe a disk while ANY child partition is held, so
# tear it down from the leaves up: unmount every mountpoint, swapoff every swap,
# close device-mapper/LUKS holders, deactivate LVM, stop md RAID, then settle.
# Scoped to the disk's own tree (lsblk "$disk"), so it never touches the live
# medium's mounts or mappers. Best-effort and idempotent: a clean disk is a no-op.
ryoku_release_disk() {
  local disk=$1
  [[ -b $disk || -n ${RYOKU_DRYRUN:-} ]] || return 0
  log "releasing $disk before wipe (unmount, swapoff, close holders)"

  local name mp
  # Unmount every mountpoint on the disk or its partitions, deepest first (a
  # nested mount pins its parent); lazy-unmount as a fallback so a busy mount
  # still releases the device.
  while IFS= read -r mp; do
    [[ -n $mp ]] || continue
    run_sh "umount -R -- '$mp' 2>/dev/null || umount -l -- '$mp' 2>/dev/null || true"
  done < <(lsblk -nrpo MOUNTPOINT "$disk" 2>/dev/null | awk 'NF' | sort -r)

  # Disable any swap that lives on the disk.
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    run_sh "swapoff -- '$name' 2>/dev/null || true"
  done < <(lsblk -nrpo NAME,FSTYPE "$disk" 2>/dev/null | awk '$2=="swap"{print $1}')

  # Close device-mapper holders on the disk (LUKS/crypt, LVM, plain dm), leaves
  # first so a stacked setup unwinds. cryptsetup for crypt, dmsetup for the rest.
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    run_sh "cryptsetup close -- '$name' 2>/dev/null || dmsetup remove --force -- '$name' 2>/dev/null || true"
  done < <(lsblk -nrpo NAME,TYPE "$disk" 2>/dev/null | awk '$2=="crypt"||$2=="lvm"||$2=="dm"{print $1}' | tac)

  # Deactivate any LVM volume group with a physical volume on the disk or one of
  # its partitions. Feed pvs the exact devices from the disk's own tree, never a
  # "${disk}*" glob: /dev/sda* would also match /dev/sdaa on a many-disk box and
  # could deactivate a VG that lives only on another disk.
  if command -v pvs >/dev/null 2>&1; then
    local -a devs=()
    while IFS= read -r name; do
      [[ -n $name ]] && devs+=("$name")
    done < <(lsblk -nrpo NAME "$disk" 2>/dev/null)
    if (( ${#devs[@]} > 0 )); then
      while IFS= read -r name; do
        [[ -n $name ]] || continue
        run_sh "vgchange -an -- '$name' 2>/dev/null || true"
      done < <(pvs --noheadings -o vg_name "${devs[@]}" 2>/dev/null | awk 'NF' | sort -u)
    fi
  fi

  # Stop any md RAID array with a member on the disk.
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    run_sh "mdadm --stop -- '$name' 2>/dev/null || true"
  done < <(lsblk -nrpo NAME,TYPE "$disk" 2>/dev/null | awk '$2 ~ /raid/{print $1}' | tac)

  run_sh 'udevadm settle 2>/dev/null || true'
}

# ryoku_wipe_signatures clears the signatures from a device, retried: right after
# sgdisk zaps the GPT the kernel can still briefly report the device busy while
# it drops the stale table, even with no holders left. Settle and retry; the
# final attempt runs through run() so a real failure still aborts the install
# loudly (and is printed, not executed, under dry-run).
ryoku_wipe_signatures() {
  local target=$1
  if [[ -z ${RYOKU_DRYRUN:-} ]]; then
    for _ in 1 2; do
      wipefs --all "$target" 2>/dev/null && return 0
      udevadm settle 2>/dev/null || true
      sleep 1
    done
  fi
  run wipefs --all "$target"
}

ryoku_partition_whole() {
  local disk=$RYOKU_DISK
  local esp_end=$(( 1 + RYOKU_ESP_GIB ))   # MiB offset 1 -> end of ESP

  # Destructive-wipe guard: refuse to zap a disk that already holds partitions
  # (e.g. a Windows install) unless the caller has explicitly acknowledged the
  # wipe. The TUI sets RYOKU_WIPE_CONFIRMED=1 only after the typed "ERASE"
  # acknowledgement on the Review screen; a truly blank disk proceeds without
  # the token so a fresh install is not gated on a second confirmation.
  if [[ ${RYOKU_WIPE_CONFIRMED:-} != 1 ]] && ryoku_disk_populated "$disk"; then
    die "refusing to wipe $disk: it already holds partitions and RYOKU_WIPE_CONFIRMED is not set. Pick 'alongside' to keep them, or set RYOKU_WIPE_CONFIRMED=1 to wipe explicitly."
  fi

  log "partitioning $disk (whole disk, GPT: ${RYOKU_ESP_GIB}GiB ESP + root)"

  # Free the disk before touching it: on the live medium the target may be held
  # by an auto-mounted partition (udisks), leftover state from a previous run, or
  # active swap. While a child holds the disk, sgdisk/wipefs fail "Device or
  # resource busy".
  ryoku_release_disk "$disk"

  # Destroy the partition table, then re-read so the kernel drops the now-stale
  # partitions before wipefs probes the bare disk.
  run sgdisk --zap-all "$disk"
  run partprobe "$disk"
  run_sh 'udevadm settle 2>/dev/null || true'
  ryoku_wipe_signatures "$disk"

  # Fresh GPT: partition 1 = ESP (EF00 == GPT 'esp' flag), partition 2 = root.
  run parted --script "$disk" mklabel gpt
  run parted --script "$disk" mkpart ESP fat32 1MiB "${esp_end}GiB"
  run parted --script "$disk" set 1 esp on
  run parted --script "$disk" mkpart root "${esp_end}GiB" 100%

  # Let the kernel re-read the new table before we touch the partitions.
  run partprobe "$disk"
  run_sh 'udevadm settle || true'

  ESP_DEV=$(part_dev "$disk" 1)
  ROOT_PART=$(part_dev "$disk" 2)

  # A fresh GPT can lay these partitions over an older layout, so a stale signature
  # (an old LUKS2 header, a previous btrfs) may still sit at the start of each one.
  # The whole-disk wipefs above does not reach into partition space, so clear the
  # new partitions directly. Otherwise blkid reports the old type (e.g. crypto_LUKS)
  # and the later mount fails with "unknown filesystem type".
  run wipefs --all "$ESP_DEV"
  run wipefs --all "$ROOT_PART"
  log "ESP=$ESP_DEV root partition=$ROOT_PART"
}

ryoku_partition_alongside() {
  local disk=$RYOKU_DISK
  log "partitioning $disk (alongside existing OS: reuse ESP, root in free space, nothing wiped)"

  # Under dry-run the disk may not exist; advertise what we would do and pick
  # plausible device names so the rest of the flow can be exercised.
  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    log "DRYRUN: would require GPT, an existing ESP, and >= $(ryoku_min_root_gib)GiB contiguous free"
    local maxnum
    maxnum=$(ryoku_max_partnum "$disk" || true)
    (( maxnum > 0 )) || maxnum=3   # disk absent on a dev box: assume a typical Windows layout (ESP+MSR+C:)
    ESP_DEV=$(part_dev "$disk" 1)
    ROOT_PART=$(part_dev "$disk" "$(( maxnum + 1 ))")
    log "DRYRUN: ESP=$ESP_DEV (reused) new root partition=$ROOT_PART"
    return 0
  fi

  # UEFI dual-boot needs a GPT label; refuse MBR rather than guess at a remap.
  local pttype
  pttype=$(blkid -o value -s PTTYPE "$disk" 2>/dev/null || true)
  [[ $pttype == gpt ]] || die "alongside needs a GPT disk; $disk has '${pttype:-no}' partition table. Use whole-disk, or convert to GPT."

  # Reuse the existing EFI System Partition (where the Windows bootloader lives),
  # so Limine and the Windows boot manager share one ESP.
  ESP_DEV=$(ryoku_find_esp "$disk")
  [[ -n $ESP_DEV ]] || die "alongside found no EFI System Partition on $disk. A UEFI Windows install has one; if this disk has none, use whole-disk."
  log "reusing existing ESP: $ESP_DEV"

  # Need a contiguous free region big enough for the Ryoku root. The user makes
  # room by shrinking Windows first (safest done from Windows Disk Management).
  local free_gib min_gib
  free_gib=$(( $(ryoku_largest_free_mib "$disk") / 1024 ))
  min_gib=$(ryoku_min_root_gib)
  (( free_gib >= min_gib )) || die "not enough free space on $disk: ${free_gib}GiB contiguous free, need >= ${min_gib}GiB. Shrink the Windows partition first, then retry."
  log "largest free region: ${free_gib}GiB (need >= ${min_gib}GiB)"

  # Snapshot the pre-existing partition set so we can prove (after sgdisk) that
  # the new root landed in free space without overwriting any existing partition.
  local -a pre_parts=()
  local pre_max p
  while IFS= read -r p; do
    [[ -n $p ]] && pre_parts+=("$p")
  done < <(ryoku_partitions "$disk")
  pre_max=$(ryoku_max_partnum "$disk")
  [[ $pre_max =~ ^[0-9]+$ ]] || die "alongside could not read existing partition numbers on $disk (sgdisk -p failed); refusing to proceed."

  # Create the root in the largest free block. sgdisk start/end of 0 default to
  # the start and end of the largest aligned free region, so only free space is
  # used; the existing partitions are never touched.
  local newnum=$(( pre_max + 1 ))

  # Guard: the next slot must be strictly higher than every existing partition
  # number. A stale or empty sgdisk -p (pre_max=0) on a disk that actually holds
  # a partition 1 would otherwise direct sgdisk -n 1:0:0 to overwrite it.
  for p in "${pre_parts[@]}"; do
    local pn
    pn=$(part_num "$p")
    (( pn < newnum )) || die "alongside refused to write partition $newnum: existing $p (number $pn) is in the way."
  done

  run sgdisk -n "${newnum}:0:0" -t "${newnum}:8300" -c "${newnum}:ryoku" "$disk"
  run partprobe "$disk"
  run_sh 'udevadm settle || true'

  ROOT_PART=$(part_dev "$disk" "$newnum")

  # Hard safety: ROOT_PART must be a NEW partition that did not exist before
  # sgdisk, must not be the disk itself, and must not be the reused ESP. Any of
  # these would mean we are about to wipefs an existing OS partition.
  [[ $ROOT_PART != "$disk" ]]    || die "alongside ROOT_PART resolves to disk $disk; refusing wipefs."
  [[ $ROOT_PART != "$ESP_DEV" ]] || die "alongside ROOT_PART matches reused ESP $ESP_DEV; refusing wipefs."
  for p in "${pre_parts[@]}"; do
    [[ $p != "$ROOT_PART" ]] || die "alongside ROOT_PART=$ROOT_PART existed before sgdisk; refusing wipefs of an existing partition."
  done
  [[ -b $ROOT_PART ]] || die "alongside created partition $newnum but $ROOT_PART is not a block device"

  # ROOT_PART's parent must be the target disk: lsblk -no PKNAME prints the kernel
  # name of the parent disk (e.g. nvme0n1). A mismatch would mean part_dev built
  # a path on a different device; abort rather than wipefs the wrong thing.
  local parent disk_base
  parent=$(lsblk -no PKNAME "$ROOT_PART" 2>/dev/null | head -n1)
  disk_base=${disk##*/}
  [[ $parent == "$disk_base" ]] || die "alongside ROOT_PART=$ROOT_PART parent='$parent' does not match disk '$disk_base'; refusing wipefs."

  # Clear any stale signature in the NEW partition only (never the disk or ESP),
  # so a leftover LUKS/btrfs header at this offset cannot fail the later mount.
  run wipefs --all "$ROOT_PART"
  log "ESP=$ESP_DEV (reused) root partition=$ROOT_PART"
}

# ryoku_find_esp prints the first EFI System Partition device on the disk (GPT
# type GUID c12a7328-f81f-11d2-ba4b-00a0c93ec93b), or nothing.
ryoku_find_esp() {
  local disk=$1 part type
  while read -r part; do
    [[ -n $part ]] || continue
    type=$(lsblk -dno PARTTYPE "$part" 2>/dev/null || true)
    [[ ${type,,} == c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]] && { printf '%s' "$part"; return 0; }
  done < <(ryoku_partitions "$disk")
  return 1
}

# ryoku_partitions lists the partition device paths on a disk, in table order.
ryoku_partitions() {
  lsblk -lnpo NAME,TYPE "$1" 2>/dev/null | awk '$2=="part"{print $1}'
}

# ryoku_disk_populated returns 0 (true) when $1 has at least one partition we can
# see, 1 only when the disk is visible AND has zero partitions. If the disk can
# not be read (missing device, broken GPT, no lsblk) we return 0 so the wipe
# guard fails closed under uncertainty: better to abort than wipe a disk we did
# not fully introspect.
ryoku_disk_populated() {
  local disk=$1
  lsblk -dno NAME "$disk" >/dev/null 2>&1 || return 0
  local n
  n=$(lsblk -lnpo NAME,TYPE "$disk" 2>/dev/null | awk '$2=="part"' | wc -l)
  (( n > 0 ))
}

# ryoku_max_partnum prints the highest partition number on the disk (0 if none).
ryoku_max_partnum() {
  sgdisk -p "$1" 2>/dev/null | awk '/^[[:space:]]+[0-9]+[[:space:]]/{n=$1} END{print n+0}'
}

# ryoku_largest_free_mib prints the size (MiB) of the largest contiguous free
# region on the disk, parsed from parted's machine-readable free-space listing.
ryoku_largest_free_mib() {
  parted -ms "$1" unit MiB print free 2>/dev/null \
    | awk -F: '$0 ~ /free;[[:space:]]*$/ { s=$4; sub(/MiB/,"",s); if (s+0>m) m=s+0 } END { printf "%d\n", m+0 }'
}

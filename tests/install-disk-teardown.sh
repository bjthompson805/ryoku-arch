#!/usr/bin/env bash
# Fixture test for ryoku_release_disk (installation/backend/lib/disk.sh): the
# pre-wipe teardown that frees a busy target disk so wipefs/sgdisk cannot fail
# with "Device or resource busy". Runs in dry-run with a mocked lsblk, so it
# asserts the teardown PLAN (the commands it would run, in order) with no real
# devices touched.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$here/.."
fail() { echo "FAIL: $1" >&2; exit 1; }

# Run ryoku_release_disk against a mocked block tree, capturing the dry-run plan.
release() {
  RYOKU_DRYRUN=1 ROOT="$root" MOCK="$1" bash -c '
    source "$ROOT/installation/backend/lib/common.sh"
    source "$ROOT/installation/backend/lib/disk.sh"
    eval "$MOCK"
    ryoku_release_disk /dev/nvme0n1
  '
}

# --- busy disk: mounts (incl. a udisks auto-mount), swap, and a LUKS holder ----
busy='lsblk() {
  case "$*" in
    *MOUNTPOINT*)  printf "/mnt\n/run/media/u/DATA\n\n" ;;
    *NAME,FSTYPE*) printf "/dev/nvme0n1p3 swap\n/dev/nvme0n1p1 vfat\n" ;;
    *NAME,TYPE*)   printf "/dev/nvme0n1 disk\n/dev/nvme0n1p2 part\n/dev/mapper/cr crypt\n" ;;
  esac
}'
out="$(release "$busy")"

grep -qF "umount -R -- '/mnt'" <<<"$out" || fail "did not unmount /mnt"
grep -qF "umount -R -- '/run/media/u/DATA'" <<<"$out" || fail "did not unmount the udisks auto-mount"
grep -qF "swapoff -- '/dev/nvme0n1p3'" <<<"$out" || fail "did not swapoff the swap partition"
grep -qF "swapoff -- '/dev/nvme0n1p1'" <<<"$out" && fail "swapoff hit the non-swap vfat partition"
grep -qF "cryptsetup close -- '/dev/mapper/cr'" <<<"$out" || fail "did not close the LUKS/dm holder"
grep -qF "udevadm settle" <<<"$out" || fail "did not settle udev"

# Deepest mount must be released before its parent (the udisks mount before /mnt).
first_umount="$(grep 'umount -R' <<<"$out" | head -n1)"
[[ $first_umount == *"/run/media/u/DATA"* ]] || fail "unmount order is not deepest-first (got: $first_umount)"

# --- clean disk: no holders -> a quiet no-op (no destructive actions) ----------
out="$(release 'lsblk() { printf "\n"; }')"
grep -qF 'releasing /dev/nvme0n1' <<<"$out" || fail "missing the releasing log line"
grep -qE "umount -R|swapoff --|cryptsetup close --|dmsetup remove|vgchange -an|mdadm --stop" <<<"$out" \
  && fail "acted on a clean disk that has no holders"

echo "install-disk-teardown: all checks passed"

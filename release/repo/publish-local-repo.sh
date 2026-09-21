#!/usr/bin/env bash
# Publish a repo staged by build-local-repo.sh into /var/lib/ryoku/repo, as root:
# swap the package set in whole, and record what it was built from (the commit,
# the versions of the ABI-coupled system packages, and a generation counter that
# keeps versions increasing), plus, when given, whose checkout it came from.
#
# ryoku-desktop installs a copy to /usr/lib/ryoku/publish-local-repo, so the
# automatic rebuild after a system upgrade runs root-owned code, not a script
# out of the user's writable checkout.
#
#   publish-local-repo.sh <staging> [--owner <user> --checkout <path>]
#
# env overrides:
#   RYOKU_LOCAL_REPO   where the repo is published (default: /var/lib/ryoku/repo)
set -euo pipefail

DEST=${RYOKU_LOCAL_REPO:-/var/lib/ryoku/repo}
ARCH=x86_64

die() { printf 'publish-local-repo.sh: error: %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root"
staging=${1:-}
[[ -n $staging ]] || die "usage: publish-local-repo.sh <staging> [--owner <user> --checkout <path>]"
shift
owner=
checkout=
while (( $# )); do
  case $1 in
    --owner) owner=${2:?}; shift 2 ;;
    --checkout) checkout=${2:?}; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

for f in "$staging/$ARCH/ryoku.db" "$staging/.built-sha" "$staging/.built-abi" "$staging/.generation"; do
  [[ -f $f ]] || die "$f is missing; the staging dir is incomplete"
done

install -d -m755 "$DEST"
rm -rf "$DEST/$ARCH.new" "$DEST/$ARCH.old"
cp -a "$staging/$ARCH" "$DEST/$ARCH.new"
chown -R root:root "$DEST/$ARCH.new"
chmod -R u=rwX,go=rX "$DEST/$ARCH.new"
if [[ -d $DEST/$ARCH ]]; then mv "$DEST/$ARCH" "$DEST/$ARCH.old"; fi
mv "$DEST/$ARCH.new" "$DEST/$ARCH"
rm -rf "$DEST/$ARCH.old"

for f in .built-sha .built-abi .generation; do
  install -m644 -o root -g root "$staging/$f" "$DEST/$f"
done
if [[ -n $owner ]]; then
  printf 'user=%s\ncheckout=%s\n' "$owner" "$checkout" > "$DEST/.owner"
  chmod 644 "$DEST/.owner"
fi

#!/usr/bin/env bash
# build, sign, and assemble the [ryoku] pacman repo.
#
# walks release/packages/*/PKGBUILD, makepkg-builds each, signs with the ryoku
# release key, then `repo-add -s` to produce the signed db. layout matches the
# public mirror at https://repo.ryoku.dev/<arch>/: an <arch>/ subdir holding
# the *.pkg.tar.zst, their *.sig detached signatures, and ryoku.db /
# ryoku.db.sig (+ ryoku.files). publish workflow rclones that <arch>/ straight
# to R2.
#
# db is rebuilt from the package set every run: <arch>/ wiped, repacked from
# exactly the packages produced now. never `repo-add --new`. so: idempotent,
# and a removed package dir simply falls out of the db.
#
# build deps live on the build host only (Go toolchain + Ryoku.Blobs QML plugin
# + the Hyprland compositor plugins + wallust): base-devel, go, rust (cargo, for
# wallust), cmake, ninja, qt6-shadertools, qt6-declarative, and hyprland +
# hyprcursor + pango + cairo + pkgconf (the plugin packages build against
# Hyprland's headers).
# makepkg runs --nodeps on purpose: runtime depends (and AUR depends) aren't
# needed to compile the artifacts and aren't resolvable here anyway.
#
# usage: ./build-repo.sh
#
# env overrides:
#   RYOKU_REPO_OUT      output dir            (default: ./out beside this script)
#   RYOKU_REPO_KEY      gpg key id to sign    (default: release key fingerprint)
#   RYOKU_REPO_NAME     repo db base name     (default: ryoku)
#   RYOKU_REPO_ARCH     target architecture   (default: x86_64)
#   RYOKU_REPO_UNSIGNED 1 = no signing key: build and index unsigned packages
#                       for a repo this machine consumes itself (build-local-repo.sh)
#   RYOKU_REPO_CARRY_DIR  a previous repo dir to fall back on (unsigned mode): an
#                       optional package whose build fails keeps its last good
#                       build from there instead of aborting the whole set (with
#                       no earlier build it is left out; a required one aborts)
#   RYOKU_REPO_SKIP_EXTERNAL  1 = do not rebuild optional packages that follow an
#                       upstream (no RYOKU_PKGVER); carry them over untouched
#   RYOKU_PACKAGES_DIR  PKGBUILD parent dir   (default: <repo>/release/packages)
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)   # release/repo
RELEASE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)                  # release

OUT_DIR=${RYOKU_REPO_OUT:-$SCRIPT_DIR/out}
KEY_ID=${RYOKU_REPO_KEY:-EB6D3C0F55A7B3CABA6B2838847B274F025DD6E3}
REPO_NAME=${RYOKU_REPO_NAME:-ryoku}
REPO_ARCH=${RYOKU_REPO_ARCH:-x86_64}
PACKAGES_DIR=${RYOKU_PACKAGES_DIR:-$RELEASE_DIR/packages}
UNSIGNED=${RYOKU_REPO_UNSIGNED:-0}
CARRY_DIR=${RYOKU_REPO_CARRY_DIR:-}
SKIP_EXTERNAL=${RYOKU_REPO_SKIP_EXTERNAL:-0}

ARCH_DIR=$OUT_DIR/$REPO_ARCH
DB_PATH=$ARCH_DIR/$REPO_NAME.db.tar.gz

log() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
die() { printf 'build-repo.sh: error: %s\n' "$*" >&2; exit 1; }

# 0. preflight. makepkg refuses root; everything else just wants the pacman
#    tools and the release secret key in GNUPGHOME.
[[ $EUID -ne 0 ]] || die "makepkg refuses to run as root; run as a regular user"
command -v makepkg  >/dev/null 2>&1 || die "makepkg not found (pacman -S base-devel)"
command -v repo-add >/dev/null 2>&1 || die "repo-add not found (ships with pacman)"
[[ -d $PACKAGES_DIR ]] || die "packages dir not found: $PACKAGES_DIR"
if [[ $UNSIGNED != 1 ]]; then
  command -v gpg >/dev/null 2>&1 || die "gpg not found (pacman -S gnupg)"
  gpg --list-secret-keys "$KEY_ID" >/dev/null 2>&1 \
    || die "release signing key $KEY_ID not in GNUPGHOME=${GNUPGHOME:-$HOME/.gnupg}"
fi

shopt -s nullglob
pkgbuilds=("$PACKAGES_DIR"/*/PKGBUILD)
(( ${#pkgbuilds[@]} > 0 )) || die "no PKGBUILDs found under $PACKAGES_DIR"

# 1. fresh output tree. wiping the arch dir is what keeps the repo idempotent:
#    db gets rebuilt from exactly the packages produced this run, no stale
#    versions left to confuse repo-add.
log "Output dir -> $ARCH_DIR"
rm -rf "$ARCH_DIR"
mkdir -p "$ARCH_DIR"

# 2. build + sign every package straight into the arch dir. with --sign
#    makepkg writes the package and its detached .sig to PKGDEST. --nodeps
#    skips the (unresolvable, unneeded) runtime depends; --clean clears the
#    per-build $srcdir/$pkgdir so the checked-out source is left alone.
export PKGDEST=$ARCH_DIR
export PKGEXT='.pkg.tar.zst'

# per-build version for the monorepo packages: core semver + commit count +
# short sha (bin/ryoku-release-version --pkgver). every published build is
# then strictly newer + commit-identifiable in pacman terms, so `ryoku update`
# (pacman -Syu) actually sees an upgrade after each push and the Hub can show
# the commit. monorepo PKGBUILDs read RYOKU_PKGVER; gpk, ryomotion, awww, and
# wallust keep their own versions (from their upstreams). overridable.
: "${RYOKU_PKGVER:=$("$RELEASE_DIR/../bin/ryoku-release-version" --pkgver)}"
export RYOKU_PKGVER
log "Monorepo package version -> $RYOKU_PKGVER"
sign_args=()
if [[ $UNSIGNED != 1 ]]; then sign_args=(--sign --key "$KEY_ID"); fi
# makepkg rewrites pkgver= in the file it reads whenever a pkgver() function
# changes it (gpk and ryomotion track upstream's latest), so each package builds
# from a throwaway copy and the checkout's tracked PKGBUILDs stay clean.

# required = what ryoku-desktop pins to this build's version plus ryoku-desktop
# itself: they must all build fresh, together. every other package is optional,
# and with a CARRY_DIR it may fall back on its last good build when it fails (an
# upstream-tracking package whose HEAD broke, a Hyprland plugin before upstream
# pins the new compositor); an unsigned build with nothing to fall back on leaves
# it out rather than lose the whole install. optional packages that also follow an upstream (no
# RYOKU_PKGVER) can be skipped outright, which is what a rebuild for changed
# system libraries wants: only the ABI-coupled packages need it.
required=" ryoku-desktop $(grep -oE '"[a-z0-9-]+=\$pkgver"' "$PACKAGES_DIR/ryoku-desktop/PKGBUILD" 2>/dev/null \
  | sed -E 's/^"|=.*$//g' | tr '\n' ' ') "

# copy the newest previous build of $1 from the carry dir into the output dir
carry_over() {
  [[ -n $CARRY_DIR ]] || return 1
  local newest
  newest=$(printf '%s\n' "$CARRY_DIR/$1"-[0-9]*.pkg.tar.zst | sort -V | tail -n1)
  [[ -f $newest ]] || return 1
  cp -f "$newest" "$ARCH_DIR/"
  log "Carried over $(basename "$newest")"
}

for pkgbuild in "${pkgbuilds[@]}"; do
  pkgdir=$(dirname "$pkgbuild")
  name=$(basename "$pkgdir")
  optional=1
  [[ $required == *" $name "* ]] && optional=0
  external=0
  grep -q RYOKU_PKGVER "$pkgbuild" || external=1
  if (( optional && external && SKIP_EXTERNAL )) && carry_over "$name"; then
    continue
  fi
  log "Building $name"
  if ! ( cd "$pkgdir" \
      && cp PKGBUILD PKGBUILD.build \
      && trap 'rm -f PKGBUILD.build' EXIT \
      && makepkg -p PKGBUILD.build --force --clean --nodeps --noconfirm "${sign_args[@]}" ); then
    (( optional )) || die "$name failed to build"
    if carry_over "$name"; then
      log "warning: $name failed to build; kept its last good build"
    elif (( UNSIGNED )); then
      log "warning: $name failed to build and has no earlier build; leaving it out"
    else
      die "$name failed to build"
    fi
  fi
done

# 3. a published filename never changes bytes. makepkg is not reproducible,
#    so a fixed-version package (awww, wallust) rebuilt here would
#    overwrite its live file with new bytes and break every client holding
#    the previous db ("Maximum file size exceeded", issue #21). a name the
#    mirror already serves keeps its served bytes, re-signed; shipping a
#    change means bumping pkgrel.
MIRROR=${RYOKU_REPO_MIRROR:-https://repo.ryoku.dev/stable/$REPO_ARCH}

# from the mirror URL on a dev box, or from a directory when CI pre-fetched
# the bucket (Cloudflare 403s datacenter runners on the public domain).
fetch_published() {
  case $MIRROR in
    http://* | https://*) curl -fsSL --retry 3 -o "$2" "$MIRROR/$1" 2>/dev/null ;;
    *) [[ -f $MIRROR/$1 ]] && cp -f "$MIRROR/$1" "$2" ;;
  esac
}

adopt_pkgs=("$ARCH_DIR"/*.pkg.tar.zst)
if [[ $UNSIGNED == 1 ]]; then adopt_pkgs=(); fi
for pkg in "${adopt_pkgs[@]}"; do
  name=$(basename "$pkg")
  if ! fetch_published "$name" "$pkg.published"; then
    rm -f "$pkg.published"   # not on the mirror yet: this build introduces it
    continue
  fi
  if ! bsdtar -tf "$pkg.published" >/dev/null 2>&1; then
    log "Mirror copy of $name is unreadable; publishing this build over it"
    rm -f "$pkg.published"
    continue
  fi
  if cmp -s "$pkg" "$pkg.published"; then
    rm -f "$pkg.published"
    continue
  fi
  log "Adopting published bytes for $name (filenames are immutable once live)"
  mv -f "$pkg.published" "$pkg"
  gpg --batch --yes --detach-sign -u "$KEY_ID" -o "$pkg.sig" "$pkg"
done

# 4. collect built packages, confirm each is signed before indexing.
packages=("$ARCH_DIR"/*.pkg.tar.zst)
(( ${#packages[@]} > 0 )) || die "no packages were built into $ARCH_DIR"
if [[ $UNSIGNED != 1 ]]; then
  for pkg in "${packages[@]}"; do
    [[ -e $pkg.sig ]] || die "missing signature for $(basename "$pkg")"
  done
fi

# 5. signed db from the actual package set. no --new: the dir was wiped above,
#    so repo-add always starts from empty and indexes exactly what's there. -s
#    signs the db with the release key.
log "Indexing ${#packages[@]} package(s) into $REPO_NAME.db"
if [[ $UNSIGNED == 1 ]]; then
  repo-add "$DB_PATH" "${packages[@]}"
else
  repo-add -s -k "$KEY_ID" "$DB_PATH" "${packages[@]}"
fi

# 6. repo-add leaves ryoku.db / ryoku.db.sig / ryoku.files as symlinks to the
#    versioned tarballs. object storage (R2/S3) has no symlinks and pacman
#    fetches the bare names, so materialize them as real files in place.
for link in "$REPO_NAME.db" "$REPO_NAME.db.sig" "$REPO_NAME.files" "$REPO_NAME.files.sig"; do
  target=$ARCH_DIR/$link
  [[ -L $target ]] || continue
  resolved=$(readlink -f "$target")
  rm -f "$target"
  cp "$resolved" "$target"
done

[[ -e $ARCH_DIR/$REPO_NAME.db ]]     || die "$REPO_NAME.db missing after repo-add"
if [[ $UNSIGNED != 1 ]]; then
  [[ -e $ARCH_DIR/$REPO_NAME.db.sig ]] || die "$REPO_NAME.db.sig missing; signing failed"
fi

log "Repo ready at $ARCH_DIR"
if [[ $UNSIGNED != 1 ]]; then
  log "Serves: https://repo.ryoku.dev/stable/$REPO_ARCH/ (Server = https://repo.ryoku.dev/stable/\$arch)"
fi

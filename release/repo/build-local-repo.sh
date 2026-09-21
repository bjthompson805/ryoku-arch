#!/usr/bin/env bash
# Build the [ryoku] packages from this checkout into a staging repo, then hand it
# to publish-local-repo.sh, so an install of a fork needs nothing hosted beyond
# the git remote. The packages are compiled here, unsigned, and served to pacman
# from /var/lib/ryoku/repo/<arch>/ over file:// with SigLevel = Never: you built
# them yourself, there is no key to trust.
#
# Runs as the normal user (makepkg refuses root); only publishing uses sudo. The
# set is built into a staging dir and swapped in whole, so a failed build leaves
# the last good repo serving.
#
# A build is needed when:
#   - the checkout's HEAD moved (everything is rebuilt);
#   - the installed versions of the ABI-coupled system packages
#     (release/repo/abi.packages) differ from the ones the last build saw. Locally
#     built packages record no library dependencies, so a system upgrade can leave
#     them linked against libraries that are gone; rebuilding on that change is
#     what keeps the shell from breaking. Only what links against them is rebuilt,
#     not the packages that just follow an upstream;
#   - an upstream-following package has a newer upstream (a package directory with
#     an executable `upstream` script that prints the current upstream version);
#     only those are rebuilt.
#
#   release/repo/build-local-repo.sh [--force] [--stage-only] [--no-upstream]
#
#   --force         rebuild everything
#   --stage-only    build into staging and stop; the caller publishes it as root
#   --no-upstream   do not look for newer upstream releases (the unattended rebuild
#                   after a system upgrade uses this: it must not pull in new code)
#
# env overrides:
#   RYOKU_LOCAL_REPO     where the repo is published (default: /var/lib/ryoku/repo)
#   RYOKU_PACKAGES_DIR   PKGBUILD parent dir (default: <repo>/release/packages)
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)

DEST=${RYOKU_LOCAL_REPO:-/var/lib/ryoku/repo}
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/ryoku
STAGING=$CACHE/repo-build
ARCH=x86_64
PKG_DIR=${RYOKU_PACKAGES_DIR:-$REPO_ROOT/release/packages}

log() { printf '\033[1;35m::\033[0m %s\n' "$*"; }
die() { printf 'build-local-repo.sh: error: %s\n' "$*" >&2; exit 1; }

force=0
stage_only=0
check_upstream=1
for arg in "$@"; do
  case $arg in
    --force) force=1 ;;
    --stage-only) stage_only=1 ;;
    --no-upstream) check_upstream=0 ;;
    *) die "unknown argument: $arg" ;;
  esac
done

[[ $EUID -ne 0 ]] || die "run as your normal user, not root (sudo is used to publish)"
git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || die "$REPO_ROOT is not a git checkout (the package version comes from its history)"

# name and version of every installed ABI-coupled package, sorted
abi_fingerprint() {
  { xargs -a "$SCRIPT_DIR/abi.packages" pacman -Q 2>/dev/null || true; } | sort
}

head=$(git -C "$REPO_ROOT" rev-parse HEAD)
abi=$(abi_fingerprint)
built_sha=$(cat "$DEST/.built-sha" 2>/dev/null || true)
built_abi=$(cat "$DEST/.built-abi" 2>/dev/null || true)
built_upstream=$(cat "$DEST/.built-upstream" 2>/dev/null || true)
generation=$(cat "$DEST/.generation" 2>/dev/null || echo 0)

# "<package> <upstream version>" for every package that follows an upstream. A
# probe that fails (offline) leaves its package out, so it counts as unchanged.
upstream_now=
if (( check_upstream )); then
  for probe in "$PKG_DIR"/*/upstream; do
    [[ -x $probe ]] || continue
    id=$(timeout 30 "$probe" 2>/dev/null) || continue
    upstream_now+="$(basename "$(dirname "$probe")") $id"$'\n'
  done
fi
upstream_now=${upstream_now%$'\n'}

# packages that follow an upstream (no RYOKU_PKGVER) do not link against the
# system libraries the way the rest do
is_external() { ! grep -q RYOKU_PKGVER "$PKG_DIR/$1/PKGBUILD"; }

mode=full
only=
changed=
if (( ! force )) && [[ -f $DEST/$ARCH/ryoku.db && $built_sha == "$head" ]]; then
  while IFS=' ' read -r name id; do
    [[ -n $name ]] || continue
    grep -qxF "$name $id" <<<"$built_upstream" || changed+="$name "
  done <<<"$upstream_now"
  if [[ $built_abi == "$abi" && -z $changed ]]; then
    log "Local [ryoku] repo already built from ${head:0:7}; --force rebuilds"
    rm -rf "$STAGING"
    exit 0
  fi
  mode=partial
  if [[ $built_abi != "$abi" ]]; then
    log "The system libraries changed since the last build; rebuilding what links against them"
    for dir in "$PKG_DIR"/*/; do
      name=$(basename "$dir")
      is_external "$name" || only+="$name "
    done
  fi
  if [[ -n $changed ]]; then
    log "Newer upstream: $changed"
  fi
  only+=$changed
fi

# Sources and package-manager caches outlive the build: git clones and the Node
# tarball are fetched once and updated incrementally, and the npm and Electron
# downloads are reused, so a rebuild does not fetch them again.
mkdir -p "$CACHE/sources" "$CACHE/build"
export SRCDEST=$CACHE/sources
export RYOKU_BUILD_CACHE=$CACHE/build

# every build gets a strictly higher version, even when the commit is the same
# (a rebuild for new libraries), so pacman -U installs it over the old one
generation=$((generation + 1))
RYOKU_PKGVER="$("$REPO_ROOT/bin/ryoku-release-version" --pkgver).$generation"
export RYOKU_PKGVER

export RYOKU_REPO_UNSIGNED=1
export RYOKU_REPO_OUT=$STAGING
export RYOKU_REPO_NAME=ryoku
if [[ -d $DEST/$ARCH ]]; then export RYOKU_REPO_CARRY_DIR=$DEST/$ARCH; fi
if [[ $mode == partial ]]; then export RYOKU_REPO_ONLY=$only; fi

log "Building the [ryoku] packages from ${head:0:7} ($mode build; compiles Go, Rust, C++, and an Electron app)"
rm -rf "$STAGING"
mkdir -p "$STAGING"
"$SCRIPT_DIR/build-repo.sh"

[[ -f $STAGING/$ARCH/ryoku.db ]] || die "no repo db was produced under $STAGING/$ARCH"
printf '%s\n' "$head" > "$STAGING/.built-sha"
printf '%s\n' "$abi" > "$STAGING/.built-abi"
printf '%s\n' "$generation" > "$STAGING/.generation"

# what each upstream-following package was built from: the versions seen now for
# the ones rebuilt, the previous record for the ones carried over or not probed
{
  while IFS=' ' read -r name id; do
    [[ -n $name ]] || continue
    if [[ $mode == full || " $only " == *" $name "* ]]; then
      printf '%s %s\n' "$name" "$id"
    else
      grep -F "$name " <<<"$built_upstream" || printf '%s %s\n' "$name" "$id"
    fi
  done <<<"$upstream_now"
  if (( ! check_upstream )); then printf '%s\n' "$built_upstream"; fi
} | sed '/^$/d' > "$STAGING/.built-upstream"

if (( stage_only )); then
  log "Staged at $STAGING; publish it with publish-local-repo.sh"
  exit 0
fi

log "Publishing to $DEST/$ARCH"
sudo "$SCRIPT_DIR/publish-local-repo.sh" "$STAGING" --owner "$(id -un)" --checkout "$REPO_ROOT"
rm -rf "$STAGING"

log "Local [ryoku] repo ready (Server = file://$DEST/\$arch)"

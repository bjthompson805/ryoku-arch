# Updates and delivery

How a change in this repo reaches a running machine, and the contract that keeps
a user's install a mirror of a dev checkout. Read this before adding a config
file, a `shell.json` key, or anything a user must receive.

## Two worlds, one result

- A **dev box** runs the checkout: `ryoku deploy` builds the binaries and lays
  `ryoku/` into `~/.config`. `ryoku update` on it tracks `origin/main` (the git
  channel) and redeploys.
- A **fork install** runs packages it built itself. The shell installer
  (`ryoku-shell-installer/`) clones the fork, compiles the `release/packages/`
  set into a local repo at `/var/lib/ryoku/repo` (`release/repo/build-local-repo.sh`,
  unsigned, registered as `[ryoku]` over `file://`), and installs from it.
  Nothing is hosted beyond the git remote. `ryoku update` on it pulls the
  recorded checkout (`~/.local/state/ryoku/local-repo`), rebuilds, installs those
  packages, then `ryoku materialize` and `ryoku doctor`.

They must converge. A change that lands on one but not the other is the bug this
page exists to prevent.

## Ryoku never updates the system

`ryoku update` never runs `pacman -Syu` and never touches the AUR. It installs
its own packages with `pacman -U`, which needs no database sync, so it cannot
cause a partial upgrade. Upgrading the rest of the system is the user's.

Packages built locally record no library dependencies, so a system upgrade can
leave them linked against libraries that no longer exist. Two things keep the
shell from breaking:

- **A pacman hook** (`system/rebuild/ryoku-rebuild.hook`, one `Target` per
  package in `release/repo/abi.packages`) starts `ryoku-rebuild-abi` when an
  upgrade replaces one of Hyprland, Qt, ffmpeg, Wayland, or the other libraries
  the packages build against. It runs as a low-priority transient unit after the
  transaction: it rebuilds as the checkout's owner, publishes, installs with
  `pacman -U`, and notifies the desktop. It only builds the commit the owner last
  built with sudo, from a clean checkout, so an edit made since is never built and
  installed as root unattended; in that case it notifies and leaves the rebuild
  to `ryoku update`.
- **`ryoku update` checks the same thing**: `build-local-repo.sh` rebuilds when
  the checkout moved or the installed versions of those packages differ from the
  last build's. A library-only rebuild skips packages that follow an upstream
  (`ryomotion`, `gpk`, `awww`, `wallust`) and gives every build a higher version
  (a generation counter appended to the commit-derived one) so `pacman -U`
  replaces the old package.

A build failure of a required package installs nothing. An optional package
(anything `ryoku-desktop` does not pin) that fails keeps its last good build, or,
on a first install with none, is left out, so a broken upstream HEAD or a Hyprland
release its plugins do not support yet cannot hold the shell hostage.

## `ryoku update`

Snapper pre-snapshot, then the channel (git fast-forward and redeploy on a dev
box, or a rebuild of the local repo and a `pacman -U` on a fork install), then
stage2 through the just-installed binary: quiesce the shell,
`ryoku materialize`, reload Hyprland, restart the shell, `ryoku doctor`, snapper
post-snapshot. Each stage publishes to `$XDG_RUNTIME_DIR/ryoku-update.json` (the
ordered steps, the current label, a live log tail, and, on failure, the error
and the pre-update snapshot), so the update island and the Hub's Updates page
render a determinate run and a one-click rollback.

## materialize: the config a user receives

`ryoku materialize` lays the package's base config (`/usr/share/ryoku/config`,
mirrored by `ryoku/shell/deploy.sh` on a dev box) into `~/.config`:

- Every shipped file is copied over on every update (the previous Ryoku copy is
  clobbered) and files dropped from a release are pruned; `~/.config/quickshell`
  is converged wholesale.
- A short **seed list** (`generatedSeed` in `ryoku/cli/materialize.go`:
  `hypr/monitors.lua`, `hypr/gpu.lua`, `hypr/keyboard.lua`,
  `fastfetch/config.jsonc`, `kitty/current-theme.conf`) is copied only when
  absent, never clobbered: per-machine or user-owned state an update must keep.
- User files the package never ships (`hypr/user.lua`, `kitty/user.conf`, ...)
  are left alone.

So the QML and the `Config.qml` defaults reach users on every update. A **new**
`shell.json` key is safe: the user's file lacks it, and the shell reads the new
`Config.qml` default.

## doctor: converging what materialize can't

`ryoku doctor` runs convergent reconcilers for the stateful drift materialize
can't state declaratively (disk, boot, session, and the user-owned
`~/.config/ryoku/*.json` materialize never rewrites). Reconcilers stand in for a
migration ledger: each is idempotent and safe on every update, and is retired
once every supported install has run it. `reconcileShellConfig` migrates a stale
`shell.json` (drops retired keys, revives the bar, clamps geometry).

## How a commit reaches a machine

A commit reaches a fork install when it is on the fork's `main` and the machine
runs `ryoku update`: the checkout fast-forwards, and the build gives every package
a strictly higher version (`<core>.r<commit-count>.g<sha>.<generation>`) that
`pacman -U` installs. `ryoku status` counts the commits between the installed
build and `origin/main`.

## The contract

- **A user-facing config file must be delivered by a path a user runs**: shipped
  in a package (then materialized) or seeded by the installer. A file only
  `deploy.sh` lays, or one no path lays, reaches no user. `ryoku-dev-verify-delivery`
  fails the commit on such an orphan.
- **A removed or renamed `shell.json` key, or a changed default that must reach
  existing users, needs a `doctor` reconciler** (materialize never edits a user's
  `shell.json`). An additive key needs nothing.
- **A change reaches a machine only once it is on the fork's `main`** and the
  machine runs `ryoku update`.

## Checks

- `bin/ryoku-dev-verify-delivery` flags orphan configs (hard fail). It runs in
  `pre-commit`, `post-commit`, and the Delivery check workflow.

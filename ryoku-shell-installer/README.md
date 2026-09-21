# ryoku-shell

Install this fork of the Ryoku desktop on an existing Arch machine, without the
ISO. Nothing is hosted beyond the git remote: the desktop packages are compiled
on the machine from a checkout of the fork, so the install does not depend on
upstream's package repo, key, or servers.

The build is heavy. Expect a toolchain download (Go, Rust, Qt, and friends), the
Cargo and Go module downloads, Ryo Motion's Node tarball and Electron, and a long
compile. Run it on a fast, unmetered connection.

```bash
curl -fsSL https://raw.githubusercontent.com/bjthompson805/ryoku-arch/main/ryoku-shell-installer/install.sh | bash
```

Headless / unattended:

```bash
curl -fsSL .../install.sh | bash -s -- --yes
```

Preview without changing anything:

```bash
curl -fsSL .../install.sh | bash -s -- --dry-run
```

Remove the Ryoku desktop again:

```bash
ryoku-shell-install --uninstall        # or: ... | bash -s -- --uninstall
```

## What it does

`install.sh` is a dumb bootstrap: it verifies the machine is Arch-based
x86_64, downloads the prebuilt `ryoku-shell-install` binary (checksummed) from
this directory, and hands it the real terminal. Everything else is the binary,
a bubbletea TUI sharing the ISO installer's visual language:

1. **Scan** the machine: distro, GPU, Secure Boot state, display manager,
   network stack, installed desktops (GNOME/KDE/Cinnamon/Xfce), rival
   quickshell shells (Noctalia, DankMaterialShell, Caelestia, iNiR), known
   Hyprland rices (ML4W, HyDE, JaKooLit, end-4, Caelestia), conflicting user
   daemons (dunst/mako/waybar/swww/…), a plain Hyprland, niri or sway setup
   to migrate from, an Omarchy install to retire (repo + mirror pin),
   keyboard layout, btrfs, and an interrupted previous run to resume.
2. **Plan** review with per-item toggles (NVIDIA drivers, SDDM switch,
   greeter theme, NetworkManager switch, rival-shell removal, monitor-layout
   carry-over, AUR extras, fish shell); sections group the list when it gets
   long.
3. **Install**, streamed step by step:
   legacy-repo retirement → `pacman -Syu` → build toolchain → checkout of the
   fork (a blobless full clone in `~/.local/share/ryoku/repo`) → package build
   (`release/repo/build-local-repo.sh` compiles every `release/packages/`
   PKGBUILD into `/var/lib/ryoku/repo`) → config backup (with a generated
   `restore.sh`) → that local repo registered as `[ryoku]` in `pacman.conf`
   (`SigLevel = Never`: you built the packages yourself, there is no key) →
   conflict removal → desktop packages → GPU drivers → SDDM/qylock/network wiring →
   `ryoku materialize` + seeds (wallpapers, brand, keyboard layout salvaged
   from the old setup) → AUR extras → standard extras (`chromium`, the CLI tools
   the shell config uses, the OCR, QR, capture, and VM helpers, and `markdown-writer`
   from its latest GitHub release; all best-effort) → `ryoku doctor` → verify.

Afterwards the machine is a normal Ryoku box: `ryoku doctor` heals it, and
`ryoku update` pulls the fork's checkout, rebuilds the local `[ryoku]` repo from
it (skipped when nothing changed), installs the built packages with `pacman -U`,
then runs the usual materialize and doctor stages. It never upgrades the rest of
the system. When you upgrade a library the packages link against (Hyprland, Qt,
ffmpeg, and so on), a pacman hook rebuilds them in the background. A failed build
installs nothing. `ryomotion` and `gpk` track their upstream's latest rather than a
pinned version: each `ryoku update` checks whether upstream has a newer release
and rebuilds just that package if so. It also keeps `markdown-writer` current from
its GitHub releases. Nothing here ever needs re-running.

Migration policy: rival shells are uninstalled (toggle), conflicting daemons
are disabled but never uninstalled, the old display manager is disabled (not
removed), desktop environments are never uninstalled and stay selectable at
the login screen, niri and sway stay installed as fallback sessions, and
every config the install touches is saved to
`~/.local/state/ryoku/shell-install/backup-<ts>/` first, `restore.sh`
included. Monitor layout and keyboard intent are salvaged with compositor
configs first: Hyprland (`monitor=`/`monitorv2`/`input`, includes and `$vars`
followed) beats niri beats sway, then KDE (`kxkbrc`,
`kwinoutputconfig.json`), then GNOME (gsettings input-sources,
`monitors.xml`), then `localectl`.

Safety gates: non-systemd systems (Artix and friends) are refused outright.
With Secure Boot enforcing, the NVIDIA toggle is forced off and locked,
because Arch kernels reject unsigned DKMS modules and the driver script
blacklists nouveau; sign with sbctl or disable Secure Boot, then re-run.
Manjaro requires a typed acknowledgement in the TUI and is refused under
`--yes` unless `RYOKU_ALLOW_MANJARO=1` is set.

Lifecycle: an interrupted run records its completed steps in
`~/.local/state/ryoku/shell-install-state.json`; the next run offers a
resume toggle (automatic with `--yes`) that skips finished steps and
continues the same backup. `--uninstall` removes the ryoku packages, drops
the `[ryoku]` repo stanza, and walks the backup chain newest to oldest,
running each `restore.sh` with confirmation; those scripts also re-enable
the services and display manager their run disabled. Session packages
(sddm, pipewire, NetworkManager, …) are left installed.

## Development

```bash
go build -trimpath -o ryoku-shell-install .   # rebuild
sha256sum ryoku-shell-install > ryoku-shell-install.sha256
go test ./...
```

The binary and its checksum are committed (same convention as
`installation/tui/ryoku-tui`) so `install.sh` can fetch them from
raw.githubusercontent.com with no release infrastructure. Test a branch with:

```bash
curl -fsSL https://raw.githubusercontent.com/bjthompson805/ryoku-arch/<branch>/ryoku-shell-installer/install.sh \
  | RYOKU_SHELL_REF=<branch> bash
```

`--payload /path/to/checkout` (or `RYOKU_SHELL_PAYLOAD`) skips the payload
clone and builds from a local repo, for iterating without pushing;
`RYOKU_SHELL_REPO` points the clone at a different git remote.

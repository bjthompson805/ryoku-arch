# Ryoku for an existing Arch install

This is a fork of [Ryoku Arch](https://github.com/neur0map/ryoku-arch) at its
**Beta 17** release (`0.12.8-beta.17`). Its purpose is to make the Ryoku shell
easy to install on top of an Arch Linux system you already have, with no ISO and
no reinstall.

```bash
curl -fsSL https://raw.githubusercontent.com/bjthompson805/ryoku-arch/main/ryoku-shell-installer/install.sh | bash
```

The installer asks before it changes anything, saves your existing configs to
`~/.local/state/ryoku/shell-install/` with a generated `restore.sh`, and can be
undone by running the same command with `bash -s -- --uninstall`. It needs an
x86_64 Arch-based system that boots with systemd.

**How it differs from upstream**

- **Nothing is hosted but this repository.** The desktop packages are compiled on
  your machine from a checkout of this repo (in `~/.local/share/ryoku/repo`) into
  a local pacman repo, so the install does not depend on upstream's package
  repository, signing key, or servers. Expect a long first build.
- **`ryoku update` only updates Ryoku.** It pulls this repo, rebuilds, and installs
  the Ryoku packages. It never runs `pacman -Syu` or touches the AUR; upgrading the
  rest of the system is yours. The installer itself does one full system upgrade
  at the start, so the dependencies it installs match your system.
- **A system upgrade should not break the shell.** The packages are built against
  the libraries you have, so when you upgrade Hyprland, Qt, ffmpeg, or another
  library they link against, a pacman hook rebuilds them in the background and
  notifies you.
- **`ryomotion` and `gpk` track their upstream's latest release** instead of a
  pinned version.
- **No ISO, no release channels.** The fork follows its own `main` and is not kept
  mergeable with upstream, which has diverged.
- **The store still reads upstream's `ryoku-extras`** (rices and extras).

What follows is upstream's README. Where it describes the ISO, the hosted
`[ryoku]` repository, the download page, or release channels, it does not apply
to this fork. Its "Already on Arch" install and recovery one-liners have been
changed to fetch this fork's scripts.

---

<div align="center">

<img src="https://raw.githubusercontent.com/neur0map/ryoku-arch/main/ryoku/assets/brand/logo-mark.png" alt="Ryoku" width="160" />

# Ryoku Arch

**力と美のために** &middot; *For the sake of power and beauty.*

Ryoku is a hand-built Arch Linux distribution: one cohesive Hyprland desktop, a
guided installer, and the system definition that reproduces them, all from a
single repository. The base is lean enough to live in from first boot and
deliberate in how it looks and moves.

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-E2342A?style=for-the-badge)](LICENSE)
[![Built on Arch](https://img.shields.io/badge/Arch_Linux-1793D1?style=for-the-badge&logo=archlinux&logoColor=white)](https://archlinux.org)
[![Hyprland](https://img.shields.io/badge/Hyprland-58E1C2?style=for-the-badge&logoColor=white)](https://hypr.land)
[![Release status](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fiso.ryoku.dev%2Fstable%2Flatest.json&query=%24.channel&label=status&color=E2342A&style=for-the-badge)](https://ryoku.dev)
[![Build ISO](https://github.com/neur0map/ryoku-arch/actions/workflows/build-iso.yml/badge.svg)](https://github.com/neur0map/ryoku-arch/actions/workflows/build-iso.yml)
[![Discord](https://img.shields.io/badge/Discord-join-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/8KjBmUEyKA)
[![Reddit](https://img.shields.io/badge/Reddit-r%2FRyokuArch-FF4500?style=for-the-badge&logo=reddit&logoColor=white)](https://www.reddit.com/r/RyokuArch/)

<kbd>[Download](https://ryoku.dev)</kbd> &middot; <kbd>[Ryoku](docs/ryoku.md)</kbd> &middot; <kbd>[Docs](docs/)</kbd> &middot; <kbd>[Structure](docs/structure.md)</kbd> &middot; <kbd>[Discord](https://discord.gg/8KjBmUEyKA)</kbd> &middot; <kbd>[Subreddit](https://www.reddit.com/r/RyokuArch/)</kbd>

</div>

---

<div align="center">

<img src="docs/media/desktop.webp" alt="The Ryoku desktop" width="960" />

<sub>The Ryoku desktop. Screenshots are real; the poster art is generated.</sub>

<p>
  <a href="https://youtu.be/kx7VW4Mg0m4">
    <img src="https://img.youtube.com/vi/kx7VW4Mg0m4/maxresdefault.jpg" alt="Ryoku showcase: watch on YouTube" width="640" />
  </a>
  <br />
  <sub>&#9654; <a href="https://youtu.be/kx7VW4Mg0m4">Watch the Ryoku showcase on YouTube</a></sub>
</p>

</div>

---

## About

Ryoku means power, and the name is the point. The power is a modular shell built
to be extended: the desktop is composed of small, independent surfaces, and a
plugin system is on the way, so the shell grows with what you actually use
instead of bloating by default. The beauty is the shell itself, one continuous
and deliberate surface where the bar, panels, launcher, lockscreen, and session
controls move as a single thing. 力と美のために: for the sake of power and beauty.

Underneath, Ryoku is a hand-built Arch distribution rather than a config dump.
The desktop, the installer, and the system definition all live in this
repository, and every machine is built from it; the repository is the single
source of truth, and a live machine is only ever a deployment target. The
desktop is a Hyprland Wayland session authored in Lua with the Quickshell-based
Ryoku shell on top. The project began as an Omarchy fork, and its command and
package conventions still descend from it, but the installer, shell, theming, and
desktop are Ryoku's own. The shell is custom: its frame-blob rendering and some
animation curves are adapted from Caelestia.

## The desktop

One motion language across every surface, retinted live from your wallpaper.

<table>
  <tr>
    <td width="50%">
      <img src="docs/media/launcher.webp" alt="Launcher" width="100%" /><br />
      <sub><b>Launcher.</b> Apps, commands, calculator, files, and Ryotunes radio behind one search.</sub>
    </td>
    <td width="50%">
      <img src="docs/media/control-deck.webp" alt="Control Deck" width="100%" /><br />
      <sub><b>Control Deck.</b> Stash, tools, game mode, and capture, reachable in one place.</sub>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <img src="docs/media/appearance.webp" alt="Appearance" width="100%" /><br />
      <sub><b>Appearance.</b> The whole desktop retints from the wallpaper.</sub>
    </td>
    <td width="50%">
      <img src="docs/media/terminals.webp" alt="Terminals" width="100%" /><br />
      <sub><b>Tooling.</b> GlazePKG across every package manager, plus a live system monitor.</sub>
    </td>
  </tr>
</table>

## What ships

- **The desktop** under `ryoku/`: a Hyprland session authored in Lua (not a
  hand-written `hyprland.conf`), the Quickshell-based Ryoku shell, the
  lockscreen, app configs, and brand assets.
- **The system definition** under `system/`: the boot chain, hardware policy,
  and package sets that make a machine a Ryoku machine.
- **The installer** under `installation/`: a guided TUI, the backend installer,
  and the archiso profile that builds the signed ISO.
- **The update system** under `release/`: the `ryoku` control CLI, the desktop
  packages, and the signed `[ryoku]` pacman repository.

## Install

Two ways in. A fresh machine boots the signed **ISO**; an existing Arch box
converts in place with the **shell installer**.

### Fresh install (the ISO)

Signed ISO builds are published at **[ryoku.dev](https://ryoku.dev)**. Download
the latest image, its signature, and the checksums, write it to a USB stick, and
boot it. The guided installer partitions the disk (Btrfs with subvolumes),
installs the package set and the Ryoku desktop from the signed repository, sets
up the Limine boot chain, and configures snapshots.

Releases are signed with:

- **Key:** `Ryoku Releases <releases@ryoku.dev>`
- **Fingerprint:** `EB6D 3C0F 55A7 B3CA BA6B  2838 847B 274F 025D D6E3`
- **Public key in repo:** [`keys/ryoku-release-key.pub.asc`](keys/ryoku-release-key.pub.asc)

Verify the imported key's fingerprint matches before trusting it:

```bash
gpg --import keys/ryoku-release-key.pub.asc
gpg --verify ryoku-*.iso.sig ryoku-*.iso
```

Prefer to build it yourself? The archiso profile and build script live in
[`installation/iso`](installation/iso).

### Already on Arch (no ISO)

One line converts an existing Arch machine into a Ryoku box: it backs up your
configs (with a `restore.sh` to undo), builds the packages from this repository
into a local `[ryoku]` repo, migrates you off conflicting shells and daemons, and
wires up the full desktop. It never
partitions a disk.

```bash
curl -fsSL https://raw.githubusercontent.com/bjthompson805/ryoku-arch/main/ryoku-shell-installer/install.sh | bash
```

Preview everything it would do without changing anything by appending
`-s -- --dry-run` after `bash`. Details in
[`ryoku-shell-installer/`](ryoku-shell-installer/README.md).

> [!WARNING]
> The shell installer is young and still being tested across different hardware,
> distributions, and existing setups. It rewrites your shell and desktop
> configuration in place, and it may not behave the same on a setup we have not
> seen yet. **Back up your system first.** It writes a `restore.sh` and refuses
> to run as root, but making proper backups is your responsibility, and Ryoku is
> not responsible for data loss or for breaking your current desktop. Run it with
> `--dry-run` before you commit, and prefer a machine you can afford to reinstall.

### CachyOS kernel, in one click

Want the CachyOS scheduler and build? Open the Hub, go to **Extras**, and install
the **CachyOS Kernel** bundle. One click adds the CachyOS `x86-64-v3` repository
(its own signing key, layered above `[core]` and never replacing it) and installs
`linux-cachyos`. It is additive and idempotent, and it leaves your stock kernel in
place as a fallback, so you keep the choice of what to boot. Full details in
[`docs/kernels.md`](docs/kernels.md).

## Updating

Everything updates through one command:

```bash
ryoku update
```

It takes a snapshot, pulls the fork, rebuilds the Ryoku packages from it, installs
them, re-lays the desktop configs into your home, reloads the shell, and takes a
paired post-snapshot. It never upgrades the rest of the system. A failed build
installs nothing.

The desktop is compiled on your machine from this repository into a local
`[ryoku]` pacman repo. After you upgrade Hyprland, Qt, ffmpeg, or another library
it builds against, a pacman hook rebuilds it in the background so the shell keeps
working.

Your settings survive every update. The base configs are Ryoku-owned and
refreshed in place, while your own edits live in override files that are never
shipped or touched (`hypr/user.lua`, `kitty/user.conf`, `fish/user.fish`); they
load last, so your changes win. There is no ordered migration ledger: the config
is reconciled to the shipped state on every update, and the rare stateful fix
(disk layout and the like) is an idempotent `ryoku doctor` reconciler that runs
inside `ryoku update`. If an update goes wrong, run `ryoku rollback` or pick the
previous snapshot from the Limine boot menu.

## Recovery

When an update leaves the desktop unusable and `ryoku update` cannot fix it,
there is a last-resort recovery. It pulls the latest `main`, reinstalls the base
packages, and rebuilds and redeploys the whole desktop from source, overwriting
your Ryoku configs:

```bash
ryoku recovery
```

If the `ryoku` command itself is gone, drop to a TTY (`Ctrl+Alt+F2`, then log in)
and run the same recovery straight from the repo:

```bash
curl -fsSL https://raw.githubusercontent.com/bjthompson805/ryoku-arch/main/bin/ryoku-recovery | bash
```

This is a true last resort. It discards local Ryoku config customizations
(`hypr/user.lua` and friends) and resets you to the latest `main`. It refuses to
run on a machine that is not Ryoku, and asks you to confirm before it changes
anything. Pass `--yes` to skip the prompt and `--no-packages` to pull and
redeploy the configs without the pacman step.

## Repository layout

| Path | One job |
|---|---|
| `ryoku/` | The desktop: the Hyprland (Lua) config, the Quickshell shell, the lockscreen, app configs, brand assets. |
| `system/` | The machine definition: boot chain, hardware policy, package sets. |
| `installation/` | How a machine is built: the TUI, the backend installer, the ISO profile. |
| `release/` | Packaging: the desktop PKGBUILDs, the `[ryoku]` repo builder, the signing keyring. |
| `docs/` | The guides. Start with [`docs/ryoku.md`](docs/ryoku.md) and [`docs/structure.md`](docs/structure.md). |

## Channels

`main` is the stable channel everyone runs; it is published to the `[ryoku]`
repository and the ISO only on tagged releases. `unstable-dev` is the maintainer
preview, consumed through the dev loop and never published. A release promotes
`unstable-dev` to `main`. See [`docs/development.md`](docs/development.md) for the
deploy, test, and commit loop.

## Credits and license

Ryoku began as a fork of Omarchy, created by David Heinemeier Hansson and
contributors; its command and package conventions descend from it. The Ryoku
shell is custom, with its frame-blob rendering and some animations adapted from
the [Caelestia shell](https://github.com/caelestia-dots/shell), and parts of the
display configuration UI adapted from
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell). Full
attribution and upstream links are in [`NOTICE`](NOTICE). Ryoku is released under
the [GNU GPL v3](LICENSE).
</content>

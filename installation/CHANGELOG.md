# Changelog: installation/

## Unreleased

### Added
- `tui/`: the installer, a full-screen Go (Bubble Tea) TUI. `main.go` is the UI;
  `system.go` talks to the machine (live keymaps, locales, time zones, disks, and
  Wi-Fi, hardware detection, applying the keymap, hashing the password, and the
  streamed handoff to the backend).
- `backend/`: `ryoku-install` plus `lib/` (preflight, disk, luks, filesystem,
  pacstrap, chroot, deploy, drivers, bootloader). Reads the RYOKU_* answers and
  installs the system end to end. A dry-run mode prints every step.
- `iso/`: an archiso profile that boots straight into the TUI (cage and foot
  autolaunch), with a `build.sh` wrapper.
- The `Ryoku.Blobs` QML plugin (the shell's frame renderer) now rides the install
  path: `iso/build.sh` prebuilds the module into the payload (cmake, ninja, and
  qt6-shadertools on the build host), and `backend/lib/deploy.sh` installs it onto
  the user's Qt QML import path, so the installed desktop renders the frame with
  no build toolchain on the target.
- Ryoku Hub now rides the install path: `iso/build.sh` prebuilds the `ryoku-hub`
  Go binary into the payload, and `backend/lib/deploy.sh` installs it onto `PATH`
  and deploys its quickshell config to `~/.config/quickshell/hub`, so `Super + ,`
  works on a fresh install with no build toolchain on the target.

### Changed
- TUI: the intro holds the brand about 5 seconds longer before the wizard.
- TUI network step: recheck connectivity on entry (so a late ethernet lease shows
  as connected), show the real interface, and add an `r` rescan to the Wi-Fi picker.
- TUI: the install-failure screen's support QR now points at `docs.ryoku.dev`.
- TUI disk step: the second strategy is now "Install alongside Windows" (keep
  Windows, install into free space). `tui/system.go` reads the disk's real
  partitions and largest free region (`lsblk` + `parted`) so the layout shows the
  actual disk, and the step refuses to continue without a reused ESP and enough
  free space, matching the backend floor.

### Fixed
- Bootloader countdown no longer loops on the adopted Limine layout. When
  limine-mkinitcpio-hook 1.37+ keeps the `/Ryoku Linux` placeholder and nests
  the `//<kernel>` UKIs under it, the placeholder's boot stanza
  (`protocol`/`kernel_path`/`cmdline`/`module_path`) was left wedged between
  the directory title and its first sub-entry, where Limine's grammar allows
  only a `comment`. That "directory that is also a boot entry" cannot autoboot,
  so the timeout resolved nothing and the countdown restarted forever until an
  entry was picked by hand. The post-AUR repoint now strips the stanza and
  leaves a clean menu directory.
- Disk strategy is now fail closed: a missing or empty selection never defaults to
  a full-disk wipe. The TUI emits the chosen strategy verbatim (it used to fall
  back to `whole`, so any path that left the pick uncommitted silently wiped the
  disk, deleting an existing Windows install), the strategy picker now defaults its
  highlight to the non-destructive "alongside", and the Review step cannot advance
  to a whole-disk install without a committed strategy.
- Whole-disk installs onto a populated disk now require an explicit acknowledgement:
  the Review step shows the strategy in bold red with the partitions it will erase,
  and proceeds only after the user types ERASE (emitting `RYOKU_WIPE_CONFIRMED=1`).
  A blank disk installs without the extra confirmation.
- The live ISO now autostarts the installer instead of the stock Arch first-boot
  prompt, pacstrap has working mirrors and a populated keyring, and the boot
  console is quiet. See the `iso/` and `backend/` changelogs for detail.
- The installed desktop now ships the packages and NVIDIA KMS config it needs to
  render (Xwayland, the polkit agent, the Qt/GTK runtime), and the first reboot
  targets the installed disk via EFI BootNext. See `system/` and the iso/backend
  changelogs.
- Dual-boot installs failed at partitioning: the TUI emitted the disk strategy
  `existing`, which the backend rejected with "disk strategy existing not
  supported yet (use 'whole')". The TUI now emits `alongside` and the backend
  implements it, so installing beside Windows works end to end.
- TUI partition step: the swapfile is carved out of the root size and shown in the
  disk bar, so increasing swap now reduces the usable root instead of leaving the
  total unchanged. Root always takes the rest of the disk (the backend uses 100%),
  so the misleading editable root-size slider and the fake free-space line are gone.
- TUI done screen: "Reboot now" and "Power off" now actually run `systemctl
  reboot` / `systemctl poweroff` on Enter; before, every choice just quit the
  installer and the machine stayed in the live session. "Exit to a shell" still
  drops to a prompt.

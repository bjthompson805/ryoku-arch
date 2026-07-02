# Changelog: ryoku-shell-installer

## Unreleased

### Added

- Standalone no-ISO installer: `install.sh` curl bootstrap plus the
  `ryoku-shell-install` bubbletea TUI. Scans the machine, backs up configs
  with a generated `restore.sh`, removes rival quickshell shells, disables
  conflicting daemons and display managers, trusts the `[ryoku]` repo, installs
  the desktop set, wires SDDM/qylock/NetworkManager, materializes per-user
  config (salvaging the keyboard layout from a niri setup), builds the AUR
  extras, and converges with `ryoku doctor`. Headless `--yes` and `--dry-run`
  modes included.

### Fixed

- First boot flashed Hyprland's "Your config has errors" overlay: the shipped
  config pcall-requires optional drop-ins that don't exist on a fresh home and
  Hyprland reports the caught failure anyway. The installer now seeds
  comment-only stubs for the six optional files after `ryoku materialize`;
  they become redundant (but stay harmless) once the searchpath-probing
  loader ships in `ryoku-desktop`.

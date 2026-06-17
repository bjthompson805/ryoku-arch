# Changelog

Notable changes to the repository as a whole. Each tree keeps its own changelog
for finer detail.

## Unreleased

### Added
- Fresh repository layout: `installation/`, `system/`, `ryoku/`, each with a README
  and changelog.
- A working installer (Go TUI plus a bash backend) that partitions, optionally
  encrypts with LUKS, installs the base system, configures it, deploys the desktop,
  and sets up Limine.
- A plain Hyprland desktop with kitty, fastfetch, fish, and nautilus, an SDDM
  greeter using the qylock clockwork theme, and Limine with Ryoku branding.

### Notes
- The previous Arch tree stays on the `main` branch as reference. The NixOS work
  moved to its own repository.

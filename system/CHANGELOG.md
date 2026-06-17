# Changelog: system/

## Unreleased

### Added
- `packages/`: base, hardware (per-vendor GPU drivers and microcode), aur, and dev
  package lists.
- `boot/`: Limine config with Ryoku branding, the Plymouth theme, and the
  mkinitcpio hooks.
- `hardware/`: `ryoku-gpu` (picks and pins the strongest GPU), `ryoku-monitor`
  (HiDPI autoscale), the GPU udev rule, and per-vendor driver scripts. GPU and
  monitor settings are written as Hyprland Lua drop-ins.

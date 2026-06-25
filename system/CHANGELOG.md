# Changelog: system/

## Unreleased

### Added
- `extras/ryoku-extras-install`: `plugin` bundle items now install (fetched into
  `~/.local/share/ryoku/plugins` via `ryoku-hub extras plugin`) instead of being
  deferred, and report real present/absent state. Removal deletes the plugin's
  files while leaving the user's placement in `plugins.json`.
- `packages/`: base, hardware (per-vendor GPU drivers and microcode), aur, and dev
  package lists.
- `boot/`: Limine config with Ryoku branding, the Plymouth theme, and the
  mkinitcpio hooks.
- `hardware/`: `ryoku-gpu` (picks and pins the strongest GPU), `ryoku-monitor`
  (HiDPI autoscale), the GPU udev rule, and per-vendor driver scripts. GPU and
  monitor settings are written as Hyprland Lua drop-ins.
- `extras/`: the helpers behind the Hub's Extras section (`ryoku-extras-install`
  and the `ryoku-pkg-*` routing wrappers) that install, remove, and report the
  optional bundles from the `ryoku-extras` catalogue.

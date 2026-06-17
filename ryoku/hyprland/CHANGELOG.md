# Changelog: ryoku/hyprland/

## Unreleased

### Added
- Plain Hyprland config as native Lua modules (Hyprland 0.55+ `hl` API):
  - `hyprland.lua`: entrypoint. Look and feel (gaps, brand-orange gradient
    borders, rounding, blur, animations), input, default environment, XWayland
    zero-scaling, and startup (session environment import, polkit agent,
    `xdg-user-dirs-update`, best-effort `ryoku-monitor`/`ryoku-gpu`). Requires
    colors, keyboard, gpu, monitors, keybinds, then custom last.
  - `keybinds.lua`: the kept keybind set with plain targets (kitty, nautilus,
    chromium, fuzzel, yazi, nvim, grim/slurp, wpctl/brightnessctl/playerctl,
    qylock lock launcher).
  - `colors.lua`: Ryoku palette seed (border and shadow globals).
  - `keyboard.lua`: keyboard layout (us).
  - `monitors.lua`: catch-all monitor seed (per-output rules added by the hardware
    display script).
  - `gpu.lua`: comment-only managed placeholder (GPU pin added by the hardware GPU
    script).
  - `custom.lua`: empty user overrides, loaded last.

### Notes
- Rebuilt clean from the Lua reference; dropped the legacy GUI-tweaker layer and
  the Ryoku shell startup and binds (clipboard, game bar, settings panel, plugins,
  appearance GUI, wallpaper switcher, power menu, Obsidian). Listed at the bottom
  of `keybinds.lua` for maintainer review.
- Validated with `Hyprland --verify-config` (config ok) and `luac`-style syntax
  checks on every module.

# ryoku/

The desktop experience: what you see and use after logging in. `system/` builds
the machine; this tree makes it Ryoku.

## What's here

- `hyprland/` The Hyprland config, in Lua (Hyprland 0.55+ loads `hyprland.lua`
  natively). Modules: `hyprland.lua` (entrypoint), `keybinds.lua`, `colors.lua`,
  `keyboard.lua`, `monitors.lua`, `gpu.lua`, and `custom.lua` (yours to edit). A
  plain setup, no panels or bars this pass.
- `lockscreen/` The login and lock screen: the qylock "clockwork" theme for SDDM
  (vendored under `qylock/`), an installer, and the SDDM setup.
- `apps/` The apps we ship and their settings: kitty (terminal), fastfetch (the
  branded readout, with its wrapper), fish (shell, greeting off), starship
  (prompt), and notes for nautilus (files).
- `assets/` Branding: the 力 logo and icons.

## Fonts, cursors, and helper scripts

Fonts (JetBrains Mono Nerd, Noto) ship as packages in `system/packages`. The
cursor theme (Bibata) is a package too, selected by the Hyprland environment. The
few helper scripts live next to what they serve: the GPU and monitor helpers in
`system/hardware`, the fastfetch wrapper in `apps/fastfetch`, and the lock
launcher in `lockscreen/qylock`.

## Not here yet

The full Ryoku shell (custom panels and widgets) is planned but not part of this
pass. For now the desktop is plain Hyprland.

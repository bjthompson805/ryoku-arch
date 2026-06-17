# hyprland/

The Hyprland window manager config for Ryoku, written in Lua. Hyprland 0.55+
loads `~/.config/hypr/hyprland.lua` natively through its `hl` API, so there is no
extra loader and no separate `.conf` files. This is the plain pass: a tidy tiling
desktop, no custom panels, bars, or shell.

These files deploy to `~/.config/hypr/`.

## Modules

`hyprland.lua` is the entrypoint. It sets the look and feel, the default
environment, and the startup programs, and `require()`s the rest in an order that
lets machine-managed and personal values override the shipped defaults:

1. `colors.lua` The palette (globals like `var_primary`) the borders read.
2. `keyboard.lua` Keyboard layout. User-owned; edits survive updates.
3. `gpu.lua` GPU pin and cursor workaround on multi-GPU machines.
4. `monitors.lua` Per-display resolution and scaling.
5. `keybinds.lua` Every keyboard and mouse shortcut.
6. `custom.lua` Your personal overrides, loaded last so they always win.

## Generated modules

`gpu.lua` and `monitors.lua` ship as comment-only or catch-all seeds and are
rewritten per machine by the hardware scripts:

- `gpu.lua` On a multi-GPU laptop, `ryoku-gpu` pins the strongest GPU
  (`AQ_DRM_DEVICES`) and disables hardware cursors for reverse-PRIME. Untouched on
  single-GPU machines.
- `monitors.lua` `ryoku-monitor` writes per-output rules scaled to each panel's
  pixel density (and matching `GDK_SCALE`). The catch-all seed keeps a fresh
  machine from ever being over-zoomed before that runs.

Both are required after the default environment so their managed values take
precedence.

## Startup

- Hands the Wayland session to systemd and D-Bus so screen sharing and file
  pickers work (the desktop portal needs this under plain Hyprland).
- A polkit agent for password prompts (`hyprpolkit-agent`, or `polkit-gnome`).
- `xdg-user-dirs-update` to create Documents, Downloads, Pictures, and friends.
- Best-effort `ryoku-monitor autoscale` and `ryoku-gpu persist`.

## Keybinds

`SUPER` is the main key. Highlights:

- `SUPER+Return` / `SUPER+T` terminal (kitty), `SUPER+E` files (nautilus),
  `SUPER+B` browser, `SUPER+N` editor, `SUPER+R` / `SUPER+Space` launcher.
- `SUPER+1..0` switch workspace; add `SHIFT` (follow) or `CTRL` to move a window.
- Arrows or `H/J/K/L` to move focus, with `SHIFT` to move the window.
- `Print` screenshots the screen, `SHIFT+Print` a region; both save to Pictures
  and copy to the clipboard.
- `SUPER+ALT+L` locks the screen.

Open `keybinds.lua` for the full list. The bottom of that file notes the
shortcuts left out of this pass (they belonged to the Ryoku shell).

## Editing

Change your keyboard layout in `keyboard.lua`, and put personal tweaks in
`custom.lua` (it is never overwritten). After any edit, reload with
`SUPER+SHIFT+R` or `hyprctl reload`.

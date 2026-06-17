# Ryoku

Ryoku is an Arch Linux desktop built around Hyprland. It ships a guided installer,
a Limine boot experience, and a small, deliberate set of tools so a fresh machine
comes up ready to use without the usual setup grind.

The name comes from the kanji 力 (chikara / ryoku): power, strength.

## How the repo is laid out

Three trees, each with its own README and changelog:

- `installation/` Everything that puts Ryoku on a machine: the live ISO, the
  guided installer (a terminal app), and the backend that partitions, encrypts,
  and lays down the system.
- `system/` How the installed machine is put together: package lists, the boot
  chain (Limine, Plymouth), hardware and GPU setup, display scaling, networking,
  and the services that run.
- `ryoku/` The desktop itself: the Hyprland config and keybinds, the lockscreen,
  the apps we ship and their settings, fonts, cursors, branding, and helpers.

## Status

This is a fresh rebuild. The first pass delivers a working install and a plain
Hyprland desktop with kitty, fastfetch, fish, and nautilus. The richer Ryoku
shell is intentionally left for a later pass.

## License

See `LICENSE` and `LICENSES/`. Third-party notices live in `NOTICE`.

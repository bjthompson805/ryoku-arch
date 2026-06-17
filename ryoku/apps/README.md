# apps/

The applications Ryoku ships and their settings, one folder per app. Each folder
maps to a place under `~/.config` (except the small helper script noted below).

## What's here

- `kitty/` The terminal. JetBrains Mono Nerd Font, a beam cursor, and fish as the
  shell. `kitty.conf` includes `current-theme.conf`, which carries the Ryoku dark
  palette (background `#171717`, foreground `#CCD0CF`, accent `#F25623`).
- `fastfetch/` The branded system readout. `config.jsonc` draws the 力 logo and a
  short list of facts (host, OS, kernel, WM, CPU, GPU, memory, disk, terminal,
  uptime). `ryoku-fastfetch` is a launcher that uses kitty's graphics protocol in
  kitty and falls back to chafa elsewhere.
- `fish/` The shell. The greeting is turned off so the login terminal stays
  clean, then it runs `ryoku-fastfetch` and wires up starship, zoxide, fzf, and a
  few eza listing aliases (each guarded so a missing tool is harmless).
- `starship/` The prompt: current directory, git branch, and command duration on
  a fixed Ryoku palette.
- `nautilus/` The file manager. No config to ship; see its README for how the
  home folders and optional defaults work.

## Install paths

| Folder       | Destination                                   |
| ------------ | --------------------------------------------- |
| `kitty/`     | `~/.config/kitty/`                            |
| `fastfetch/` | `~/.config/fastfetch/` (config + wrapper)     |
| `fish/`      | `~/.config/fish/config.fish`                  |
| `starship/`  | `~/.config/starship.toml`                     |

The `ryoku-fastfetch` wrapper must also land on `PATH` (for example
`~/.local/bin/ryoku-fastfetch`) so fish can call it on terminal start. It expects
the brand logo at `~/.local/share/ryoku/assets/brand/logo-mark.png`.

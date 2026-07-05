# Changelog: lockscreen/

## Unreleased

### Fixed
- The desktop no longer strands itself on a black lock screen after sleep. The
  ext-session-lock protocol wedges the whole session if the locker crashes while
  locked, which a GPU glitch on resume can trigger: the machine wakes to a black
  screen that eats every keypress and can't be dismissed (reported as "slept and
  won't wake up" and "keybinds don't register on the lock screen"). Hyprland now
  ships with `misc:allow_session_lock_restore` on from boot, so it accepts a
  fresh locker instead of stranding the session and `ryoku-shell lock` can relock
  and take the password. qylock only enabled it after a successful unlock, which
  is too late for the crash that happens before one.

### Added
- Vendored the qylock clockwork theme (orbital and tape variants) and the
  Quickshell lockscreen under `qylock/`, trimmed to only what Ryoku ships.
- Per-skin `preview.gif` for the Lockscreen section in Ryoku Settings: orbital
  reuses qylock's own clockwork preview (its dark-mode segment, to match the
  shipped `themeMode=dark`); tape is rendered from the skin itself. They deploy
  inside the themes dir, and `ryoku-hub lock list` reports their paths.
- `install-qylock`: offline installer for the SDDM greeter and the in-session
  lock. Installs the default skin under the fixed `/usr/share/sddm/themes/ryoku`
  name (the one the Hub overwrites when a skin is chosen) and writes
  `/etc/sddm.conf.d/99-ryoku.conf` (Current=ryoku), installs the Quickshell
  lockscreen to the user's home, links `themes_link`, and sets
  `~/.config/qylock/theme`. Resolves the login user under sudo and pkexec.
  Honors `RYOKU_DRYRUN=1` and `--dry-run`.
- `sddm/setup`: install-time SDDM wiring (enable sddm.service, default to
  graphical.target, strip pam_gnome_keyring from the SDDM PAM stack, ensure a
  Hyprland wayland session exists). Honors `RYOKU_DRYRUN=1` and `--dry-run`.

### Fixed
- In-session lock: skins that gate login and power behind `!isQuickshell`
  (notably `material-you` and `nothing`) left the password field, reboot, and
  shutdown dead under the Quickshell lock, since the shim omitted `sddm.hostName`
  and `isQuickshell` was always true. The shim now reports a real `sddm.hostName`
  (so `isQuickshell` is false), implements `sddm.suspend()`, and exposes SDDM's
  `keyboard` object, so every catalogue skin authenticates and powers off under
  the lock as it does under the SDDM greeter.

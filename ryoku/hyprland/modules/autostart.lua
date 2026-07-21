hl.on("hyprland.start", function()
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Ice 24")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme prefer-dark")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme Adwaita-dark")
    -- hyprpolkitagent.service gates on ConditionEnvironment=WAYLAND_DISPLAY, which
    -- is checked once at start time and never re-evaluated. Hyprland's own env
    -- import into the systemd --user manager can lose the race with the start
    -- calls below, so the condition fails, the unit is silently "skipped" (not
    -- "failed", so nothing surfaces), and no polkit agent ever runs for the
    -- session -- every pkexec call then hangs forever waiting for one.
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    -- The user manager is one persistent process across logins, so a previous
    -- session's agent can still be mid crash-loop when this one starts: its old
    -- Wayland connection just broke (compositor gone), it aborts instantly with
    -- no display to attach to, and repeats fast enough to hit start-limit-hit --
    -- which then also blocks the very "start" call below for the new session.
    -- reset-failed clears that stale lock before asking systemd to start it.
    hl.exec_cmd("systemctl --user reset-failed hyprpolkitagent")
    hl.exec_cmd("systemctl --user start hyprland-session.target")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("command -v ryoku-monitor >/dev/null 2>&1 && ryoku-monitor autoscale")
    hl.exec_cmd("command -v ryoku-gpu >/dev/null 2>&1 && ryoku-gpu persist")
    hl.exec_cmd("ryoku-shell daemon")
    hl.exec_cmd("command -v ryoku-idle >/dev/null 2>&1 && ryoku-idle start")
    hl.exec_cmd("command -v ryoku-leds >/dev/null 2>&1 && ryoku-leds apply")
    hl.exec_cmd("command -v ryoku-mic >/dev/null 2>&1 && ryoku-mic")
    -- Booted into a btrfs snapshot from the Limine menu: offer the one-click
    -- restore. limine-snapper-sync ships this as an XDG autostart entry, which
    -- Hyprland never runs (no autostart manager), so start it here; on a normal
    -- boot it detects no snapshot and exits silently.
    hl.exec_cmd("command -v limine-snapper-restore >/dev/null 2>&1 && limine-snapper-restore --notify")
    -- Voxtype dictation: `ryoku-hub voxtype ensure` seeds a default config with
    -- the built-in hotkey off (the shell owns Super+` and the mic wave), installs
    -- the user service once, and starts it unless you turned dictation off in the
    -- Hub. The shell then drives it with `voxtype record` on the Super+` tap.
    hl.exec_cmd("command -v voxtype >/dev/null 2>&1 && command -v ryoku-hub >/dev/null 2>&1 && ryoku-hub voxtype ensure >/dev/null 2>&1")
    -- First-login welcome walkthrough: show the guided tour once, then mark it
    -- seen so it never returns. The flag lives in state (not config), so it needs
    -- no doctor reconciler; an flock guards a double fire. The tour window quits on
    -- finish or close, then the flag is written only if qs actually ran the tour
    -- (`&&`), so a first-boot launch failure retries next login instead of marking
    -- it seen forever. exec is async, so the blocking `qs` never holds up autostart.
    local welcome_state = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state")) .. "/ryoku"
    hl.exec_cmd("[ -e '" .. welcome_state .. "/welcome-seen' ] || { flock -n \"${XDG_RUNTIME_DIR:-/tmp}/ryoku-welcome.lock\" qs -c welcome && mkdir -p '" .. welcome_state .. "' && touch '" .. welcome_state .. "/welcome-seen'; }")
end)

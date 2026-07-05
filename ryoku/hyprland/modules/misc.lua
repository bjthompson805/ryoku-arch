hl.config({
    misc = {
        -- keyboard focus follows an app's activation request, else a window mapping
        -- off the focused monitor comes up un-typeable (Discord, Vivaldi)
        focus_on_activate = true,
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
        -- keep a crashed lockscreen recoverable. the ext-session-lock protocol
        -- wedges the whole session if the locker (qylock/quickshell) dies while
        -- locked, which a GPU glitch on resume can trigger: the machine wakes to
        -- a black screen that eats every keypress and can't be dismissed ("slept
        -- and won't wake up", "keybinds don't register on the lock screen"). with
        -- this, Hyprland accepts a fresh locker instead of stranding the session,
        -- so ryoku-shell can relock and you can type your password. qylock only
        -- flips this on AFTER a successful unlock, too late for the crash before
        -- one; pin it on from boot.
        allow_session_lock_restore = true,
    },
    xwayland = {
        force_zero_scaling = true, -- XWayland (Chromium/Electron) crisp on HiDPI
    },
})

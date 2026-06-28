hl.config({
    misc = {
        -- keyboard focus follows an app's activation request, else a window mapping
        -- off the focused monitor comes up un-typeable (Discord, Vivaldi)
        focus_on_activate = true,
        disable_hyprland_logo = true,
        force_default_wallpaper = 0,
    },
    xwayland = {
        force_zero_scaling = true, -- XWayland (Chromium/Electron) crisp on HiDPI
    },
})

-- Ryoku Hyprland keybinds. Plain targets, no Ryoku shell. Required by hyprland.lua.

local terminal = "kitty"
local fileManager = "nautilus"
local yaziFileManager = "kitty -e yazi"
local browser = "chromium"
local neovimEditor = "kitty -e nvim"
local menu = "fuzzel"
-- qylock in-session lock launcher (kept; the upstream lock entrypoint).
local lock = "$HOME/.local/share/quickshell-lockscreen/lock.sh"

-- grim/slurp: save into the Pictures folder and copy to the clipboard in one pass.
local screenshotFull = [[grim - | tee "$(xdg-user-dir PICTURES)/Screenshot-$(date +%Y-%m-%d_%H-%M-%S).png" | wl-copy]]
local screenshotRegion = [[grim -g "$(slurp)" - | tee "$(xdg-user-dir PICTURES)/Screenshot-$(date +%Y-%m-%d_%H-%M-%S).png" | wl-copy]]

-- Applications
hl.bind("SUPER + Return", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + E", hl.dsp.exec_cmd(fileManager))
hl.bind("SUPER + ALT + E", hl.dsp.exec_cmd(yaziFileManager))
hl.bind("SUPER + B", hl.dsp.exec_cmd(browser))
hl.bind("SUPER + N", hl.dsp.exec_cmd(neovimEditor))
hl.bind("SUPER + R", hl.dsp.exec_cmd(menu))
hl.bind("SUPER + Space", hl.dsp.exec_cmd(menu))

-- Windows
hl.bind("SUPER + Q", hl.dsp.window.close())
hl.bind("ALT + F4", hl.dsp.window.close())
hl.bind("SUPER + SHIFT + Q", hl.dsp.window.close())
hl.bind("SUPER + F", hl.dsp.window.fullscreen())
hl.bind("SUPER + A", hl.dsp.window.float({ action = "toggle" }))
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Move window" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window" })

-- Move focus with arrows or vim keys
hl.bind("SUPER + left", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + up", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "down" }))
hl.bind("SUPER + H", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + J", hl.dsp.focus({ direction = "down" }))
hl.bind("SUPER + K", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + L", hl.dsp.focus({ direction = "right" }))

-- Move the window with arrows or vim keys
hl.bind("SUPER + SHIFT + left", hl.dsp.window.move({ direction = "left" }))
hl.bind("SUPER + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind("SUPER + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
hl.bind("SUPER + SHIFT + down", hl.dsp.window.move({ direction = "down" }))
hl.bind("SUPER + SHIFT + H", hl.dsp.window.move({ direction = "left" }))
hl.bind("SUPER + SHIFT + J", hl.dsp.window.move({ direction = "down" }))
hl.bind("SUPER + SHIFT + K", hl.dsp.window.move({ direction = "up" }))
hl.bind("SUPER + SHIFT + L", hl.dsp.window.move({ direction = "right" }))

-- Workspaces: SUPER+[1..0] focus, +SHIFT move the window there, +CTRL likewise.
for i = 1, 10 do
    local key = i % 10 -- 10 maps to the 0 key
    hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
    hl.bind("SUPER + CTRL + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Cycle workspaces with PageUp/Down and the mouse wheel
hl.bind("SUPER + Page_Up", hl.dsp.focus({ workspace = "e-1" }))
hl.bind("SUPER + Page_Down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Screenshots
hl.bind("Print", hl.dsp.exec_cmd(screenshotFull))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(screenshotRegion))
hl.bind("SUPER + S", hl.dsp.exec_cmd(screenshotRegion))

-- Media and hardware keys (work while idle/locked; volume and brightness repeat)
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Session
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))
hl.bind("SUPER + SHIFT + E", hl.dsp.exit())
hl.bind("SUPER + ALT + L", hl.dsp.exec_cmd(lock))

-- Intentionally dropped: these drove the Ryoku shell, which this plain pass does
-- not ship. Restore them when the shell returns. Flagged for maintainer review.
--   SUPER + V             clipboard history (shell IPC)
--   SUPER + G             game bar (shell IPC)
--   SUPER + comma         system settings panel (shell)
--   SUPER + X             plugins toggle (shell IPC)
--   SUPER + SHIFT + comma appearance settings GUI (shell)
--   SUPER + W             wallpaper switcher (no plain tool shipped yet)
--   SUPER + P             power menu (shell session; no wlogout shipped)
--   SUPER + ALT + O       Obsidian (not in the package set)

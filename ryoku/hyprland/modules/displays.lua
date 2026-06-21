-- Re-derive DPI scaling when a display is hotplugged, not only at login, and
-- paint the current wallpaper onto the new output so it never comes up blank.
-- The refresh waits for autoscale to settle the mode first, so awww caches the
-- image at the output's final resolution.
hl.on("monitor.added", function()
    hl.exec_cmd("command -v ryoku-monitor >/dev/null 2>&1 && ryoku-monitor autoscale")
    hl.exec_cmd("command -v ryoku-shell >/dev/null 2>&1 && { sleep 1; ryoku-shell wallpaper refresh; }")
end)

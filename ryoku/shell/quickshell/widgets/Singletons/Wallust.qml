pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The live wallust palette for the desktop widgets. wallust rewrites
 * ~/.cache/wallust/colors.json on every wallpaper change (see wallust.toml) and
 * this watches it, so a clock or weather card tinted from the palette retunes to
 * whatever is on screen. The defaults are the Ryoku brand palette, so widgets look
 * right before the first wallust run and never fall back to grey.
 *
 * `accent`/`accent2` are the two lead tints; `ramp`/`colorAt(t)` is the ordered
 * sweep the ring clock and gradients sample. Every tint is vivified so even a
 * muted wallpaper still reads as colour, matching the visualiser.
 */
Singleton {
    id: root

    readonly property color background: adapter.background
    readonly property color foreground: adapter.foreground
    readonly property color accent:  vivid(adapter.color4)
    readonly property color accent2: vivid(adapter.color5)

    // Shell-wide "Match wallpaper" toggle (shell.json) and the surface ramp it
    // drives: base is exactly the terminal background, the rest shift its value.
    readonly property bool  matchWallpaper: shellCfg.matchWallpaper
    readonly property color base:     background
    readonly property color elevated: tone(background, 0.05)
    readonly property color deep:     tone(background, -0.03)
    readonly property color line:     tone(background, 0.14)

    readonly property var ramp: [
        vivid(adapter.color1),
        vivid(adapter.color3),
        vivid(adapter.color2),
        vivid(adapter.color6),
        vivid(adapter.color4),
        vivid(adapter.color5)
    ]

    // Lift saturation and floor brightness so a tint reads as colour, not mud,
    // regardless of how desaturated the wallpaper's palette is. Greys (no
    // measurable hue) are only brightened, never tinted.
    function vivid(c) {
        var hue = c.hsvHue < 0 ? 0 : c.hsvHue;
        var sat = c.hsvSaturation < 0.06 ? 0 : Math.min(1, c.hsvSaturation * 1.2 + 0.06);
        return Qt.hsva(hue, sat, Math.max(c.hsvValue, 0.74), 1);
    }

    // Shift a colour's HSV value by dv (hue and saturation kept), for the ramp.
    function tone(c, dv) {
        var hue = c.hsvHue < 0 ? 0 : c.hsvHue;
        return Qt.hsva(hue, c.hsvSaturation, Math.max(0, Math.min(1, c.hsvValue + dv)), 1);
    }

    // Linear-interpolate the ramp at t in [0,1].
    function colorAt(t) {
        var s = root.ramp;
        var n = s.length;
        if (n === 0)
            return root.accent;
        if (n === 1)
            return s[0];
        var x = Math.max(0, Math.min(0.999999, t)) * (n - 1);
        var i = Math.floor(x);
        var f = x - i;
        var a = s[i];
        var b = s[i + 1];
        return Qt.rgba(a.r + (b.r - a.r) * f, a.g + (b.g - a.g) * f, a.b + (b.b - a.b) * f, 1);
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/wallust/colors.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property color background: "#16161e"
            property color foreground: "#c0caf5"
            property color color0: "#16161e"
            property color color1: "#f7768e"
            property color color2: "#9ece6a"
            property color color3: "#e0af68"
            property color color4: "#7aa2f7"
            property color color5: "#bb9af7"
            property color color6: "#7dcfff"
            property color color7: "#c0caf5"
            property color color8: "#414868"
            property color color9: "#f7768e"
            property color color10: "#9ece6a"
            property color color11: "#e0af68"
            property color color12: "#7aa2f7"
            property color color13: "#bb9af7"
            property color color14: "#7dcfff"
            property color color15: "#c0caf5"
        }
    }

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/shell.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        JsonAdapter {
            id: shellCfg
            property bool matchWallpaper: false
        }
    }
}

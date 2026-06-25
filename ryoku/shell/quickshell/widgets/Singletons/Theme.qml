pragma Singleton
import QtQuick
import Quickshell

/**
 * Design tokens shared by the desktop widgets: the brand constant, the type
 * family, and a small neutral ink ramp. Widgets sit directly on the wallpaper, so
 * their text is bright and cool by default and leans on Wallust for colour
 * accents; the brand orange stays fixed for the one deliberate highlight. Motion
 * matches the shell's morph curve (OutExpo), so a widget feels like the same
 * desktop as the pill.
 */
Singleton {
    // Brand: fixed, used sparingly (the one accent that never themes).
    readonly property color brand: "#F25623"

    // Neutral inks for text on an arbitrary wallpaper: bright, with soft and dim
    // steps. Designs pair these with a drop shadow for contrast on any backdrop.
    readonly property color ink:     "#f5f3ff"
    readonly property color inkSoft: "#d2d7ef"
    readonly property color inkDim:  "#9aa3c8"
    readonly property color shadow:  Qt.rgba(0, 0, 0, 0.55)

    // Carbon-dossier surface, for the desktop menu (chrome that should read as the
    // same shell as the pill): a cool near-black panel, a faint hairline for rules
    // and registration ticks, and a faint ink for eyebrow labels.
    readonly property color cardTop: Wallust.matchWallpaper ? Wallust.base : "#1a1b26"
    readonly property color cardBot: Wallust.matchWallpaper ? Wallust.deep : "#13131b"
    readonly property color hair:    Qt.rgba(245 / 255, 243 / 255, 255 / 255, 0.13)
    readonly property color faint:   Qt.rgba(245 / 255, 243 / 255, 255 / 255, 0.42)

    readonly property string font:   "Inter"
    readonly property string fontJp: "Noto Sans CJK JP"
    readonly property string mono:   "JetBrainsMono Nerd Font"

    // Motion: short and smooth; OutExpo mirrors the shell's open curve.
    readonly property int quick:  140
    readonly property int medium: 260
    readonly property int slow:   420
    readonly property int ease:   Easing.OutExpo
}

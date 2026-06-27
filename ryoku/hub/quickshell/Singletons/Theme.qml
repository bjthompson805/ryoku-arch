pragma Singleton
import QtQuick
import Quickshell

// Ryoku Settings palette. deep, warm near-black canvas so the brand orange reads
// as the one deliberate accent (力 mark, active section, focused search) and
// never a wash. warm neutral text, crisp not muddy. motion follows the shell's
// morph curve (cubic-bezier 0.16,1,0.3,1, approximated by OutExpo).
Singleton {
    // brand: sparingly, boldly.
    readonly property color brand:     "#F25623"
    readonly property color ember:     "#ff6a3d"
    readonly property color emberDeep: "#bf3c19"

    // log status accents (update console).
    readonly property color ok:        "#7fbf6a"
    readonly property color bad:       "#e05a5a"

    // canvas + surfaces. flat; depth comes from hairlines, not gradients.
    readonly property color bgTop:    "#1b1612"
    readonly property color bgBot:    "#140f0c"
    readonly property color rail:     "#171210"
    readonly property color surface:  "#241c16"
    readonly property color surfaceLo:"#1c1510"
    readonly property color keyTop:   "#2a211a"
    readonly property color keyBot:   "#1d160f"
    readonly property color line:     "#322720"
    readonly property color lineSoft: Qt.rgba(236 / 255, 214 / 255, 198 / 255, 0.06)

    // profile card specimen = trading-card surface in the hub's warm palette.
    // twin of the shell card's cool tokens (cardTop/cardBot/frameBg/hair).
    readonly property color cardTop:  "#241b14"
    readonly property color cardBot:  "#15100c"
    readonly property color frameBg:  Qt.rgba(242 / 255, 86 / 255, 35 / 255, 0.10)
    readonly property color hair:     Qt.rgba(236 / 255, 214 / 255, 198 / 255, 0.12)

    // text (warm neutrals).
    readonly property color bright:   "#f4ece5"
    readonly property color cream:    "#ddccc0"
    readonly property color subtle:   "#b0a197"
    readonly property color dim:      "#83766c"
    readonly property color faint:    "#5c5249"
    readonly property color onAccent: "#fdeee6"

    readonly property string font:   "Inter"
    readonly property string fontJp: "Noto Sans CJK JP"
    readonly property string mono:   "JetBrainsMono Nerd Font"

    // motion. short + smooth; OutExpo mirrors the shell's open curve.
    readonly property int quick:  120
    readonly property int medium: 240
    readonly property int slow:   360
    readonly property int ease:   Easing.OutExpo
}

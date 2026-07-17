pragma Singleton

import QtQuick
import Quickshell

// The one place Ryoku's look is defined. Everything that draws imports this;
// nothing hardcodes a hex, a size or a duration.
//
// Paper and ink are sampled off the reference sheet, not invented: the black is
// #000000 carrying grain at +/-8 levels (the grain is what makes it read matte,
// not a lifted black), and the ink is a warm bone at 73% luminance. A pure white
// ink glows and kills the matte.
//
// The ramp is contrast-solved against the paper, not eyeballed. Ratios are in
// the comments; nothing here sits below 4.5:1, so any text is legible at any
// tier. If you add a tier, solve it -- do not guess a hex.
Singleton {
    id: t

    // ── paper ────────────────────────────────────────────────────────────
    readonly property color paper: "#000000"
    readonly property color paperLift: "#0a0a0a"   // a raised block, barely

    // ── ink, on paper ────────────────────────────────────────────────────
    readonly property color ink: "#cdc4ba"       // 12.0:1  values, titles, fills
    readonly property color inkDim: "#b0a9a0"    //  9.0:1  nav, body, unselected labels
    readonly property color inkMuted: "#958f87"  //  6.6:1  descriptions, cell labels
    readonly property color inkFaint: "#7a756e"  //  4.6:1  source tags, counts, struck defaults

    // ── bone stock (inverted) ────────────────────────────────────────────
    // Inversion is the emphasis mechanism -- the job colour does elsewhere.
    // The stock flips exactly: the ink becomes the paper, no third value.
    // Bone carries at most TWO ink levels: 50% black on bone measures 3.9:1
    // and fails AA, so there is no third tier to reach for. Keep bone simple.
    readonly property color bone: t.ink
    readonly property color inkOnBone: "#000000"                 // 12.0:1
    readonly property color inkOnBoneDim: Qt.rgba(0, 0, 0, 0.62) //  5.4:1
    readonly property color lineOnBone: Qt.rgba(0, 0, 0, 0.26)

    // ── hairlines and tints ──────────────────────────────────────────────
    readonly property color line: Qt.rgba(205 / 255, 196 / 255, 186 / 255, 0.26)
    readonly property color lineSoft: Qt.rgba(205 / 255, 196 / 255, 186 / 255, 0.13)
    readonly property color lineStrong: Qt.rgba(205 / 255, 196 / 255, 186 / 255, 0.42)
    readonly property color tint5: Qt.rgba(205 / 255, 196 / 255, 186 / 255, 0.05)   // surface hover
    readonly property color tint10: Qt.rgba(205 / 255, 196 / 255, 186 / 255, 0.10)  // control hover
    readonly property color tint16: Qt.rgba(205 / 255, 196 / 255, 186 / 255, 0.16)  // pressed

    // ── colour ───────────────────────────────────────────────────────────
    // There is none in app chrome. Not for errors, not for destructive verbs:
    // a destructive confirm is a bone plate and an unambiguous word, which the
    // hazard-label reference proves reads as more serious, not less. The two
    // exceptions are data, not decoration -- art manufactures its own sun, and
    // a colour swatch's job is to be its colour. `sun` is here so art and the
    // frame can name the brand; no app surface may fill with it.
    readonly property color sun: "#e2342a"
    readonly property color sunDeep: "#b81f19"

    // ── type ─────────────────────────────────────────────────────────────
    // Fraunces carries display. Space Grotesk carries everything a human reads
    // as language -- labels, values, numerals, body. Space Mono is demoted to
    // what is genuinely tabular: config keys, ranges, defaults, file paths,
    // ids. Setting the whole UI in mono is what made an earlier pass read as a
    // terminal instead of a printed instrument.
    readonly property string display: "Fraunces"
    readonly property string ui: "Space Grotesk"
    readonly property string mono: "SpaceMono Nerd Font"
    readonly property string jp: "Noto Sans CJK JP"

    readonly property int fTitle: 46    // page title, Fraunces
    readonly property int fHero: 34     // a headline readout
    readonly property int fValue: 26    // a cell's value
    readonly property int fRow: 15      // a row name
    readonly property int fBody: 14
    readonly property int fSmall: 13    // descriptions
    readonly property int fMicro: 11    // tracked labels
    readonly property int fTiny: 9      // corner tags, struck defaults

    readonly property real trackLabel: 1.4   // letter-spacing for micro labels
    readonly property real trackMark: 2.2    // for eyebrows and section marks

    // ── space ────────────────────────────────────────────────────────────
    readonly property int s1: 4
    readonly property int s2: 8
    readonly property int s3: 12
    readonly property int s4: 16
    readonly property int s5: 24
    readonly property int s6: 32
    readonly property int s7: 48

    // ── geometry ─────────────────────────────────────────────────────────
    // A hair of rounding, not a pill. Only true circles (status dots, toggle
    // knobs) are round. Depth is a hairline; a shadow is only allowed where
    // something genuinely floats over something else (a popup, a drawer).
    readonly property int radius: 2
    readonly property real border: 1
    readonly property int rowH: 48
    readonly property int cellH: 104
    readonly property int railW: 268
    readonly property int ctlH: 26

    // ── motion ───────────────────────────────────────────────────────────
    // Mechanical. A machine snaps; it does not drift. The shell's Motion
    // singleton runs 300-500ms with spring overshoot, which is right for a
    // blob melting and wrong for a control answering a click.
    readonly property int snap: 90     // hover, press, state flip
    readonly property int move: 170    // a selector travelling
    readonly property int swap: 210    // content exchanging
    readonly property int flap: 110    // a value changing
    readonly property int ease: Easing.OutCubic
    readonly property int easeSnap: Easing.OutQuad

    // ── grain ────────────────────────────────────────────────────────────
    readonly property real grainOpacity: 0.055
}

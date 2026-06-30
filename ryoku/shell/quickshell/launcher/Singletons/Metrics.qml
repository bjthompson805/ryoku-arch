pragma Singleton
import QtQuick
import Quickshell

// Layout tokens for the launcher, so spacing/sizing live in one place instead of
// scattered literals. Base pixels at 1080p; components multiply by the per-monitor
// scale where they read them, matching the pill's convention.
Singleton {
    readonly property real windowW:      720
    readonly property real searchHeight: 52
    readonly property real rowHeight:    44
    readonly property real iconSize:     26
    readonly property real tileSize:     108
    readonly property int  gridColumns:  6

    readonly property real padOuter:  18
    readonly property real padRow:    12
    readonly property real gapRow:    2
    readonly property real gapTab:    20

    readonly property real radiusWindow: 18
    readonly property real radiusRow:    10
    readonly property real radiusTag:    6
    readonly property real radiusGlyph:  16

    readonly property int  fontTitle:    14
    readonly property int  fontSubtitle: 11
    readonly property int  fontEyebrow:  10
    readonly property int  fontSearch:   15
    readonly property int  fontSection:  14

    // results past this scroll; keeps the keystroke->paint budget bounded.
    readonly property int  maxResults:   40
}

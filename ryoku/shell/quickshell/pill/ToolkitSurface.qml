pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Singletons"

/**
 * The screen-tool surface grown from the pill centre (Super+D). Four tiles run
 * self-contained ~/.config/hypr/scripts helpers and dismiss the surface so the
 * action has the whole screen: Lens uploads a region to Google Lens, Color picks
 * a screen colour, OCR copies recognised text, and Mirror toggles a flipped
 * webcam self-view. A Ryoku wave signature fills under the tiles on open, in
 * place of the docked bead.
 */
PillSurface {
    id: root

    mTop: 14
    mLeft: 20
    mRight: 20
    mBottom: 14

    ameForm: "off"

    implicitHeight: tiles.height + 9 * root.s + waveSig.height

    readonly property string scripts: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/"

    readonly property var tools: [
        { key: "lens",   glyph: "lens",       label: "Lens",   argv: [root.scripts + "ryoku-cmd-google-lens"] },
        { key: "color",  glyph: "eyedropper", label: "Color",  argv: [root.scripts + "ryoku-cmd-color-picker"] },
        { key: "ocr",    glyph: "ocr",        label: "OCR",    argv: [root.scripts + "ryoku-cmd-ocr"] },
        { key: "mirror", glyph: "webcam",     label: "Mirror", argv: [root.scripts + "ryoku-cmd-mirror"] }
    ]

    property string hovered: ""

    // Tools that grab the screen (slurp region, hyprpicker freeze) need the
    // overlay gone first: it holds exclusive keyboard focus and would otherwise
    // be frozen into the pick. Close, let the morph settle, then launch.
    property var pendingArgv: null

    function launch(argv) {
        root.pendingArgv = argv;
        root.requestClose();
        launchTimer.restart();
    }

    Timer {
        id: launchTimer
        interval: 400
        onTriggered: {
            if (root.pendingArgv) {
                Quickshell.execDetached(root.pendingArgv);
                root.pendingArgv = null;
            }
        }
    }

    Item {
        id: tiles
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56 * root.s

        Row {
            id: tileRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 48 * root.s

            Repeater {
                model: root.tools

                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index

                    readonly property bool lit: root.hovered === tile.modelData.key

                    width: 38 * root.s
                    height: 56 * root.s

                    Rectangle {
                        id: btn
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 38 * root.s
                        height: 38 * root.s
                        radius: (Motion.rTile - 2) * root.s
                        color: tile.lit ? Theme.frameBg : "transparent"
                        border.width: 1
                        border.color: tile.lit ? Theme.frameBorder : Theme.border

                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }

                        GlyphIcon {
                            anchors.centerIn: parent
                            width: 14 * root.s
                            height: 14 * root.s
                            name: tile.modelData.glyph
                            color: tile.lit ? Theme.cream : Theme.iconDim
                            stroke: 1.6
                        }
                    }

                    Text {
                        anchors.top: btn.bottom
                        anchors.topMargin: 5 * root.s
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.modelData.label
                        color: tile.lit ? Theme.cream : Theme.subtle
                        font.family: Theme.font
                        font.pixelSize: 9.5 * root.s
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.hovered = tile.modelData.key
                        onExited: if (root.hovered === tile.modelData.key) root.hovered = ""
                        onClicked: root.launch(tile.modelData.argv)
                    }
                    Rectangle {
                        visible: tile.index < root.tools.length - 1
                        width: 1
                        height: 22 * root.s
                        color: Theme.faint
                        opacity: 0.55
                        x: tile.width + (tileRow.spacing - width) / 2
                        y: (btn.height - height) / 2
                    }
                }
            }
        }
    }

    WaveMeter {
        id: waveSig
        anchors.top: tiles.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        frac: root.open ? 1 : 0
    }
}

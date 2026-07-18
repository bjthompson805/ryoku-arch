import QtQuick
import Quickshell
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// In-app settings: the Wallhaven API key, the NSFW gate (only with a key), and
// where downloads land. An overlay in the standard grammar: paperLift fill,
// lineStrong border, radius 2, scrim at black 55%.
Item {
    id: sp
    property bool open: false
    signal closed()

    // re-probe on open so a just-installed upscaler flips Install to a live toggle.
    onOpenChanged: if (open) Wallhaven.refreshCaps()

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Tokens.snap } }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        TapHandler { onTapped: sp.closed() }
    }

    Rectangle {
        anchors.centerIn: parent
        width: 460
        height: col.implicitHeight + 2 * Tokens.s5
        radius: Tokens.radius
        color: Tokens.paperLift
        border.width: Tokens.border
        border.color: Tokens.lineStrong
        TapHandler {}

        Column {
            id: col
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.s5
            spacing: Tokens.s5

            Item {
                width: parent.width
                height: 26
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SETTINGS"
                    color: Tokens.ink
                    font.family: Tokens.ui
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    font.letterSpacing: Tokens.trackMark
                }
                IconBtn {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "✕"
                    onAct: sp.closed()
                }
            }

            Column {
                width: parent.width
                spacing: Tokens.s2
                Text { text: "Wallhaven API key"; color: Tokens.inkDim; font.family: Tokens.ui; font.pixelSize: 13; font.weight: Font.Medium }
                Field {
                    width: parent.width
                    tabular: true
                    placeholder: "paste your key"
                    text: Wallhaven.settings.apiKey
                    onEdited: (v) => Wallhaven.settings.apiKey = v
                    onCommitted: Wallhaven.saveSettings()
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Optional, from wallhaven.cc/settings/account. Raises rate limits and unlocks NSFW."
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: 12
                }
            }

            Item {
                width: parent.width
                height: 24
                Text { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; text: "Show NSFW"; color: Tokens.inkDim; font.family: Tokens.ui; font.pixelSize: 13; font.weight: Font.Medium }
                Sw {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: Wallhaven.apiKey.length > 0
                    opacity: Wallhaven.apiKey.length > 0 ? 1 : 0.3
                    on: Wallhaven.settings.nsfw
                    onToggled: (v) => {
                        Wallhaven.settings.nsfw = v;
                        Wallhaven.saveSettings();
                        if (!Wallhaven.searching) Wallhaven.searchTop(Wallhaven.topRange);
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Tokens.line }

            Item {
                width: parent.width
                height: 34
                Column {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: "Downloads"; color: Tokens.inkDim; font.family: Tokens.ui; font.pixelSize: 13; font.weight: Font.Medium }
                    Text { text: "~/Pictures/Wallpapers"; color: Tokens.inkFaint; font.family: Tokens.mono; font.pixelSize: 11 }
                }
                Btn {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "OPEN"
                    onAct: Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/Pictures/Wallpapers"])
                }
            }
        }
    }
}

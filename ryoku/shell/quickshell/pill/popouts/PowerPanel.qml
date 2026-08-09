pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../Singletons"

// The power/session panel: a live wallpaper hero over an identity + actions
// strip, painted straight onto the popout's blob surface -- the blob IS the
// surface, so this paints no fill of its own (that would double it). The
// hero is the one splash of colour (data, the desktop's skin); identity and
// uptime read on the left, session actions on the right. Replaces the old
// glyph-column Power popout.
Item {
    id: root

    property real s: 1
    property bool open: false
    signal closeRequested()

    readonly property real cardW: 640 * root.s
    readonly property real heroH: 260 * root.s
    readonly property real stripH: 132 * root.s
    implicitWidth: cardW
    implicitHeight: heroH + stripH

    readonly property var actions: [
        { glyph: "lock",     label: "Lock",     confirm: false, dispatch: "",              argv: ["ryoku-shell", "lock"] },
        { glyph: "suspend",  label: "Sleep",    confirm: false, dispatch: "",              argv: ["systemctl", "suspend"] },
        { glyph: "logout",   label: "Logout",   confirm: true,  dispatch: "hl.dsp.exit()", argv: [] },
        { glyph: "reboot",   label: "Restart",  confirm: true,  dispatch: "",              argv: ["systemctl", "reboot"] },
        { glyph: "shutdown", label: "Shutdown", confirm: true,  dispatch: "",              argv: ["systemctl", "poweroff"] }
    ]

    // matches blobGroup's own fill (shell.qml) so the hero's foot fades into
    // the frame surface it sits on, not some unrelated colour.
    readonly property color frameFill: Config.matchWallpaper ? Wallust.surface : Config.surfaceColor

    // absorb clicks on the panel body so they never fall through the blob.
    MouseArea { anchors.fill: parent }

    // ── hero: the live wallpaper ──────────────────────────────────────────
    WallpaperHero {
        id: hero
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.heroH
        active: root.open
        path: Session.wallpaper
        isVideo: Session.wallIsVideo
        poster: Session.livePoster

        // fade the hero's foot into the strip so hero and strip read as one body.
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 96 * root.s
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: root.frameFill }
            }
        }
    }

    // hairline seam between hero and strip.
    Rectangle {
        anchors { left: parent.left; right: parent.right }
        y: root.heroH
        height: 1
        color: Theme.border
    }

    // ── strip: identity (left) + actions (right) ──────────────────────────
    Item {
        id: strip
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: root.stripH

        // identity block: width bounded against the actions row so a long
        // "user@hostname" wraps instead of running under the action tiles.
        Item {
            id: identity
            anchors {
                left: parent.left; right: actionsRow.left
                verticalCenter: parent.verticalCenter
                leftMargin: 22 * root.s; rightMargin: 16 * root.s
            }
            height: idCol.height

            BrandMark {
                id: mark
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                size: 30 * root.s
                color: Theme.bright
            }

            Column {
                id: idCol
                anchors {
                    left: mark.right; leftMargin: 14 * root.s
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                spacing: 4 * root.s
                Text {
                    text: Session.user
                    color: Theme.bright; font.family: Theme.display
                    font.pixelSize: 22 * root.s; font.capitalization: Font.Capitalize
                }
                Text {
                    width: parent.width
                    text: Session.user + "@" + Session.host
                    color: Theme.subtle; font.family: Theme.mono
                    font.pixelSize: 11 * root.s
                    wrapMode: Text.Wrap
                }
                Text {
                    text: "UP " + Session.uptimeText
                    color: Theme.faint; font.family: Theme.mono
                    font.pixelSize: 11 * root.s
                    font.capitalization: Font.AllUppercase; font.letterSpacing: 1
                }
            }
        }

        // session actions, right-aligned and vertically centred.
        Row {
            id: actionsRow
            anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 18 * root.s }
            spacing: 6 * root.s
            Repeater {
                model: root.actions
                delegate: PowerAction {
                    required property var modelData
                    s: root.s
                    glyph: modelData.glyph
                    label: modelData.label
                    confirm: modelData.confirm
                    argv: modelData.argv
                    dispatch: modelData.dispatch
                    onRan: root.closeRequested()
                }
            }
        }
    }
}

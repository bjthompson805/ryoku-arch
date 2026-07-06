pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "Singletons"

// bar content riding one of the frame's thickened edges. the chosen edge
// swells into a band (BlobInvertedRect in shell.qml) and this draws the
// options directly on it, in the frame's own scene: no separate program, no
// seam. modules sit on BarPlate slabs (sharp washi plates or fully rounded
// capsules, per Config.barStyle) that lift on hover.
//
// top/bottom = the horizontal composition: seal + workspace strip + focused
// title on the left, the clock (the anchor a summoned surface drops from,
// top bar only) in the centre, now-playing + status + tray + power on the
// right. left/right = the caelestia composition: seal and workspaces at the
// top, stacked clock in the middle, art + status + tray + power falling to
// the bottom. a wheel over bare band nudges the sink volume either way.
Item {
    id: bar

    required property real s
    // which frame edge carries the band: top | bottom | left | right.
    property string position: "top"
    // the frame's own visible edge thickness and the band it swelled by;
    // content centres in the band, clear of the frame's outer lip.
    property real frameEdge: 0
    property real band: 0
    // window the tray menus anchor to.
    required property var trayWindow
    // a summoned surface drops out of a top bar over the centre; the clock
    // fades under it so the two never overprint.
    property bool surfaceOpen: false

    signal calendarRequested()
    signal powerRequested()
    signal surfaceRequested(string name)

    readonly property bool vertical: position === "left" || position === "right"
    readonly property real plateSpan: Math.round(bar.band * 0.78)

    // quickshell's refreshWorkspaces/refreshMonitors parse nothing out of
    // this Hyprland's IPC, so Hyprland.focusedWorkspace stays null on a
    // fresh instance until the first workspace event. seed the highlight
    // once from hyprctl; events own it from the first real switch.
    property int seedWsId: -1
    readonly property int activeWsId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : seedWsId

    Process {
        running: true
        command: ["hyprctl", "activeworkspace", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { bar.seedWsId = JSON.parse(text).id; } catch (e) {}
            }
        }
    }

    // wheel anywhere on the bare band = sink volume. plates sit above this
    // handler and take their own wheel where they care (workspaces, media).
    readonly property var sink: Pipewire.defaultAudioSink
    function nudgeVolume(steps) {
        if (!sink || !sink.audio)
            return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + steps * 0.03));
    }
    WheelHandler {
        onWheel: (w) => bar.nudgeVolume(w.angleDelta.y > 0 ? 1 : -1)
    }

    // the band area content occupies: inset from the frame's outer lip so the
    // options read as riding the band, not the screen edge.
    Item {
        id: face
        x: bar.position === "left" ? bar.frameEdge : 0
        y: bar.position === "top" ? bar.frameEdge : 0
        width: bar.vertical ? bar.band : bar.width
        height: bar.vertical ? bar.height : bar.band

        // ---- horizontal composition (top / bottom) ----------------------
        Row {
            visible: !bar.vertical
            anchors.left: parent.left
            anchors.leftMargin: 26 * bar.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * bar.s

            BarPlate {
                anchors.verticalCenter: parent.verticalCenter
                s: bar.s
                height: bar.plateSpan
                padX: 9 * bar.s
                onTapped: Quickshell.execDetached(["ryoku-shell", "launcher"])

                Text {
                    text: "力"
                    color: Theme.brand
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 13 * bar.s
                }
            }

            BarPlate {
                anchors.verticalCenter: parent.verticalCenter
                s: bar.s
                height: bar.plateSpan
                padX: 7 * bar.s
                interactive: false

                BarWorkspaces {
                    s: bar.s
                    activeWsId: bar.activeWsId
                }
            }

            // focused-window title, live via foreign-toplevel (Hyprland's
            // model deliberately skips title events to avoid refresh spam).
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: Config.barShowTitle && text.length > 0
                width: Math.min(implicitWidth, 340 * bar.s)
                elide: Text.ElideRight
                leftPadding: 6 * bar.s
                text: ToplevelManager.activeToplevel ? (ToplevelManager.activeToplevel.title || "") : ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 10.5 * bar.s
                font.weight: Font.Medium
            }
        }

        BarPlate {
            id: clockPlate
            visible: !bar.vertical
            anchors.centerIn: parent
            s: bar.s
            height: bar.plateSpan
            padX: 12 * bar.s
            opacity: bar.surfaceOpen ? 0 : 1
            interactive: !bar.surfaceOpen
            Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
            onTapped: bar.calendarRequested()

            BarClock {
                s: bar.s
            }
        }

        Row {
            visible: !bar.vertical
            anchors.right: parent.right
            anchors.rightMargin: 26 * bar.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * bar.s

            BarPlate {
                anchors.verticalCenter: parent.verticalCenter
                s: bar.s
                height: bar.plateSpan
                visible: Config.barShowMedia && hMedia.present
                onTapped: hMedia.toggle()
                onWheeled: (steps) => bar.nudgeVolume(steps)

                BarMedia {
                    id: hMedia
                    s: bar.s
                }
            }

            BarPlate {
                anchors.verticalCenter: parent.verticalCenter
                s: bar.s
                height: bar.plateSpan
                visible: Config.barShowStatus
                interactive: false

                BarStatus {
                    s: bar.s
                    onRequestSurface: (name) => bar.surfaceRequested(name)
                }
            }

            BarPlate {
                anchors.verticalCenter: parent.verticalCenter
                s: bar.s
                height: bar.plateSpan
                visible: hTray.count > 0
                quiet: true
                interactive: false

                BarTray {
                    id: hTray
                    s: bar.s
                    trayWindow: bar.trayWindow
                    menuEdgeY: bar.height
                }
            }

            BarPlate {
                anchors.verticalCenter: parent.verticalCenter
                s: bar.s
                height: bar.plateSpan
                padX: 9 * bar.s
                quiet: true
                onTapped: bar.powerRequested()

                GlyphIcon {
                    width: 14 * bar.s
                    height: 14 * bar.s
                    name: "shutdown"
                    color: Theme.dim
                    stroke: 1.7
                }
            }
        }

        // ---- vertical composition (left / right) ------------------------
        Column {
            visible: bar.vertical
            anchors.top: parent.top
            anchors.topMargin: 22 * bar.s
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8 * bar.s

            BarPlate {
                anchors.horizontalCenter: parent.horizontalCenter
                s: bar.s
                vertical: true
                width: bar.plateSpan
                padY: 8 * bar.s
                onTapped: Quickshell.execDetached(["ryoku-shell", "launcher"])

                Text {
                    text: "力"
                    color: Theme.brand
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 13 * bar.s
                }
            }

            BarPlate {
                anchors.horizontalCenter: parent.horizontalCenter
                s: bar.s
                vertical: true
                width: bar.plateSpan
                padY: 7 * bar.s
                interactive: false

                BarWorkspaces {
                    s: bar.s
                    vertical: true
                    activeWsId: bar.activeWsId
                }
            }
        }

        BarPlate {
            visible: bar.vertical
            anchors.centerIn: parent
            s: bar.s
            vertical: true
            width: bar.plateSpan
            padY: 9 * bar.s
            onTapped: bar.calendarRequested()

            BarClock {
                s: bar.s
                vertical: true
            }
        }

        Column {
            visible: bar.vertical
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 22 * bar.s
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8 * bar.s

            BarPlate {
                anchors.horizontalCenter: parent.horizontalCenter
                s: bar.s
                vertical: true
                width: bar.plateSpan
                visible: Config.barShowMedia && vMedia.present
                onTapped: vMedia.toggle()
                onWheeled: (steps) => bar.nudgeVolume(steps)

                BarMedia {
                    id: vMedia
                    s: bar.s
                    vertical: true
                }
            }

            BarPlate {
                anchors.horizontalCenter: parent.horizontalCenter
                s: bar.s
                vertical: true
                width: bar.plateSpan
                padY: 9 * bar.s
                visible: Config.barShowStatus
                interactive: false

                BarStatus {
                    s: bar.s
                    vertical: true
                    onRequestSurface: (name) => bar.surfaceRequested(name)
                }
            }

            BarPlate {
                anchors.horizontalCenter: parent.horizontalCenter
                s: bar.s
                vertical: true
                width: bar.plateSpan
                visible: vTray.count > 0
                quiet: true
                interactive: false

                BarTray {
                    id: vTray
                    s: bar.s
                    vertical: true
                    trayWindow: bar.trayWindow
                    menuEdgeY: 0
                }
            }

            BarPlate {
                anchors.horizontalCenter: parent.horizontalCenter
                s: bar.s
                vertical: true
                width: bar.plateSpan
                padY: 8 * bar.s
                quiet: true
                onTapped: bar.powerRequested()

                GlyphIcon {
                    width: 14 * bar.s
                    height: 14 * bar.s
                    name: "shutdown"
                    color: Theme.dim
                    stroke: 1.7
                }
            }
        }
    }
}

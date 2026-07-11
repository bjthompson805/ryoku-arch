import QtQuick
import "Singletons"

// The machine specimen: a brutalist carbon stage (hard offset shadow, hairline
// border, a registration crosshair) carrying the guest's mark, a power-state
// line, and a live dossier of the real machine, the guest, cores, memory, disk
// footprint and the SPICE / SSH endpoints once it is running. The hero of the
// detail pane; it informs rather than decorates. A true-circle status dot is the
// only motion, and only while the VM runs.
Item {
    id: stage

    property string guest: "linux"
    property string os: ""
    property bool running: false
    property string mode: "gtk"
    property string ssh: ""
    property string spice: ""
    property string cores: "auto"
    property string ram: "auto"
    property real diskUsed: 0
    property string diskCap: ""

    // one dossier line: a mono uppercase key and its value.
    component Spec: Row {
        id: sp
        property string k: ""
        property string v: ""
        property color vc: Theme.cream
        property bool show: true
        visible: sp.show
        width: parent ? parent.width : 0
        Text {
            width: 66
            text: sp.k
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1.4
            font.capitalization: Font.AllUppercase
        }
        Text {
            width: sp.width - 66
            elide: Text.ElideRight
            text: sp.v
            color: sp.vc
            font.family: Theme.mono
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    BrutalPanel {
        anchors.fill: parent
        step: Theme.shadowStep
        surface: Theme.rail
        line: stage.running ? Qt.alpha(Theme.ember, 0.55) : Theme.lineStrong
        Behavior on line { ColorAnimation { duration: Theme.medium } }

        // registration crosshair: poster chrome, warms with the accent when live.
        RegMark {
            x: parent.width - width - 16
            y: 15
            size: 12
            tint: stage.running ? Qt.alpha(Theme.ember, 0.7) : Theme.faint
            Behavior on tint { ColorAnimation { duration: Theme.medium } }
        }

        // left: the guest mark on a bordered square, then the power state.
        Column {
            id: left
            anchors.left: parent.left
            anchors.leftMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            spacing: 14
            width: 92

            Rectangle {
                width: 92
                height: 92
                color: Qt.alpha(Theme.cream, 0.03)
                border.width: 1
                border.color: stage.running ? Qt.alpha(Theme.ember, 0.5) : Theme.line
                Behavior on border.color { ColorAnimation { duration: Theme.medium } }
                OsIcon {
                    anchors.centerIn: parent
                    width: 54
                    height: 54
                    size: 54
                    slug: stage.os
                    label: stage.os.length > 0 ? stage.os : stage.guest
                    glyphTint: stage.running ? Theme.ember : Theme.subtle
                }
            }
            Row {
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    radius: 4
                    color: stage.running ? Theme.ok : Theme.faint
                    SequentialAnimation on opacity {
                        running: stage.running
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.3; duration: 900; easing.type: Easing.InOutSine }
                        NumberAnimation { from: 0.3; to: 1; duration: 900; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: stage.running ? "POWERED ON" : "POWERED OFF"
                    color: stage.running ? Theme.ok : Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.5
                }
            }
        }

        // a vertical hairline splits the mark from the dossier.
        Rectangle {
            anchors.left: left.right
            anchors.leftMargin: 26
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: parent.height * 0.6
            color: Theme.line
        }

        // right: the real machine, read from the conf and the live run state.
        Column {
            anchors.left: left.right
            anchors.leftMargin: 52
            anchors.right: parent.right
            anchors.rightMargin: 26
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9

            Spec { k: "Guest"; v: stage.guest }
            Spec {
                k: "CPU"
                v: stage.cores === "auto" ? "Automatic"
                    : stage.cores + (parseInt(stage.cores) === 1 ? " core" : " cores")
            }
            Spec { k: "Memory"; v: stage.ram === "auto" ? "Automatic" : stage.ram }
            Spec {
                k: "Disk"
                v: stage.diskUsed > 0
                    ? (Vm.human(stage.diskUsed) + (stage.diskCap.length > 0 ? "  /  " + stage.diskCap : " used"))
                    : (stage.diskCap.length > 0 ? stage.diskCap + " (empty)" : "not created")
            }
            Spec { k: "Mode"; v: ({ "gtk": "Window", "spice": "SPICE", "none": "Headless" })[stage.mode] || stage.mode }
            Spec { k: "SPICE"; v: "localhost:" + stage.spice; vc: Theme.ember; show: stage.running && stage.spice.length > 0 }
            Spec { k: "SSH"; v: "localhost:" + stage.ssh; vc: Theme.ember; show: stage.running && stage.ssh.length > 0 }
        }
    }
}

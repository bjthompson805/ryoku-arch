pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// GPU specimen card: the machine's two GPUs and the one Ryoku draws on, in the
// Profile idiom (warm carbon gradient, hairline border). read-only; fed by the
// `caps` object from `ryoku-hub gpu caps`. the passthrough verdict lives in the
// Graphics tab, not here -- this card is the calm hardware picture.
Item {
    id: root

    property var caps: ({})
    property real cardWidth: 360
    width: cardWidth
    implicitWidth: cardWidth
    implicitHeight: card.height

    // the GPU wired to the display drives both the desktop and a windowed VM.
    readonly property var renderGpu: {
        var p = root.caps.passthrough, h = root.caps.host;
        if (p && p.drivesDisplay)
            return p;
        if (h && h.drivesDisplay)
            return h;
        return h || p || null;
    }

    component GpuLine: Row {
        id: line
        property string tag: ""
        property var gpu: null
        visible: line.gpu !== null && line.gpu !== undefined
        width: parent ? parent.width : 0
        spacing: 11

        Rectangle {
            width: 46
            height: 20
            radius: 5
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.surfaceLo
            border.width: 1
            border.color: Theme.line
            Text {
                anchors.centerIn: parent
                text: line.tag
                color: Theme.subtle
                font.family: Theme.mono
                font.pixelSize: 9
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }
        }
        Column {
            width: line.width - 57
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                text: line.gpu ? line.gpu.model : ""
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                text: line.gpu ? (line.gpu.vramMb + " MB · " + line.gpu.driver + (line.gpu.drivesDisplay ? " · drives display" : " · free")) : ""
                color: line.gpu && line.gpu.drivesDisplay ? Theme.subtle : Theme.dim
                font.family: Theme.mono
                font.pixelSize: 10
            }
        }
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: content.implicitHeight + 36
        radius: 16
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.cardTop }
            GradientStop { position: 1.0; color: Theme.cardBot }
        }
        border.width: 1
        border.color: Theme.line

        Column {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 18
            spacing: 16

            Text {
                text: "力  GRAPHICS"
                color: Theme.cream
                font.family: Theme.mono
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 2.4
            }

            // what Ryoku (and a windowed VM) renders on right now.
            Column {
                width: parent.width
                spacing: 3
                Text {
                    text: "RENDERS ON"
                    color: Theme.dim
                    font.family: Theme.mono
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 2
                }
                Text {
                    width: parent.width
                    text: root.renderGpu ? root.renderGpu.model : "Detecting…"
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 21
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    text: "The desktop and a windowed VM draw here"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.line }

            Column {
                width: parent.width
                spacing: 12
                GpuLine { tag: "iGPU"; gpu: root.caps.host }
                GpuLine { tag: "dGPU"; gpu: root.caps.passthrough }
            }

            Text {
                width: parent.width
                visible: root.caps.chassis !== undefined
                text: (root.caps.chassis === "laptop" ? "Laptop" : "Desktop")
                      + (root.caps.cpu ? " · " + root.caps.cpu : "")
                      + (root.caps.mux && root.caps.mux !== "none" ? " · MUX " + root.caps.mux.replace("present-", "") : "")
                color: Theme.faint
                font.family: Theme.mono
                font.pixelSize: 10
                font.letterSpacing: 1
                font.capitalization: Font.AllUppercase
            }
        }
    }
}

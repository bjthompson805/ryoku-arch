pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import RyoMotion

// The live stage: mpv renders the video with zoom + text baked in by the live
// lavfi graph (so it matches the export), and QML frames it on the background
// with padding, rounded corners, shadow and border. Editing handles (zoom
// focus, text, overlay) sit on top so you drag them directly on the preview.
Item {
    id: stage
    property alias mpv: mpv

    readonly property real vAspect: 16 / 9
    readonly property real canvasAR: {
        var a = Project.aspectRatios[Project.aspect];
        return a > 0 ? a : vAspect;
    }
    readonly property real fitW: Math.min(width, height * canvasAR)
    readonly property real fitH: Math.min(height, width / canvasAR)

    Item {
        id: canvas
        width: stage.fitW
        height: stage.fitH
        anchors.centerIn: parent

        // background
        Rectangle {
            anchors.fill: parent
            visible: Project.bgKind !== "image"
            gradient: Project.bgKind === "gradient" ? grad : null
            color: Project.bgKind === "solid" ? Project.bgSolid : "transparent"
            Gradient {
                id: grad
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Project.bgA }
                GradientStop { position: 1.0; color: Project.bgB }
            }
        }
        Image {
            anchors.fill: parent
            visible: Project.bgKind === "image" && Project.bgImage !== ""
            source: Project.bgImage ? "file://" + Project.bgImage : ""
            fillMode: Image.PreserveAspectCrop
        }

        readonly property real pad: Project.padding * Math.min(width, height)
        readonly property real dispScale: (width - 2 * pad) / 1280

        Item {
            id: box
            x: canvas.pad; y: canvas.pad
            width: canvas.width - 2 * canvas.pad
            height: canvas.height - 2 * canvas.pad

            MpvItem { id: mpv; anchors.fill: parent; visible: Project.roundness <= 0 && Project.shadow <= 0 }
            MultiEffect {
                anchors.fill: mpv
                source: mpv
                visible: Project.roundness > 0 || Project.shadow > 0
                maskEnabled: Project.roundness > 0
                maskSource: maskRect
                maskThresholdMin: 0.5
                shadowEnabled: Project.shadow > 0
                shadowBlur: 1.0
                shadowColor: Qt.rgba(0, 0, 0, Project.shadow)
                shadowVerticalOffset: 10 * canvas.dispScale
                autoPaddingEnabled: true
            }
            Rectangle {
                id: maskRect
                anchors.fill: parent
                visible: false
                layer.enabled: true
                radius: Project.roundness * canvas.dispScale
                color: "black"
            }
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: Project.roundness * canvas.dispScale
                border.width: Project.borderW * canvas.dispScale
                border.color: Project.borderColor
                visible: Project.borderW > 0
            }

            // --- zoom focus handle (drag to aim the zoom on the preview) ---
            Rectangle {
                id: focusDot
                readonly property var reg: Project.selKind === "zoom" ? Project.selected() : null
                visible: reg !== null
                width: 22; height: 22; radius: 11
                color: "transparent"
                border.width: 2.5; border.color: Theme.ember
                x: (reg ? reg.cx : 0.5) * box.width - width / 2
                y: (reg ? reg.cy : 0.5) * box.height - height / 2
                Rectangle { anchors.centerIn: parent; width: 4; height: 4; radius: 2; color: Theme.ember }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    cursorShape: Qt.SizeAllCursor
                    onPositionChanged: (m) => {
                        if (!pressed || !focusDot.reg) return;
                        var p = mapToItem(box, m.x, m.y);
                        Project.updateSel({ cx: Math.max(0, Math.min(1, p.x / box.width)), cy: Math.max(0, Math.min(1, p.y / box.height)) });
                    }
                }
            }

            // --- text handle (drag to place the caption) ---
            Rectangle {
                id: textHandle
                readonly property var reg: Project.selKind === "text" ? Project.selected() : null
                visible: reg !== null
                color: Qt.rgba(Theme.gold.r, Theme.gold.g, Theme.gold.b, 0.18)
                border.width: 1.5; border.color: Theme.gold
                radius: 4
                width: Math.max(60, box.width * 0.3); height: Math.max(24, box.height * (reg ? reg.size : 0.06) * 1.6)
                x: (reg ? reg.x : 0.5) * box.width - width / 2
                y: (reg ? reg.y : 0.15) * box.height - height / 2
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    onPositionChanged: (m) => {
                        if (!pressed || !textHandle.reg) return;
                        var p = mapToItem(box, m.x, m.y);
                        Project.updateSel({ x: Math.max(0, Math.min(1, p.x / box.width)), y: Math.max(0, Math.min(1, p.y / box.height)) });
                    }
                }
            }

            // --- overlay handle (drag to place clip-in-clip) ---
            Rectangle {
                id: ovHandle
                readonly property var reg: Project.selKind === "overlay" ? Project.selected() : null
                visible: reg !== null
                color: "transparent"
                border.width: 2; border.color: "#4facfe"
                radius: 6
                width: box.width * (reg ? reg.scale : 0.34)
                height: width * 9 / 16
                x: (reg ? reg.x : 0.72) * box.width - width / 2
                y: (reg ? reg.y : 0.72) * box.height - height / 2
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.SizeAllCursor
                    onPositionChanged: (m) => {
                        if (!pressed || !ovHandle.reg) return;
                        var p = mapToItem(box, m.x, m.y);
                        Project.updateSel({ x: Math.max(0, Math.min(1, p.x / box.width)), y: Math.max(0, Math.min(1, p.y / box.height)) });
                    }
                }
            }
        }
    }

    // empty state
    Column {
        anchors.centerIn: parent
        spacing: 12
        visible: !Project.hasClip
        Icon { name: "film"; size: 44; tint: Theme.dim; anchors.horizontalCenter: parent.horizontalCenter }
        Text {
            text: "Record a demo or open a clip"
            color: Theme.dim; font.family: Theme.font; font.pixelSize: 15
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}

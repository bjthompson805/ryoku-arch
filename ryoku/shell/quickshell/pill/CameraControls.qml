pragma ComponentBehavior: Bound

import QtQuick
import "Singletons"

// Compact floating control pill for the camera bubble: flip, aspect, size, and a
// roundness slider (square corners -> full circle). Reads and writes Camera; the
// overlay reveals it on hover and hides it while recording, so it is never in the
// shot. Its own file so CameraOverlay stays focused on the surface and drag.
Rectangle {
    id: bar

    implicitWidth: row.implicitWidth + 16
    implicitHeight: 30
    radius: 9
    color: Qt.rgba(0, 0, 0, 0.66)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.08)

    component Ctl: Rectangle {
        property string label: ""
        property bool lit: false
        signal tapped()
        implicitWidth: t.implicitWidth + 10
        implicitHeight: 20
        radius: 5
        color: hov.hovered ? Qt.rgba(1, 1, 1, 0.13) : "transparent"
        Text {
            id: t
            anchors.centerIn: parent
            text: parent.label
            color: parent.lit ? Theme.cream : Theme.subtle
            font.family: Theme.mono
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
        HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.tapped() }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Ctl {
            anchors.verticalCenter: parent.verticalCenter
            label: "FLIP"
            lit: Camera.flipped
            onTapped: Camera.flipped = !Camera.flipped
        }
        Ctl {
            anchors.verticalCenter: parent.verticalCenter
            label: Camera.aspect === "square" ? "1:1" : Camera.aspect === "portrait" ? "3:4" : "4:3"
            lit: true
            onTapped: Camera.cycleAspect()
        }
        Ctl {
            anchors.verticalCenter: parent.verticalCenter
            label: Camera.sizeScale < 0.9 ? "S" : Camera.sizeScale < 1.2 ? "M" : "L"
            lit: true
            onTapped: Camera.cycleSize()
        }

        // roundness slider
        Item {
            id: slider
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            height: 20
            function setFromX(x) {
                Camera.roundness = Math.max(0, Math.min(1, x / slider.width));
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 3
                radius: 1.5
                color: Qt.rgba(1, 1, 1, 0.2)
                Rectangle {
                    width: parent.width * Camera.roundness
                    height: parent.height
                    radius: 1.5
                    color: Theme.brand
                }
            }
            Rectangle {
                width: 11
                height: 11
                radius: 5.5
                color: Theme.cream
                anchors.verticalCenter: parent.verticalCenter
                x: (slider.width - width) * Camera.roundness
            }
            TapHandler { onTapped: point => slider.setFromX(point.position.x) }
            DragHandler {
                target: null
                yAxis.enabled: false
                onCentroidChanged: if (active) slider.setFromX(centroid.position.x)
            }
        }
    }
}

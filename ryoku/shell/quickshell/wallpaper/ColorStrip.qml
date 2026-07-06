pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// The colour category strip: skwd-wall's idea in our sharp language. One swatch
// per colour group present under the current type filter, plus a leading All.
// Click a swatch to keep only that colour; click it (or All) again to clear.
Item {
    id: strip

    required property real s
    required property var groups
    required property int selected
    signal picked(int g)

    Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.round(6 * strip.s)

        Rectangle {
            id: all
            readonly property bool on: strip.selected === -1
            width: Math.round(38 * strip.s)
            height: strip.height
            color: all.on ? Theme.frameBg : "transparent"
            border.width: 1
            border.color: all.on ? Theme.brand : Theme.border
            Text {
                anchors.centerIn: parent
                text: "All"
                color: all.on ? Theme.brand : Theme.dim
                font.family: Theme.font
                font.pixelSize: Math.round(11.5 * strip.s)
                font.weight: all.on ? Font.DemiBold : Font.Normal
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: strip.picked(-1) }
        }

        Repeater {
            model: strip.groups
            delegate: Rectangle {
                id: sw
                required property var modelData
                readonly property bool on: strip.selected === sw.modelData
                width: Math.round(26 * strip.s)
                height: strip.height
                color: hh.hovered ? Qt.lighter(Colors.swatch(sw.modelData), 1.18) : Colors.swatch(sw.modelData)
                opacity: (strip.selected === -1 || sw.on) ? 1 : 0.45
                border.width: sw.on ? 2 : 1
                border.color: sw.on ? Theme.brand : Qt.rgba(0, 0, 0, 0.35)
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: strip.picked(sw.modelData) }
            }
        }
    }
}

import QtQuick
import "Singletons"

// flat horizontal switch, deck idiom. hairline track that fills vermilion
// when on, with a sliding knob. shared by Keep-Awake + Game-Mode rows.
Rectangle {
    id: sw

    property real s: 1
    property bool on: false
    signal toggled()

    width: 38 * s
    height: 20 * s
    color: sw.on ? Theme.brand : "transparent"
    border.width: 1
    border.color: sw.on ? Theme.brand : Theme.border
    Behavior on color { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

    Rectangle {
        width: 14 * sw.s
        height: 14 * sw.s
        anchors.verticalCenter: parent.verticalCenter
        x: sw.on ? parent.width - width - 3 * sw.s : 3 * sw.s
        color: sw.on ? Theme.cream : Theme.iconDim
        Behavior on x { NumberAnimation { duration: 130 } }
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: sw.toggled() }
}

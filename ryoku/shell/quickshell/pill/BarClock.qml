import QtQuick
import Quickshell
import "Singletons"

// clock module: tabular HH:MM with the vermilion colon and a tracked mono
// date. a vertical bar stacks hour over minute (the caelestia idiom) and
// drops the date; the tooltip-sized band has no room for it.
Item {
    id: clock

    property real s: 1
    property bool vertical: false
    readonly property var loc: Qt.locale("en_US")

    implicitWidth: vertical ? vcol.implicitWidth : hrow.implicitWidth
    implicitHeight: vertical ? vcol.implicitHeight : hrow.implicitHeight

    SystemClock {
        id: sys
        precision: SystemClock.Minutes
    }

    Row {
        id: hrow
        visible: !clock.vertical
        spacing: 7 * clock.s

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                text: Qt.formatTime(sys.date, "HH")
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * clock.s
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
            Text {
                text: ":"
                color: Theme.brand
                font.family: Theme.font
                font.pixelSize: 12.5 * clock.s
                font.weight: Font.DemiBold
            }
            Text {
                text: Qt.formatTime(sys.date, "mm")
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12.5 * clock.s
                font.weight: Font.DemiBold
                font.features: ({ "tnum": 1 })
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: clock.loc.toString(sys.date, "ddd d MMM").toUpperCase()
            color: Theme.dim
            font.family: Theme.mono
            font.pixelSize: 8.5 * clock.s
            font.weight: Font.DemiBold
            font.letterSpacing: 1.1 * clock.s
        }
    }

    Column {
        id: vcol
        visible: clock.vertical
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(sys.date, "HH")
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * clock.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 8 * clock.s
            height: 1.6 * clock.s
            color: Theme.brand
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(sys.date, "mm")
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 10.5 * clock.s
            font.weight: Font.DemiBold
            font.features: ({ "tnum": 1 })
        }
    }
}

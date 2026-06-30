import QtQuick
import Quickshell
import "Singletons"

// Zero-query home: a single card with the time, the date, and a greeting that
// shifts with the hour. Shown when the search field is empty, the way the inir
// rest screen reads before you type.
Item {
    id: root

    property real s: 1
    implicitHeight: 96 * s

    readonly property var now: clock.date
    readonly property string hhmm: Qt.formatTime(now, "HH:mm")
    readonly property string date: Qt.locale("en_US").toString(now, "dddd, MMMM d")
    readonly property string greeting: {
        var h = now.getHours();
        if (h < 5) return "Good night";
        if (h < 12) return "Good morning";
        if (h < 18) return "Good afternoon";
        return "Good evening";
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusRow * root.s
        color: Theme.frameBg

        Text {
            id: time
            anchors.left: parent.left
            anchors.leftMargin: Metrics.padRow * root.s
            anchors.top: parent.top
            anchors.topMargin: 14 * root.s
            text: root.hhmm
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 40 * root.s
            font.weight: Font.Light
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: Metrics.padRow * root.s
            anchors.top: parent.top
            anchors.topMargin: 18 * root.s
            text: root.date
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 13 * root.s
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Metrics.padRow * root.s
            anchors.top: time.bottom
            anchors.topMargin: 2 * root.s
            text: root.greeting
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 13 * root.s
        }
    }
}

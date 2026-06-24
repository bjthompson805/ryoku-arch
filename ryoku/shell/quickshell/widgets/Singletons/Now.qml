pragma Singleton
import QtQuick
import Quickshell

/**
 * The shared wall clock for every desktop widget. One second-resolution tick
 * drives all clock designs and the analog second hand, so they stay in lockstep
 * and the desktop never runs two timers for the same time. Designs that only show
 * minutes simply ignore the seconds field.
 */
Singleton {
    id: root

    property var date: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.date = new Date()
    }
}

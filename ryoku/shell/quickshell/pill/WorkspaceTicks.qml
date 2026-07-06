pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import "Singletons"

// the island's workspace readout: a row of registration ticks, one per
// workspace in the current desktop block. the active tick stretches into an
// accent dash, occupied ticks read brighter, empty ones faint. precise
// printer's marks instead of the old squiggle; ticks past five appear only
// once used. click a tick to jump.
Row {
    id: ticks

    property real s: 1
    property string screenName: ""

    readonly property int activeWsId: {
        var mons = Hyprland.monitors.values;
        for (var i = 0; i < mons.length; i++)
            if (mons[i].name === ticks.screenName && mons[i].activeWorkspace)
                return mons[i].activeWorkspace.id;
        return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
    }
    readonly property int base: Math.floor((activeWsId - 1) / 10) * 10
    readonly property var occupiedSet: {
        var occ = {};
        var v = Hyprland.workspaces.values;
        for (var i = 0; i < v.length; i++)
            if (v[i])
                occ[v[i].id] = true;
        return occ;
    }
    readonly property int shown: {
        var n = 5;
        for (var i = 10; i > 5; i--) {
            if (occupiedSet[base + i] || activeWsId === base + i) {
                n = i;
                break;
            }
        }
        return n;
    }

    spacing: 4 * s

    Repeater {
        model: ticks.shown
        delegate: Rectangle {
            id: tick
            required property int index
            readonly property int wsId: ticks.base + index + 1
            readonly property bool active: ticks.activeWsId === wsId
            readonly property bool occupied: ticks.occupiedSet[wsId] === true
            anchors.verticalCenter: parent.verticalCenter
            width: active ? 13 * ticks.s : 3.5 * ticks.s
            height: 3 * ticks.s
            color: active ? Theme.verm
                : (occupied ? Qt.alpha(Theme.cream, 0.55) : Qt.alpha(Theme.cream, 0.18))
            Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Motion.fast } }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -3 * ticks.s
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Hyprland.dispatch('hl.dsp.workspace.move({ workspace = ' + tick.wsId + ', monitor = "current" })');
                    Hyprland.dispatch('hl.dsp.focus({ workspace = ' + tick.wsId + ' })');
                }
            }
        }
    }
}

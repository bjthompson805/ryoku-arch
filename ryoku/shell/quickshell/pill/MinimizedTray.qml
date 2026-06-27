pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Hyprland
import "Singletons"

// row of icon buttons for windows parked on Hyprland's `special:minimized`
// (Super+M). click sends a window back to the focused workspace.
Row {
    id: root

    property real s: 1
    property string screenName: ""
    spacing: 8 * s

    // ws id to restore into = active ws of the monitor this pill lives on,
    // so the window reappears on the screen the user clicked. falls back to
    // the focused ws.
    function restoreWorkspace() {
        var ms = Hyprland.monitors.values;
        for (var i = 0; i < ms.length; i++)
            if (ms[i].name === root.screenName && ms[i].activeWorkspace)
                return ms[i].activeWorkspace.id;
        return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
    }

    readonly property var items: {
        var out = [];
        var tl = Hyprland.toplevels.values;
        for (var i = 0; i < tl.length; i++) {
            var t = tl[i];
            if (t && t.workspace && t.workspace.name === "special:minimized")
                out.push(t);
        }
        return out;
    }
    readonly property int count: items.length

    Repeater {
        model: root.items

        delegate: Item {
            id: chip
            required property var modelData
            width: 18 * root.s
            height: 18 * root.s

            readonly property string iconSrc: Apps.iconFor(chip.modelData)

            Image {
                anchors.fill: parent
                sourceSize.width: Math.round(36 * root.s)
                sourceSize.height: Math.round(36 * root.s)
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                source: chip.iconSrc
                opacity: area.containsMouse ? 1 : 0.78
                Behavior on opacity { NumberAnimation { duration: 110 } }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                anchors.margins: -3 * root.s
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    var addr = chip.modelData.address;
                    if (addr.indexOf("0x") !== 0)
                        addr = "0x" + addr;
                    Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + root.restoreWorkspace() + ', window = "address:' + addr + '" })');
                }
            }
        }
    }
}

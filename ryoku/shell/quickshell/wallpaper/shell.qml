//@ pragma UseQApplication
//@ pragma DefaultEnv QSG_RENDER_LOOP = threaded
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "Singletons"

/**
 * Ryoku wallpaper switcher: a full-screen, Super+Tab-style overlay launched as
 * its own `qs -c wallpaper` instance (like the overview and window switcher, so
 * it never burdens the always-on pill). Images and videos share one grid,
 * grouped by colour the way skwd-wall does; arrows/Tab move the pick, a colour
 * swatch or the type row filters, Enter or a click sets it, Esc dismisses. The
 * card and accent mirror the shell chrome through the local wallust singleton.
 */
ShellRoot {
    id: root

    // Intro/outro: `active` drives the reveal; a dismiss plays the outro then
    // quits the instance (on-demand config, so dismiss == exit).
    property bool active: false
    Timer { id: introT; interval: 16; running: true; onTriggered: root.active = true }
    Timer { id: outroT; interval: 200; onTriggered: Qt.quit() }
    function dismiss() {
        if (!root.active && outroT.running)
            return;
        root.active = false;
        outroT.restart();
    }

    readonly property string focusedMon: {
        var m = Hyprland.focusedMonitor;
        return m && m.name ? m.name : "";
    }

    Component.onCompleted: Walls.refresh()

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property real s: Math.min(1.3, (modelData ? modelData.height / 1080 : 1)) * Math.max(0.8, Math.min(1.4, Config.fontScale))
            readonly property bool isFocused: !root.focusedMon || root.focusedMon === modelData.name

            screen: modelData
            color: "transparent"
            exclusiveZone: 0
            WlrLayershell.namespace: "ryoku-wallpaper"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: isFocused ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }

            // Dim scrim over the desktop; click-out dismisses.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.42)
                opacity: root.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.window; easing.type: Motion.easeStandard } }
                MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
            }

            // Only the focused monitor carries the card + keyboard; the rest just dim.
            Loader {
                id: body
                anchors.fill: parent
                active: win.isFocused
                sourceComponent: Switcher {
                    s: win.s
                    active: root.active
                    onRequestClose: root.dismiss()

                    opacity: root.active ? 1 : 0
                    scale: root.active ? 1 : 0.98
                    Behavior on opacity { NumberAnimation { duration: Motion.window; easing.type: Motion.easeStandard } }
                    Behavior on scale { NumberAnimation { duration: Motion.window; easing.type: Motion.easeExpo } }
                }
            }
        }
    }
}

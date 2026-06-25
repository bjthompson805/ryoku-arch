import QtQuick
import Quickshell
import Quickshell.Wayland
import "Singletons"
import "clock"
import "weather"

/**
 * Desktop widgets: a wallpaper layer (WlrLayer.Bottom, below windows) carrying the
 * clock and weather, one per monitor. The layer is interactive across the
 * wallpaper so a right-click anywhere on the bare desktop opens the desktop menu;
 * windows above still receive their own input, so only clicks on visible wallpaper
 * reach it. Drag a widget to move it (it snaps to the grid that fades in),
 * right-click a widget for its own menu, right-click the desktop for the global
 * one. Everything is read live from the widgets Config; the drag, the menus, and
 * Ryoku Settings' Desktop Widgets section all write the same file, so the surfaces
 * retune with no reload.
 */
ShellRoot {
    id: root

    // One IP-located weather fetch shared by every monitor, in the user's unit.
    Binding {
        target: WeatherData
        property: "unit"
        value: Config.weatherUnit
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData

            screen: modelData
            color: "transparent"

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "ryoku-widgets"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors { top: true; left: true; right: true; bottom: true }

            // Right-click the bare desktop for the global menu. Sits behind the
            // widgets (which handle their own right-click) and takes only the right
            // button, so a left click on the wallpaper does nothing rather than
            // being swallowed in a way that feels broken.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onPressed: (mouse) => menu.openDesktop(mouse.x, mouse.y)
            }

            WidgetGrid {
                anchors.fill: parent
                active: clockSlot.dragging || weatherSlot.dragging
                gridSize: clockSlot.gridSize
            }

            WidgetSlot {
                id: clockSlot
                widget: "clock"
                visible: Config.clockEnabled
                anchor: Config.clockAnchor
                freeX: Config.clockX
                freeY: Config.clockY
                locked: Config.clockLocked
                bg: Config.clockBg
                radius: Config.clockRadius
                scaleCfg: Config.clockScale
                pad: Config.clockBg === "none" ? 0 : Math.round(24 * Config.clockScale)
                opacity: Config.clockOpacity
                onMenuRequested: (x, y, w) => menu.openFor(w, x, y)
                Clock {}
            }

            WidgetSlot {
                id: weatherSlot
                widget: "weather"
                visible: Config.weatherEnabled
                anchor: Config.weatherAnchor
                freeX: Config.weatherX
                freeY: Config.weatherY
                locked: Config.weatherLocked
                bg: Config.weatherBg
                radius: Config.weatherRadius
                scaleCfg: Config.weatherScale
                pad: Config.weatherBg === "none" ? 0 : Math.round(24 * Config.weatherScale)
                opacity: Config.weatherOpacity
                onMenuRequested: (x, y, w) => menu.openFor(w, x, y)
                Weather {}
            }

            WidgetMenu { id: menu }
        }
    }
}

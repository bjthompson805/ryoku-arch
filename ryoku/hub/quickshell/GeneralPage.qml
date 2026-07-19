pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Singletons"

// General: desktop-wide preferences that aren't owned by any one surface.
// Starts with the clock format (12h/24h) -- it used to live on Desktop
// Widgets, but it drives every clock in the shell (bar, sidebar, launcher,
// Hub, and the desktop widget), not just the widget, so it belongs here
// instead. Writes ~/.config/ryoku/general.json, watched live by every
// surface's Config singleton.
Item {
    id: page

    FileView {
        id: cfg
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/general.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property bool clock24h: true
        }

        Component.onCompleted: if (!cfg.text()) cfg.writeAdapter()
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 4
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        Column {
            id: col
            width: parent.width
            spacing: 26

            SettingSection {
                width: col.width
                title: "TIME"

                ToggleRow {
                    width: parent.width
                    label: "24-hour clock (applies everywhere: the bar, sidebar, launcher, Hub, and the desktop clock widget)"
                    checked: adapter.clock24h
                    onToggled: c => {
                        adapter.clock24h = c;
                        cfg.writeAdapter();
                    }
                }
            }
        }
    }
}

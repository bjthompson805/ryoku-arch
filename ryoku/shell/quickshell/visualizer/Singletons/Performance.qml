pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Performance toggles, shared through ~/.config/ryoku/performance.json (the
// Performance section in Ryoku Settings writes it). The visualiser freezes when
// silent by default -- its idle animation otherwise leaks on this Qt/NVIDIA stack.
Singleton {
    id: root

    property alias freezeVisualizerWhenIdle: adapter.freezeVisualizerWhenIdle

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/performance.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property bool freezeVisualizerWhenIdle: true
        }
    }
}

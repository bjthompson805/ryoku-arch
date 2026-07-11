import QtQuick
import Quickshell
import "Singletons"

// qs -c ryovm entry: a floating window, single-instanced by the launch flock.
ShellRoot {
    FloatingWindow {
        id: win
        title: "ryovm"
        minimumSize: Qt.size(960, 640)
        // Opaque from the first frame. Without it the surface maps transparent and
        // the compositor shows its uncleared (garbage) buffer as horizontal streaks
        // for a frame or two before the QML paints; matching App's canvas means no
        // flash on launch.
        color: Theme.bgBot
        onClosed: Qt.quit()

        App { anchors.fill: parent }
    }
}

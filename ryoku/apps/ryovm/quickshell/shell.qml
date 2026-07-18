import QtQuick
import Quickshell
import Ryoku.Ui.Singletons

// qs -c ryovm entry: a floating window, single-instanced by the launch flock.
ShellRoot {
    FloatingWindow {
        id: win
        title: "ryovm"
        minimumSize: Qt.size(1180, 760)
        // Opaque paper from the first frame, so the compositor never flashes its
        // uncleared buffer before the QML paints.
        color: Tokens.paper
        onClosed: Qt.quit()

        App { anchors.fill: parent }
    }
}

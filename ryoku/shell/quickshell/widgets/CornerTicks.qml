import QtQuick
import "Singletons"

// Faint L-bracket registration ticks at the four corners, framing a panel like an
// editorial specimen sheet, the same motif the pill's dossier surfaces use.
// Purely decorative.
Item {
    id: ticks

    property real len: 9
    property color tint: Theme.hair

    Rectangle { anchors.left: parent.left; anchors.top: parent.top; width: ticks.len; height: 1; color: ticks.tint }
    Rectangle { anchors.left: parent.left; anchors.top: parent.top; width: 1; height: ticks.len; color: ticks.tint }
    Rectangle { anchors.right: parent.right; anchors.top: parent.top; width: ticks.len; height: 1; color: ticks.tint }
    Rectangle { anchors.right: parent.right; anchors.top: parent.top; width: 1; height: ticks.len; color: ticks.tint }
    Rectangle { anchors.left: parent.left; anchors.bottom: parent.bottom; width: ticks.len; height: 1; color: ticks.tint }
    Rectangle { anchors.left: parent.left; anchors.bottom: parent.bottom; width: 1; height: ticks.len; color: ticks.tint }
    Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: ticks.len; height: 1; color: ticks.tint }
    Rectangle { anchors.right: parent.right; anchors.bottom: parent.bottom; width: 1; height: ticks.len; color: ticks.tint }
}

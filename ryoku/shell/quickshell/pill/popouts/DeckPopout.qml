pragma ComponentBehavior: Bound

import QtQuick
import ".."

// control deck popout: the single-view dashboard (Super+D, plus the stash /
// toolkit / utilities entry points), grown from the bar edge. holds the
// DeckSurface pinned open so the Popout blob does the reveal. a keyboard popout
// (stash download link + LocalSend compose fields). requestClose bubbles up.
Item {
    id: root

    property real s: 1
    property bool open: false
    signal closeRequested()

    implicitWidth: 590 * root.s
    implicitHeight: deck.implicitHeight + 28 * root.s

    // consume clicks on empty body so they don't fall through to the backdrop
    // and dismiss the popout; the deck's own controls sit on top.
    MouseArea { anchors.fill: parent }

    DeckSurface {
        id: deck
        anchors.fill: parent
        s: root.s
        open: true
        shown: true
        openProgress: 1
        openW: root.implicitWidth
        openH: root.implicitHeight
        onRequestClose: root.closeRequested()
    }
}

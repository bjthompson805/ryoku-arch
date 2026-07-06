import QtQuick
import "Singletons"

// bar module plate: the slab every bar module sits on, in one of two skins.
//   plates  = sharp washi slab, faint warm fill, hairline edge (the house
//             brutalist idiom).
//   capsule = fully rounded tonal pill, no hairline (the caelestia idiom),
//             for shells riced round.
// both lift on hover so a module reads as touchable before it's clicked.
// content is centred; the plate hugs it plus padding on the main axis.
Item {
    id: plate

    property real s: 1
    property bool vertical: false
    property real padX: 10 * s
    property real padY: 9 * s
    default property alias content: slot.data
    property bool interactive: true
    // quiet = no resting fill; the plate only surfaces on hover (tray, title).
    property bool quiet: false
    readonly property alias hovered: hoverArea.containsMouse
    readonly property bool capsule: Config.barStyle === "capsule"

    signal tapped()
    signal wheeled(int steps)

    implicitWidth: vertical ? width : slot.implicitWidth + 2 * padX
    implicitHeight: vertical ? slot.implicitHeight + 2 * padY : height

    Rectangle {
        anchors.fill: parent
        radius: plate.capsule ? Math.min(width, height) / 2 : 0
        color: {
            if (hoverArea.containsMouse && plate.interactive)
                return plate.capsule ? Qt.alpha(Theme.cream, 0.16) : Qt.alpha(Theme.bright, 0.10);
            if (plate.quiet)
                return "transparent";
            return plate.capsule ? Qt.alpha(Theme.cream, 0.075) : Qt.alpha(Theme.bright, 0.045);
        }
        border.width: plate.capsule ? 0 : 1
        border.color: hoverArea.containsMouse && plate.interactive
            ? Qt.alpha(Theme.bright, 0.22)
            : (plate.quiet ? "transparent" : Theme.hair)
        Behavior on color { ColorAnimation { duration: Motion.hover; easing.type: Motion.easeStandard } }
        Behavior on border.color { ColorAnimation { duration: Motion.hover; easing.type: Motion.easeStandard } }
    }

    // single-root content: the plate hugs its implicit size. (childrenRect is
    // unreliable under anchors; one root Row/Item per module is the contract.)
    Item {
        id: slot
        anchors.centerIn: parent
        implicitWidth: children.length > 0 ? children[0].implicitWidth : 0
        implicitHeight: children.length > 0 ? children[0].implicitHeight : 0
        width: implicitWidth
        height: implicitHeight
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: plate.interactive
        cursorShape: Qt.PointingHandCursor
        onClicked: plate.tapped()
        onWheel: (w) => plate.wheeled(w.angleDelta.y > 0 ? 1 : -1)
    }
}

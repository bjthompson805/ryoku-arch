import QtQuick
import "Singletons"

// An action button in the Profile dossier idiom: a small-radius carbon chip with a
// mono uppercase label, not a generic pill. `primary` is an outlined ember stamp -
// ember as a thin accent (border + label), never a fill; `secondary` is a hairline
// ghost whose border warms to ember on hover. Hover brightens, press dips.
Item {
    id: btn

    property string label: ""
    property string icon: ""
    property bool primary: false
    signal clicked()

    readonly property real radius: 10

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 38

    opacity: enabled ? 1 : 0.4
    scale: tap.pressed && btn.enabled ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }

    // Primary face: an outlined ember stamp - ember is the accent, never a fill.
    Rectangle {
        anchors.fill: parent
        visible: btn.primary
        radius: btn.radius
        color: hover.hovered ? Theme.frameBg : "transparent"
        border.width: 1
        border.color: Theme.ember
        Behavior on color { ColorAnimation { duration: Theme.quick } }
    }

    // Ghost (secondary) face: a carbon tag, hairline border warming to ember.
    Rectangle {
        anchors.fill: parent
        visible: !btn.primary
        radius: btn.radius
        color: hover.hovered ? Theme.keyTop : "transparent"
        border.width: 1
        border.color: hover.hovered ? Theme.ember : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.quick } }
        Behavior on border.color { ColorAnimation { duration: Theme.quick } }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Icon {
            visible: btn.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: btn.icon
            size: 14
            weight: 1.8
            tint: btn.primary ? (hover.hovered ? Qt.lighter(Theme.ember, 1.25) : Theme.ember) : (hover.hovered ? Theme.bright : Theme.cream)
            Behavior on tint { ColorAnimation { duration: Theme.quick } }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.label
            color: btn.primary ? (hover.hovered ? Qt.lighter(Theme.ember, 1.25) : Theme.ember) : (hover.hovered ? Theme.bright : Theme.cream)
            font.family: Theme.mono
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.letterSpacing: 1.5
            font.capitalization: Font.AllUppercase
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }
    }

    HoverHandler { id: hover; enabled: btn.enabled; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; enabled: btn.enabled; onTapped: btn.clicked() }
}

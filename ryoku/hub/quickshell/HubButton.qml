import QtQuick
import "Singletons"

// Profile dossier action button: small-radius carbon chip with a mono caps label,
// not a generic pill. primary = outlined ember stamp (ember as accent on border +
// label, never a fill); secondary = hairline ghost, border warms to ember on
// hover. hover brightens, press dips.
Item {
    id: btn

    property string label: ""
    property string icon: ""
    property bool primary: false
    signal clicked()

    readonly property real radius: Theme.radiusChip

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 38

    opacity: enabled ? 1 : 0.4
    scale: tap.pressed && btn.enabled ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }

    // primary face. outlined ember stamp, ember is the accent, never a fill.
    Rectangle {
        anchors.fill: parent
        visible: btn.primary
        radius: btn.radius
        color: hover.hovered ? Theme.frameBg : "transparent"
        border.width: 1
        border.color: Theme.ember
        Behavior on color { ColorAnimation { duration: Theme.quick } }
    }

    // ghost (secondary). carbon tag, hairline border warming to ember.
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

    // optional hover tooltip: a small carbon popup that explains what the button
    // does, for the terse mono labels (Edit overrides / View defaults) that need
    // a sentence. shows below the button after a short hover, never on tap.
    property string tooltip: ""

    Timer { id: tipGate; property bool ready: false; interval: 350; onTriggered: tipGate.ready = true }
    Connections {
        target: hover
        function onHoveredChanged() {
            if (hover.hovered) {
                tipGate.ready = false;
                tipGate.restart();
            } else {
                tipGate.stop();
                tipGate.ready = false;
            }
        }
    }

    Rectangle {
        id: tip
        visible: opacity > 0
        opacity: (btn.tooltip !== "" && hover.hovered && tipGate.ready) ? 1 : 0
        z: 999
        width: 264
        height: tipText.implicitHeight + 18
        anchors.top: parent.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        color: Theme.surface
        radius: btn.radius
        border.width: 1
        border.color: Theme.line
        Behavior on opacity { NumberAnimation { duration: Theme.quick } }

        Text {
            id: tipText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            text: btn.tooltip
            wrapMode: Text.WordWrap
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 12
            lineHeight: 1.25
        }
    }
}

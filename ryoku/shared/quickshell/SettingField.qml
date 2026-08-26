pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// labelled free-text field: label on the left, a CommitField box on the
// right (see CommitField.qml for the commit/checkmark behaviour), mirroring
// NumberField / Dropdown so it sits cleanly among the other setting rows.
Item {
    id: root

    property string label: ""
    property string value: ""
    property string placeholder: ""
    property real fieldWidth: 200

    signal committed(string value)

    implicitWidth: 320
    implicitHeight: 38

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - box.width - 14
        elide: Text.ElideRight
        text: root.label
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 14
        font.weight: Font.Medium
    }

    CommitField {
        id: box
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: root.fieldWidth
        value: root.value
        placeholder: root.placeholder
        onCommitted: (t) => root.committed(t)
    }
}

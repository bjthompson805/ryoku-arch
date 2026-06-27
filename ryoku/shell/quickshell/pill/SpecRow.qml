import QtQuick
import "Singletons"

// dossier spec line: mono label left, hairline eats the gap, value right.
// the card's type-line motif, reused. scales with `s`.
Row {
    id: sr

    property string k: ""
    property string v: ""
    property real s: 1

    width: parent ? parent.width : 0
    height: 30 * s
    spacing: 12 * s

    Text {
        id: srk
        anchors.verticalCenter: parent.verticalCenter
        text: sr.k
        color: Theme.dim
        font.family: Theme.mono
        font.pixelSize: 10 * sr.s
        font.letterSpacing: 1.6 * sr.s
        font.capitalization: Font.AllUppercase
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(8 * sr.s, sr.width - srk.implicitWidth - srv.implicitWidth - 2 * sr.spacing)
        height: 1
        color: Theme.hair
    }

    Text {
        id: srv
        anchors.verticalCenter: parent.verticalCenter
        text: sr.v
        color: Theme.bright
        font.family: Theme.font
        font.pixelSize: 13 * sr.s
        font.weight: Font.Medium
    }
}

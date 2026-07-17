import QtQuick
import "Singletons"

// A named group of settings. The section owns packing: cells declare a span
// and Flow places them. Nothing in this file knows where a cell goes, which is
// the point -- meaning decides grouping, the control decides width.
Column {
    id: sect
    property string title: ""
    property int gutter: Tokens.s2
    default property alias cells: flow.data

    readonly property real colWidth: (width - (Spans.cols - 1) * gutter) / Spans.cols
    function span(n) { return n * colWidth + (n - 1) * gutter }

    spacing: Tokens.s3

    Row {
        spacing: Tokens.s2
        Rectangle { width: 4; height: 4; color: Tokens.ink; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: sect.title
            color: Tokens.ink
            font.family: Tokens.ui
            font.pixelSize: Tokens.fMicro
            font.weight: Font.Medium
            font.letterSpacing: Tokens.trackMark
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            width: Math.max(0, sect.width - 200)
            height: 1
            color: Tokens.lineSoft
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Flow {
        id: flow
        width: parent.width
        spacing: sect.gutter
    }
}

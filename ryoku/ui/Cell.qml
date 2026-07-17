import QtQuick
import "Singletons"

// One setting, drawn. A cell never places itself: Section flows it, and its
// span comes from Spans.of(kind, optionCount), so adding a setting cannot
// require a layout decision.
//
// The control's footprint is reserved by the text column rather than drawn on
// top of it -- that is what makes overlap impossible instead of merely tuned
// away. Controls that need their own band (gallery, multi, chips) declare more
// rows and the text stops above them.
Item {
    id: cell

    property string label: ""
    property string desc: ""
    property string value: ""
    property string unit: ""
    property string def: ""
    property string source: ""
    property bool changed: value !== def
    property bool block: false      // control gets its own band under the text
    property int controlWidth: 0    // reserved when inline
    default property alias control: slot.data

    readonly property bool hovered: hh.hovered

    implicitHeight: Tokens.cellH

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius
        color: hh.hovered ? Qt.rgba(205 / 255, 196 / 255, 186 / 255, 0.05) : "transparent"
        border.width: Tokens.border
        border.color: hh.hovered ? Tokens.lineStrong : Tokens.line
        Behavior on color { ColorAnimation { duration: Tokens.snap } }
        Behavior on border.color { ColorAnimation { duration: Tokens.snap } }
    }
    HoverHandler { id: hh }

    // changed reads as a solid edge. no colour is spent on it.
    Rectangle {
        visible: cell.changed
        x: 0
        y: Tokens.s2
        width: 2
        height: parent.height - Tokens.s4
        color: Tokens.ink
    }

    // which file this lands in, parked in the corner off the reading path
    Text {
        anchors { right: parent.right; top: parent.top; margins: Tokens.s3 }
        visible: cell.source !== ""
        text: cell.source.replace(".json", "")
        color: Tokens.inkFaint
        font.family: Tokens.mono
        font.pixelSize: Tokens.fTiny
        opacity: hh.hovered ? 1 : 0.8
        Behavior on opacity { NumberAnimation { duration: Tokens.snap } }
    }

    Column {
        anchors { left: parent.left; top: parent.top; margins: Tokens.s3 }
        anchors.leftMargin: Tokens.s4
        width: cell.width - Tokens.s4 - Tokens.s3 - (cell.block ? 0 : cell.controlWidth + Tokens.s4) - 46
        spacing: 0

        Text {
            width: parent.width
            text: cell.label.toUpperCase()
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: 10
            font.weight: Font.Medium
            font.letterSpacing: Tokens.trackLabel
            elide: Text.ElideRight
        }
        Row {
            spacing: Tokens.s1
            Text {
                text: cell.value
                color: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: cell.value.length > 8 ? 18 : Tokens.fValue
                font.weight: Font.Light
            }
            Text {
                text: cell.unit
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
            }
            Text {
                visible: cell.changed && cell.def !== ""
                text: cell.def + (cell.unit ? " " + cell.unit : "")
                color: Tokens.inkFaint
                font.family: Tokens.mono
                font.pixelSize: Tokens.fTiny
                font.strikeout: true
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
            }
        }
        Item { width: 1; height: 2 }
        Text {
            width: parent.width
            text: cell.desc
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    Item {
        id: slot
        anchors.right: parent.right
        anchors.rightMargin: Tokens.s4
        anchors.verticalCenter: cell.block ? undefined : parent.verticalCenter
        anchors.bottom: cell.block ? parent.bottom : undefined
        anchors.bottomMargin: Tokens.s3
        anchors.left: cell.block ? parent.left : undefined
        anchors.leftMargin: Tokens.s4
        height: cell.block ? Math.max(Tokens.ctlH, childrenRect.height) : Tokens.ctlH
        width: cell.block ? undefined : cell.controlWidth
    }
}

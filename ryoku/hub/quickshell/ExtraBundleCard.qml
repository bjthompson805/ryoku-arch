import QtQuick
import "Singletons"

// one bento tile, laid out like the Ryoku extras catalogue entry it stands for:
// big mono catalogue number, sources, name, keyword tagline, blurb. flat warm
// surface, hairline warms to ember on hover. no gradient, no glassy badge. sizes
// to content so the page packs a ragged bento mosaic. click opens the detail.
Rectangle {
    id: tile

    property var bundle: ({})
    property int ordinal: 0
    property int installedCount: 0
    readonly property int totalCount: bundle.items ? bundle.items.length : 0
    readonly property bool anyInstalled: tile.installedCount > 0

    signal opened()

    implicitHeight: body.implicitHeight + 40
    radius: Theme.radius
    color: hover.hovered ? Theme.surface : Theme.surfaceLo
    border.width: 1
    border.color: hover.hovered ? Theme.ember : Theme.line
    Behavior on color { ColorAnimation { duration: Theme.quick } }
    Behavior on border.color { ColorAnimation { duration: Theme.quick } }

    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 20
        spacing: 0

        Item {
            width: parent.width
            height: number.implicitHeight

            Text {
                id: number
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: (tile.ordinal < 10 ? "0" : "") + tile.ordinal
                color: hover.hovered ? Theme.ember : Theme.faint
                font.family: Theme.mono
                font.pixelSize: 26
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: Theme.quick } }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 7

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: tile.anyInstalled ? Theme.ok : Theme.line
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tile.installedCount + " / " + tile.totalCount
                    color: tile.anyInstalled ? Theme.subtle : Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 11
                }
            }
        }

        Text {
            width: parent.width
            topPadding: 16
            text: tile.bundle.sources || ""
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 1.5
            font.capitalization: Font.AllUppercase
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            topPadding: 8
            text: tile.bundle.name || ""
            color: Theme.bright
            font.family: Theme.font
            font.pixelSize: 18
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            topPadding: 4
            visible: (tile.bundle.tagline || "") !== ""
            text: tile.bundle.tagline || ""
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            topPadding: 12
            text: tile.bundle.description || ""
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12
            lineHeight: 1.32
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }

    Icon {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 18
        anchors.bottomMargin: 16
        name: "chevron"
        size: 15
        weight: 2
        rotation: -90
        tint: Theme.ember
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.quick } }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: tile.opened() }
}

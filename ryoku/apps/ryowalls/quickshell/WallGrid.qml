pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "Singletons"

// The browse collection: a scrollable wall of thumbnails bound to
// Wallhaven.results. Picking a cell selects it for the preview; the empty and
// loading states carry the torii mark and one sentence, per the skeleton.
Item {
    id: g

    readonly property int gap: Tokens.s2
    readonly property int cols: Math.max(2, Math.floor(width / 200))

    GridView {
        id: grid
        anchors.fill: parent
        visible: Wallhaven.results.length > 0
        clip: true
        cellWidth: Math.floor(g.width / g.cols)
        cellHeight: Math.round(cellWidth * 0.62)
        model: Wallhaven.results
        cacheBuffer: 1200
        boundsBehavior: Flickable.StopAtBounds
        opacity: Wallhaven.searching ? 0.45 : 1
        Behavior on opacity { NumberAnimation { duration: Tokens.snap } }

        ScrollBar.vertical: ScrollRail {}

        delegate: Item {
            required property var modelData
            width: grid.cellWidth
            height: grid.cellHeight

            WallCell {
                anchors.fill: parent
                anchors.margins: g.gap / 2
                item: parent.modelData
                active: Wallhaven.selected && Wallhaven.selected.id === parent.modelData.id
                onPicked: Wallhaven.select(parent.modelData)
                onOpened: Wallhaven.openWeb(parent.modelData)
                selectable: Wallhaven.source === "local"
                selected: Wallhaven.localSelection.indexOf(parent.modelData.id) >= 0
                onToggledSelect: Wallhaven.toggleLocalSelect(parent.modelData)
            }
        }
    }

    // empty / loading / error state: the mark at 96, then one sentence.
    Column {
        anchors.centerIn: parent
        spacing: Tokens.s4
        visible: Wallhaven.results.length === 0
        Torii {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 96; height: 96
            ink: Tokens.inkFaint
            // the loading mark holds solid; no spin, per reduced-motion discipline.
            opacity: Wallhaven.searching ? 0.5 : 1
            Behavior on opacity { NumberAnimation { duration: Tokens.snap } }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Wallhaven.searching ? "Loading wallpapers"
                : (Wallhaven.error.length > 0 ? Wallhaven.error
                : (Wallhaven.source === "live" ? "No live wallpapers yet" : "No wallpapers"))
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: 12
        }
    }
}

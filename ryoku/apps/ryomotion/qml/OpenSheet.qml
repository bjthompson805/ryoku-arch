pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import RyoMotion

// In-app clip picker: lists recent clips under ~/Videos so opening stays inside
// the app, with a Browse escape hatch for anywhere else.
Item {
    id: sheet
    anchors.fill: parent
    visible: open
    property bool open: false
    signal chosen(url u)
    property var clips: []
    onOpenChanged: if (open) clips = Backend.listClips()

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        MouseArea { anchors.fill: parent; onClicked: sheet.open = false }
    }
    Rectangle {
        width: Math.min(560, parent.width - 80)
        height: Math.min(520, parent.height - 100)
        anchors.centerIn: parent
        radius: Theme.radiusLg
        color: Theme.bgTop
        border.width: 1; border.color: Theme.hair

        Item {
            id: head
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 56
            Text { anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter } text: "Open a clip"; color: Theme.bright; font.family: Theme.display; font.pixelSize: 19; font.weight: Font.DemiBold }
            Rectangle {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: 30; height: 30; radius: 15; color: xma.containsMouse ? Theme.field : "transparent"
                Icon { anchors.centerIn: parent; name: "close"; size: 16; tint: Theme.dim }
                MouseArea { id: xma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sheet.open = false }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.hair }
        }
        ListView {
            id: list
            anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: foot.top; margins: 8 }
            clip: true; model: sheet.clips; spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width; height: 46; radius: Theme.radiusSm
                color: rma.containsMouse ? Theme.field : "transparent"
                Icon { id: fic; anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter } name: "film"; size: 18; tint: Theme.ember }
                Text { anchors { left: fic.right; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter } text: Backend.basename(parent.modelData); color: Theme.cream; font.family: Theme.font; font.pixelSize: 13; elide: Text.ElideMiddle }
                MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { sheet.chosen("file://" + parent.modelData); sheet.open = false; } }
            }
        }
        Text {
            anchors.centerIn: list
            visible: sheet.clips.length === 0
            text: "No clips in ~/Videos yet.\nRecord one, or browse below."
            horizontalAlignment: Text.AlignHCenter; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13
        }
        Item {
            id: foot
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 54
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.hair }
            TopBtn { anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter } label: "Browse files…"; onTapped: browse.open() }
        }
    }
    FileDialog {
        id: browse
        nameFilters: ["Video (*.mp4 *.mkv *.mov *.webm)"]
        onAccepted: { sheet.chosen(selectedFile); sheet.open = false; }
    }
}

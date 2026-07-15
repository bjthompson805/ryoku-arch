import QtQuick
import QtQuick.Controls
import "Singletons"

// The library: a scrollable column of VM cards bound to Vm.vms. Picking a card
// selects it for the detail hero on the right. An empty library invites a build.
Item {
    id: g

    property string filter: ""
    signal buildRequested()

    readonly property var shown: {
        if (g.filter.length === 0)
            return Vm.vms;
        var f = g.filter.toLowerCase();
        return Vm.vms.filter(v => v.name.toLowerCase().indexOf(f) >= 0 || (v.guest || "").toLowerCase().indexOf(f) >= 0);
    }

    ListView {
        id: list
        anchors.fill: parent
        visible: g.shown.length > 0
        clip: true
        spacing: 10
        model: g.shown
        cacheBuffer: 800
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: BoardScrollBar {}

        // yard roll-call on first population only: a populate transition never
        // runs for delegates the view creates while scrolling (the old
        // per-delegate Component.onCompleted animation replayed on every
        // scroll-back and every model refresh — the launch/scroll flicker).
        populate: Transition {
            id: popT
            SequentialAnimation {
                PropertyAction { property: "opacity"; value: 0 }
                PauseAnimation { duration: 50 * Math.min(popT.ViewTransition.index, 8) }
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.medium; easing.type: Theme.ease }
                    NumberAnimation { property: "y"; from: popT.ViewTransition.destination.y + 14; to: popT.ViewTransition.destination.y; duration: Theme.medium; easing.type: Theme.ease }
                }
            }
        }
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.medium; easing.type: Theme.ease }
        }

        delegate: Item {
            id: slot
            required property var modelData
            required property int index
            width: list.width
            height: 68
            VmCard {
                width: parent.width - 6
                item: slot.modelData
                active: Vm.selectedName === slot.modelData.name
                onPicked: Vm.select(slot.modelData.name)
            }
        }
    }

    // empty state.
    Column {
        anchors.centerIn: parent
        spacing: 12
        width: parent.width - 40
        visible: g.shown.length === 0
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: Vm.vmsLoading ? "refresh" : (g.filter.length > 0 ? "search" : "server")
            size: 32
            tint: Theme.faint
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
            wrapMode: Text.WordWrap
            text: Vm.vmsLoading ? "Loading your machines"
                : (g.filter.length > 0 ? "No machines match"
                : "No machines yet.")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 13
        }
        HubButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Vm.vmsLoading && g.filter.length === 0
            primary: true
            icon: "download"
            label: "Open Catalog"
            onClicked: g.buildRequested()
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "Singletons"

// One bundle: a header with its name, sources, blurb, an install/uninstall-all
// action and an installed count, expanding to the per-tool list. Steady state
// comes from `statuses` (the status query the page runs); while an install or
// remove this card started is running, the live report file overrides it until
// the page hands back a fresh status.
Rectangle {
    id: card

    property var bundle: ({})
    property var statuses: ({})          // { itemName: status } steady state
    property string reportDir: ""

    signal installAll()
    signal removeAll()
    signal installItem(string name)
    signal removeItem(string name)
    signal refreshRequested()

    property bool expanded: false
    property bool armed: false           // a user action from this card is in flight
    property var live: ({})              // { itemName: {status, reason} } from the report

    onStatusesChanged: { card.armed = false; card.live = ({}); }

    readonly property var items: bundle.items || []

    function effStatus(name) {
        if (card.armed && card.live[name])
            return card.live[name].status;
        if (card.statuses[name] !== undefined)
            return card.statuses[name];
        return "absent";
    }
    function effReason(name) {
        return (card.armed && card.live[name]) ? (card.live[name].reason || "") : "";
    }
    function isHere(s) { return s === "present" || s === "installed"; }

    readonly property int installedCount: {
        var n = 0;
        for (var i = 0; i < items.length; i++)
            if (isHere(effStatus(items[i].name))) n++;
        return n;
    }
    readonly property bool anyPackagePresent: {
        for (var i = 0; i < items.length; i++)
            if (items[i].type === "package" && isHere(effStatus(items[i].name))) return true;
        return false;
    }

    color: Theme.surface
    radius: 16
    border.width: 1
    border.color: card.expanded ? Qt.rgba(0.95, 0.42, 0.18, 0.35) : Theme.line
    Behavior on border.color { ColorAnimation { duration: Theme.quick } }

    implicitWidth: parent ? parent.width : 0
    implicitHeight: header.height + (card.expanded ? itemsCol.implicitHeight + 8 : 0)
    Behavior on implicitHeight { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }
    clip: true

    FileView {
        id: report
        path: card.reportDir + "/" + (card.bundle.id || "_") + ".json"
        watchChanges: true
        onLoaded: card.applyReport(report.text())
        onFileChanged: report.reload()
        onLoadFailed: {}
    }

    function applyReport(t) {
        try {
            var o = JSON.parse(t);
            card.live = o.items || ({});
            if (o.phase === "done" && card.armed)
                card.refreshRequested();
        } catch (e) {}
    }

    // --- header -------------------------------------------------------------
    Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 78

        TapHandler { onTapped: card.expanded = !card.expanded }

        Icon {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            name: "sparkles"
            size: 22
            weight: 1.5
            tint: Theme.ember
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 16
            anchors.right: actions.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Row {
                spacing: 10
                Text {
                    text: card.bundle.name || ""
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: (card.bundle.sources || "") !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.bundle.sources || ""
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 9
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
            }

            Text {
                width: parent.width
                text: card.bundle.description || ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Text {
                text: card.installedCount + " of " + card.items.length + " installed"
                color: card.installedCount > 0 ? Theme.cream : Theme.faint
                font.family: Theme.mono
                font.pixelSize: 10
            }
        }

        Row {
            id: actions
            anchors.right: chevron.left
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Install all"
                icon: "download"
                primary: true
                onClicked: card.installAll()
            }
            ActionPill {
                anchors.verticalCenter: parent.verticalCenter
                visible: card.anyPackagePresent
                label: "Uninstall all"
                icon: "trash"
                danger: true
                onClicked: card.removeAll()
            }
        }

        Icon {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            name: "chevron"
            size: 18
            weight: 2
            tint: Theme.dim
            rotation: card.expanded ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 1
        color: Theme.line
        visible: card.expanded
    }

    // --- items --------------------------------------------------------------
    Column {
        id: itemsCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.leftMargin: 20
        anchors.rightMargin: 16
        anchors.topMargin: 4
        visible: card.expanded

        Repeater {
            model: card.items
            delegate: ExtraItemRow {
                required property var modelData
                itemName: modelData.name
                summary: modelData.summary || ""
                itemType: modelData.type
                source: modelData.source || ""
                status: card.effStatus(modelData.name)
                reason: card.effReason(modelData.name)
                onInstall: card.installItem(modelData.name)
                onRemove: card.removeItem(modelData.name)
            }
        }
    }
}

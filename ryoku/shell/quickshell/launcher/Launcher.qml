import QtQuick
import Quickshell
import "Singletons"
import "providers"

// The command palette body: a search row over either the rest dashboard (empty
// query), the action-mode tabs + list ("/" prefix), or the ranked result list.
// Ctrl+K opens the selected row's action panel. Grows and shrinks with its
// content on the Ryoku morph curve. Providers register with the dispatcher; this
// view only renders what the dispatcher returns.
Item {
    id: root

    property real s: 1
    property bool shown: false
    property string query: ""

    signal requestClose()

    readonly property var results: shown ? Dispatcher.results(query, Metrics.maxResults) : []
    readonly property int totalCount: shown ? Dispatcher.results("", 0).length : 0
    readonly property bool resting: query.length === 0
    readonly property bool actionMode: query.charAt(0) === "/"
    readonly property var selectedActions: {
        var r = root.results[list.selectedIndex];
        return r && r.actions ? r.actions : [];
    }

    readonly property real cardW: Metrics.windowW * s
    readonly property int visibleRows: 8
    readonly property real listH: Math.min(results.length, visibleRows) * (Metrics.rowHeight + Metrics.gapRow) * s
    readonly property real tabsH: actionMode ? tabs.implicitHeight + 6 * s : 0
    readonly property real bodyH: resting ? rest.implicitHeight : (results.length > 0 ? listH : empty.implicitHeight)
    readonly property real contentH: tabsH + bodyH

    implicitWidth: cardW
    implicitHeight: search.height + divider.height + contentH + Metrics.padOuter * 2 * s

    Behavior on implicitHeight {
        NumberAnimation { duration: Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
    }

    Providers { id: providers }

    // the action-mode tabs drive which category the actions provider lists.
    Binding {
        target: providers.actions
        property: "activeCategory"
        value: tabs.activeCategory
        when: root.actionMode
    }

    onShownChanged: {
        if (shown) {
            root.query = "";
            search.clear();
            list.selectedIndex = 0;
            panel.open = false;
            Qt.callLater(search.focusField);
        }
    }
    onQueryChanged: panel.open = false;

    Rectangle {
        anchors.fill: parent
        radius: Metrics.radiusWindow * root.s
        color: Theme.cardTop
        border.width: 1
        border.color: Theme.border
    }

    SearchRow {
        id: search
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: (Metrics.padOuter - 8) * root.s
        s: root.s
        resultCount: root.results.length
        totalCount: root.totalCount
        onTextChanged: { root.query = text; list.selectedIndex = 0; }
        onMoved: (d) => { if (panel.open) panel.move(d); else list.move(d); }
        onAccepted: { if (panel.open) panel.run(); else list.activate(); }
        onDismissed: { if (panel.open) panel.open = false; else root.requestClose(); }
        onKeyPressed: (e) => {
            if (e.key === Qt.Key_K && (e.modifiers & Qt.ControlModifier)) {
                if (root.selectedActions.length > 0)
                    panel.open = !panel.open;
                e.accepted = true;
            } else if (root.actionMode && e.key === Qt.Key_Tab) {
                tabs.cycle(1); e.accepted = true;
            } else if (root.actionMode && e.key === Qt.Key_Backtab) {
                tabs.cycle(-1); e.accepted = true;
            }
        }
    }

    Rectangle {
        id: divider
        anchors.top: search.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Metrics.padOuter * root.s
        anchors.rightMargin: Metrics.padOuter * root.s
        height: 1
        color: Theme.hair
    }

    CategoryTabs {
        id: tabs
        visible: root.actionMode
        anchors.top: divider.bottom
        anchors.topMargin: 8 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Metrics.padOuter * root.s
        anchors.rightMargin: Metrics.padOuter * root.s
        s: root.s
    }

    RestDashboard {
        id: rest
        visible: root.resting
        anchors.top: divider.bottom
        anchors.topMargin: Metrics.padRow * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Metrics.padOuter * root.s
        anchors.rightMargin: Metrics.padOuter * root.s
        s: root.s
    }

    ResultList {
        id: list
        visible: !root.resting && root.results.length > 0
        anchors.top: root.actionMode ? tabs.bottom : divider.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: (Metrics.padOuter - Metrics.padRow) * root.s
        anchors.rightMargin: (Metrics.padOuter - Metrics.padRow) * root.s
        height: root.listH
        s: root.s
        results: root.results
        query: root.actionMode ? root.query.slice(1) : root.query
        onActivated: root.requestClose()
    }

    Text {
        id: empty
        visible: !root.resting && root.results.length === 0
        anchors.top: root.actionMode ? tabs.bottom : divider.bottom
        anchors.topMargin: Metrics.padRow * root.s
        anchors.horizontalCenter: parent.horizontalCenter
        text: "No matches"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 12 * root.s
        implicitHeight: 40 * root.s
    }

    ActionPanel {
        id: panel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Metrics.padOuter * root.s
        height: open ? Math.min(root.selectedActions.length, 5) * 31 * root.s + 28 * root.s : 0
        s: root.s
        actions: root.selectedActions
        onChosen: { panel.open = false; root.requestClose(); }
    }
}

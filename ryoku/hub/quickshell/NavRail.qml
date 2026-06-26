pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import "Singletons"

// The navigation rail: brand header, a global search field (it searches content
// across every section), then the section list. Items flagged `pinned` (Profile,
// the showcase) sit on their own at the top, never inside a group. The rest are
// grouped into drawers that animate open and closed; group headers use the
// Profile dossier idiom (brand dot, mono label, hairline rule between groups).
// The group holding the current section is always open (its label brightens, no
// chevron); an expand/collapse-all control in the header tucks or reveals the
// rest. A single sliding selector marks the active row.
Rectangle {
    id: rail

    property var sections: []
    property string current: "displays"
    property alias query: search.text
    signal navigate(string section)
    signal escaped()

    function focusSearch() { search.focusInput(); }

    readonly property int navTop: 96 + 54 + 8
    readonly property int navItemH: 44
    readonly property int groupHeaderH: 40
    readonly property int pinnedGap: 18          // space + rule between pinned items and the groups

    // Open state, derived (no init timing): a group is open iff it holds the
    // current section or the user expanded it. Default {} => only the current
    // group is open, so the rail starts tucked. Reassign the map (never mutate)
    // so bindings retrigger.
    property var userExpanded: ({})

    readonly property var pinnedSections: rail.sections.filter(s => s.pinned === true)
    readonly property var groupedSections: rail.sections.filter(s => s.pinned !== true)

    readonly property var groups: {
        var seen = ({});
        var out = [];
        for (var i = 0; i < rail.groupedSections.length; i++) {
            var g = rail.groupedSections[i].group;
            if (!seen[g]) { seen[g] = true; out.push(g); }
        }
        return out;
    }

    function groupOf(key) {
        for (var i = 0; i < rail.sections.length; i++)
            if (rail.sections[i].key === key)
                return rail.sections[i].group || "";
        return "";
    }

    function isExpanded(group) {
        return group === rail.groupOf(rail.current) || rail.userExpanded[group] === true;
    }

    readonly property bool allExpanded: {
        for (var i = 0; i < rail.groups.length; i++)
            if (!rail.isExpanded(rail.groups[i]))
                return false;
        return true;
    }

    // The updates section is the only one that carries a badge; surface it on its
    // group's header while that group is collapsed, so a pending update is never
    // hidden by tucking System away.
    function groupBadge(group) {
        for (var i = 0; i < rail.sections.length; i++)
            if (rail.sections[i].group === group && rail.sections[i].key === "updates")
                return Updates.available ? Updates.behind : 0;
        return 0;
    }

    function expandAll() {
        var e = ({});
        for (var i = 0; i < rail.groups.length; i++)
            e[rail.groups[i]] = true;
        rail.userExpanded = e;
    }
    function collapseAll() { rail.userExpanded = ({}); }   // only the current group stays open
    function toggleGroup(g) {
        if (g === rail.groupOf(rail.current))
            return;                       // the current group never collapses
        var e = Object.assign({}, rail.userExpanded);
        e[g] = !e[g];
        rail.userExpanded = e;
    }
    function toggleAll() { if (rail.allExpanded) rail.collapseAll(); else rail.expandAll(); }

    // Absolute y of a section's row: pinned items first, then a gap, then the
    // groups (a header per group, items only while the group is open) so the
    // sliding selector lands on the visible row.
    function itemY(key) {
        var y = 0;
        for (var i = 0; i < rail.pinnedSections.length; i++) {
            if (rail.pinnedSections[i].key === key)
                return y;
            y += rail.navItemH;
        }
        if (rail.pinnedSections.length > 0)
            y += rail.pinnedGap;
        var last = null;
        for (var j = 0; j < rail.groupedSections.length; j++) {
            var s = rail.groupedSections[j];
            if (s.group !== last) {
                y += rail.groupHeaderH;
                last = s.group;
            }
            if (s.key === key)
                return y;
            if (rail.isExpanded(s.group))
                y += rail.navItemH;
        }
        return 0;
    }

    color: Theme.rail

    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: Theme.line
    }

    // brand + search
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        Item {
            width: parent.width
            height: 96

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 44
                    source: Qt.resolvedUrl("brand-icon.png")
                    sourceSize.width: 96
                    sourceSize.height: 96
                    smooth: true
                    fillMode: Image.PreserveAspectFit
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        text: "Ryoku Settings"
                        color: Theme.bright
                        font.family: Theme.font
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.2
                    }

                    Text {
                        text: "System & shell"
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                }
            }

            // Expand-all / collapse-all: tucks every group away (bar the current
            // one) or reveals them all. Sits above the list per the sidebar header
            // convention.
            Item {
                id: expandAllBtn
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 28
                height: 28

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: expandHover.hovered ? Theme.keyTop : "transparent"
                    border.width: expandHover.hovered ? 1 : 0
                    border.color: Theme.line
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                }

                Icon {
                    anchors.centerIn: parent
                    name: rail.allExpanded ? "collapse" : "expand"
                    size: 17
                    weight: 1.9
                    tint: expandHover.hovered ? Theme.ember : Theme.faint
                    Behavior on tint { ColorAnimation { duration: Theme.quick } }
                }

                HoverHandler { id: expandHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: rail.toggleAll() }
            }
        }

        Item {
            width: parent.width
            height: 54

            SearchField {
                id: search
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                placeholder: "Search everything\u2026"
                onEscaped: rail.escaped()
            }
        }
    }

    // section list, scrollable when it overflows the rail
    Flickable {
        id: navFlick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: rail.navTop
        anchors.bottom: footer.top
        anchors.bottomMargin: 14
        clip: true
        contentHeight: listCol.height
        boundsBehavior: Flickable.StopAtBounds
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        // Sliding selection indicator (scrolls with the list; dimmed during search).
        Rectangle {
            id: selector
            x: 12
            width: navFlick.width - 24
            height: 42
            radius: 11
            y: rail.itemY(rail.current) + (rail.navItemH - height) / 2
            color: Theme.keyTop
            border.width: 1
            border.color: Theme.line
            opacity: rail.query.length > 0 ? 0.4 : 1
            Behavior on y { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }
            Behavior on opacity { NumberAnimation { duration: Theme.quick } }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 1
                height: 3
                radius: 3
                color: Theme.keyBot
            }
        }

        Column {
            id: listCol
            width: navFlick.width
            spacing: 0

            // Pinned items (Profile): standalone at the top, always shown.
            Repeater {
                model: rail.pinnedSections

                delegate: NavButton {
                    required property var modelData
                    width: listCol.width
                    height: rail.navItemH
                    icon: modelData.icon
                    label: modelData.name
                    selected: rail.current === modelData.key
                    onClicked: rail.navigate(modelData.key)
                }
            }

            // Separator between the pinned items and the grouped drawers.
            Item {
                width: listCol.width
                height: rail.pinnedSections.length > 0 ? rail.pinnedGap : 0
                visible: rail.pinnedSections.length > 0

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 24
                    anchors.rightMargin: 18
                    height: 1
                    color: Theme.line
                }
            }

            Repeater {
                model: rail.groupedSections

                delegate: Column {
                    id: row
                    required property int index
                    required property var modelData
                    readonly property bool firstOfGroup: row.index === 0 || rail.groupedSections[row.index - 1].group !== row.modelData.group
                    readonly property bool groupOpen: rail.isExpanded(row.modelData.group)
                    readonly property bool currentGroup: row.modelData.group === rail.groupOf(rail.current)
                    width: parent.width

                    // Group header: a hairline rule between groups, a brand accent
                    // dot, and a mono label. The current group brightens and drops
                    // its chevron (it never collapses); a tucked group surfaces its
                    // updates badge here.
                    Item {
                        width: parent.width
                        height: row.firstOfGroup ? rail.groupHeaderH : 0
                        visible: row.firstOfGroup

                        Rectangle {
                            visible: row.index > 0
                            anchors.top: parent.top
                            anchors.topMargin: 9
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 24
                            anchors.rightMargin: 18
                            height: 1
                            color: Theme.line
                        }

                        Row {
                            id: hdrRow
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 9
                            spacing: 9

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 5
                                height: 5
                                radius: 1.5
                                color: Theme.brand
                            }

                            Text {
                                id: groupLabel
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.modelData.group
                                color: row.currentGroup ? Theme.subtle : (hdrHover.hovered ? Theme.cream : Theme.faint)
                                font.family: Theme.mono
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.letterSpacing: 2.2
                                font.capitalization: Font.AllUppercase
                                Behavior on color { ColorAnimation { duration: Theme.quick } }
                            }

                            Icon {
                                visible: !row.currentGroup
                                anchors.verticalCenter: parent.verticalCenter
                                name: "chevron"
                                size: 12
                                weight: 2
                                tint: hdrHover.hovered ? Theme.cream : Theme.faint
                                rotation: row.groupOpen ? 0 : -90
                                Behavior on rotation { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }
                                Behavior on tint { ColorAnimation { duration: Theme.quick } }
                            }
                        }

                        Rectangle {
                            visible: !row.groupOpen && rail.groupBadge(row.modelData.group) > 0
                            anchors.right: parent.right
                            anchors.rightMargin: 22
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 7
                            width: Math.max(16, hdrBadge.implicitWidth + 10)
                            height: 15
                            radius: 7.5
                            color: Theme.ember

                            Text {
                                id: hdrBadge
                                anchors.centerIn: parent
                                text: "" + rail.groupBadge(row.modelData.group)
                                color: Theme.onAccent
                                font.family: Theme.font
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                        }

                        HoverHandler { id: hdrHover; enabled: !row.currentGroup; cursorShape: Qt.PointingHandCursor }
                        TapHandler { enabled: !row.currentGroup; onTapped: rail.toggleGroup(row.modelData.group) }
                    }

                    // The nav row, height-animated as the drawer opens and closes.
                    Item {
                        width: parent.width
                        height: row.groupOpen ? rail.navItemH : 0
                        visible: height > 0.5
                        clip: true
                        Behavior on height { NumberAnimation { duration: Theme.medium; easing.type: Theme.ease } }

                        NavButton {
                            width: parent.width
                            height: rail.navItemH
                            icon: row.modelData.icon
                            label: row.modelData.name
                            badge: row.modelData.key === "updates" ? (Updates.available ? Updates.behind : 0) : 0
                            selected: rail.current === row.modelData.key
                            onClicked: rail.navigate(row.modelData.key)
                        }
                    }
                }
            }
        }
    }

    Text {
        id: footer
        anchors.left: parent.left
        anchors.leftMargin: 26
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 22
        text: "\u529b  ryoku desktop"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 11
        font.weight: Font.Medium
    }
}

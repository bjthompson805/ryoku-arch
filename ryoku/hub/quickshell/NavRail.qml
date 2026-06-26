pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as QQC
import "Singletons"

// The navigation rail, in three bands: a fixed top (items flagged pinned "top" —
// Profile, the showcase), a scrolling middle (the grouped sections), and a fixed
// foot (items flagged pinned "bottom" — Updates, the maintenance entry, which
// keeps its badge permanently in view). The middle groups are drawers that
// animate open and closed; their headers use the Profile dossier idiom (brand
// dot, mono label, hairline rule between groups). The group holding the current
// section is always open (brighter label, no chevron); an expand/collapse-all
// control in the header tucks or reveals the rest. A sliding selector marks the
// active row in the middle band; the pinned bands draw their own selection.
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
    readonly property int pinnedGap: 18          // space + rule framing the scrolling band

    // Open state, derived (no init timing): a group is open iff it holds the
    // current section or the user expanded it. Default {} => only the current
    // group is open, so the rail starts tucked.
    property var userExpanded: ({})

    readonly property var pinnedTop: rail.sections.filter(s => s.pinned === "top")
    readonly property var pinnedBottom: rail.sections.filter(s => s.pinned === "bottom")
    readonly property var groupedSections: rail.sections.filter(s => !s.pinned)

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
    function sectionPinned(key) {
        for (var i = 0; i < rail.sections.length; i++)
            if (rail.sections[i].key === key)
                return rail.sections[i].pinned || "";
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

    // Absolute y of a grouped section's row within the scrolling band: a header
    // per group, items only while the group is open, so the sliding selector
    // lands on the visible row.
    function itemY(key) {
        var y = 0;
        var last = null;
        for (var i = 0; i < rail.groupedSections.length; i++) {
            var s = rail.groupedSections[i];
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

    // A pinned row (top or bottom band): a NavButton with its own selection pill,
    // since the sliding selector only roams the scrolling middle band.
    component PinnedRow: Item {
        id: pin
        property var section: ({})
        width: parent ? parent.width : 0
        height: rail.navItemH

        Rectangle {
            visible: rail.current === pin.section.key
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 1
            anchors.bottomMargin: 1
            radius: 11
            color: Theme.keyTop
            border.width: 1
            border.color: Theme.line

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

        NavButton {
            anchors.fill: parent
            icon: pin.section.icon
            label: pin.section.name
            badge: pin.section.key === "updates" ? (Updates.available ? Updates.behind : 0) : 0
            selected: rail.current === pin.section.key
            onClicked: rail.navigate(pin.section.key)
        }
    }

    // A hairline that frames the scrolling band from the pinned bands.
    component BandRule: Item {
        width: parent ? parent.width : 0
        height: rail.pinnedGap
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

    // brand + search
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // Brand: a 力 seal (the live brand kanji set in a carbon hanko, not a flat
        // image) beside the RYOKU ARCH wordmark and its subtitle.
        Item {
            width: parent.width
            height: 96

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 22
                anchors.verticalCenter: parent.verticalCenter
                spacing: 13

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 42
                    height: 42
                    radius: 11
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.cardTop }
                        GradientStop { position: 1.0; color: Theme.cardBot }
                    }
                    border.width: 1
                    border.color: Qt.alpha(Theme.ember, 0.5)

                    Text {
                        anchors.centerIn: parent
                        text: "\u529b"
                        color: Theme.ember
                        font.family: Theme.font
                        font.pixelSize: 24
                        font.weight: Font.Black
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Row {
                        spacing: 6
                        Text {
                            text: "RYOKU"
                            color: Theme.bright
                            font.family: Theme.font
                            font.pixelSize: 15
                            font.weight: Font.Black
                            font.letterSpacing: 3
                        }
                        Text {
                            text: "ARCH"
                            color: Theme.ember
                            font.family: Theme.font
                            font.pixelSize: 15
                            font.weight: Font.Black
                            font.letterSpacing: 3
                        }
                    }

                    Text {
                        text: "system and shell settings"
                        color: Theme.dim
                        font.family: Theme.mono
                        font.pixelSize: 9
                        font.weight: Font.Medium
                        font.letterSpacing: 0.5
                    }
                }
            }
        }

        // Search, with the expand/collapse-all control for the group drawers tucked
        // at its right so the brand owns the full row above.
        Item {
            width: parent.width
            height: 54

            Item {
                id: expandAllBtn
                anchors.right: parent.right
                anchors.rightMargin: 14
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

            SearchField {
                id: search
                anchors.left: parent.left
                anchors.right: expandAllBtn.left
                anchors.leftMargin: 16
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                placeholder: "Search\u2026"
                onEscaped: rail.escaped()
            }
        }
    }

    // ── Fixed top band: pinned "top" items (Profile) ─────────────────────────
    Column {
        id: topBand
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: rail.navTop
        spacing: 0

        Repeater {
            model: rail.pinnedTop
            delegate: PinnedRow {
                required property var modelData
                width: topBand.width
                section: modelData
            }
        }
        BandRule { visible: rail.pinnedTop.length > 0; height: rail.pinnedTop.length > 0 ? rail.pinnedGap : 0 }
    }

    // ── Fixed foot band: pinned "bottom" items (Updates) ─────────────────────
    Column {
        id: bottomBand
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        anchors.bottomMargin: 8
        spacing: 0

        BandRule { visible: rail.pinnedBottom.length > 0; height: rail.pinnedBottom.length > 0 ? rail.pinnedGap : 0 }
        Repeater {
            model: rail.pinnedBottom
            delegate: PinnedRow {
                required property var modelData
                width: bottomBand.width
                section: modelData
            }
        }
    }

    // ── Scrolling middle band: the grouped drawers ───────────────────────────
    Flickable {
        id: navFlick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topBand.bottom
        anchors.bottom: bottomBand.top
        clip: true
        contentHeight: listCol.height
        boundsBehavior: Flickable.StopAtBounds
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        // Sliding selection indicator (hidden when a pinned band item is current).
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
            opacity: rail.query.length > 0 ? 0.4 : (rail.sectionPinned(rail.current) !== "" ? 0 : 1)
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
                    // its chevron (it never collapses).
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

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Notifications
import "Singletons"

/**
 * 力 INBOX surface: the notification center, opened by the pill's bell icon.
 * Notifications group per app with expandable stacks, critical entries gain a
 * vermilion hairline, an empty state reads IDLE, and CLEAR wipes the lot.
 * Opening marks everything seen after a short beat so the bell's unread ember
 * clears once it is read. The Ame bead docks as a seam on the focused row.
 * Connectivity lives in its own LINK surface; this one is notifications only.
 */
PillSurface {
    id: root

    mTop: 13
    mLeft: 16
    mRight: 16
    mBottom: 13

    implicitHeight: mainCol.implicitHeight

    /**
     * Row-soul focus registry. Each hoverable row reports itself here; the bead
     * docks as a glowing seam at the left edge of the focused row and hides when
     * nothing is focused.
     */
    property Item focusRowItem: null
    function reportRowHover(item, hovered) {
        if (hovered)
            focusRowItem = item;
    }
    readonly property bool rowFocused: focusRowItem !== null && active

    readonly property point rowPoint: {
        void root.width;
        void root.height;
        void mainCol.implicitHeight;
        void root.focusRowItem;
        if (!focusRowItem)
            return Qt.point(4 * s, root.height / 2);
        return focusRowItem.mapToItem(root, 4 * s, focusRowItem.height / 2);
    }

    ameForm: rowFocused ? "rowseam" : "off"
    amePoint: rowPoint

    onActiveChanged: {
        if (active) {
            seenTimer.restart();
        } else {
            seenTimer.stop();
            focusRowItem = null;
        }
    }

    Timer {
        id: seenTimer
        interval: 600
        repeat: false
        onTriggered: Notifs.markAllSeen()
    }

    /**
     * Single inbox entry: icon tile or diamond, body text, ×N coalesce badge,
     * age label that cross-fades into a dismiss glyph on hover. Critical entries
     * gain a vermilion left hairline and cream emphasis.
     */
    component NotifRow: Rectangle {
        id: nrow

        required property var entry
        property bool critical: false
        readonly property var n: entry.n

        width: parent ? parent.width : 0
        height: 26 * root.s
        radius: 7 * root.s
        color: nrowHover.hovered ? Theme.frameBg : "transparent"

        HoverHandler {
            id: nrowHover
            onHoveredChanged: root.reportRowHover(nrow, hovered)
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                Notifs.activateEntry(nrow.entry);
                root.requestClose();
            }
        }

        Rectangle {
            visible: nrow.critical
            anchors.left: parent.left
            anchors.leftMargin: 1 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 2 * root.s
            height: parent.height - 10 * root.s
            radius: 999
            color: Theme.verm
        }

        Rectangle {
            id: nrowTile
            anchors.left: parent.left
            anchors.leftMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 16 * root.s
            height: 16 * root.s
            radius: 5 * root.s
            color: Theme.tileBg
            border.width: 1
            border.color: Theme.border

            Image {
                id: nrowImg
                anchors.fill: parent
                anchors.margins: nrow.n.image ? 0 : 2 * root.s
                source: Notifs.iconFor(nrow.n)
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectCrop
                smooth: true
                visible: source.toString().length > 0
            }

            Rectangle {
                anchors.centerIn: parent
                visible: !nrowImg.visible
                width: 5 * root.s
                height: 5 * root.s
                radius: 1.5 * root.s
                rotation: 45
                color: nrow.critical ? Theme.vermLit : Theme.verm
            }
        }

        Text {
            anchors.left: nrowTile.right
            anchors.leftMargin: 8 * root.s
            anchors.right: nrowRight.left
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: nrow.n.body.length > 0 ? nrow.n.body : nrow.n.summary
            color: nrow.critical ? Theme.cream : Theme.subtle
            font.family: Theme.font
            font.pixelSize: 10.5 * root.s
            font.weight: nrow.critical ? Font.DemiBold : Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
            textFormat: Text.PlainText
        }

        Row {
            id: nrowRight
            anchors.right: parent.right
            anchors.rightMargin: 8 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s

            Text {
                visible: nrow.entry.count > 1
                anchors.verticalCenter: parent.verticalCenter
                text: "×" + nrow.entry.count
                color: nrow.critical ? Theme.vermLit : Theme.vermDim
                font.family: Theme.font
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
            }

            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(nrowAge.implicitWidth, nrowX.implicitWidth)
                height: Math.max(nrowAge.implicitHeight, nrowX.implicitHeight)

                Text {
                    id: nrowAge
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: nrowHover.hovered ? 0 : 1
                    text: Notifs.ageLabel(nrow.n)
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 9 * root.s
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }

                Text {
                    id: nrowX
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: nrowHover.hovered ? 1 : 0
                    text: "✕"
                    color: nrowXArea.containsMouse ? Theme.cream : Theme.dim
                    font.pixelSize: 10 * root.s
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                    MouseArea {
                        id: nrowXArea
                        anchors.fill: parent
                        anchors.margins: -6 * root.s
                        enabled: nrowHover.hovered
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Notifs.dismissEntry(nrow.entry)
                    }
                }
            }
        }
    }

    Column {
        id: mainCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 4 * root.s

        Item {
            width: parent.width
            height: 24 * root.s

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8 * root.s

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "力"
                    color: Theme.brand
                    font.family: Theme.fontJp
                    font.weight: Font.Medium
                    font.pixelSize: 16 * root.s
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "INBOX"
                    color: Theme.subtle
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                    font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6 * root.s
                }
            }

            Item {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: Notifs.count > 0
                width: clearRow.implicitWidth
                height: 20 * root.s

                Row {
                    id: clearRow
                    anchors.centerIn: parent
                    spacing: 4 * root.s

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CLR"
                        color: clearArea.containsMouse ? Theme.vermLit : Theme.vermDim
                        font.family: Theme.font
                        font.pixelSize: 9 * root.s
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CLEAR"
                        color: clearArea.containsMouse ? Theme.vermLit : Theme.vermDim
                        font.family: Theme.font
                        font.pixelSize: 9 * root.s
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4 * root.s
                    }
                }

                MouseArea {
                    id: clearArea
                    anchors.fill: parent
                    anchors.margins: -5 * root.s
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifs.clearAll()
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.hair
        }

        Item {
            visible: Notifs.count > 0
            width: parent.width
            height: notifFlick.height

            Flickable {
                id: notifFlick
                width: parent.width
                height: Math.min(notifCol.implicitHeight, 360 * root.s)
                contentHeight: notifCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onContentHeightChanged: returnToBounds()

                Column {
                    id: notifCol
                    width: notifFlick.width
                    spacing: 6 * root.s

                    Repeater {
                        model: Notifs.groups

                        Column {
                            id: group
                            required property var modelData
                            readonly property bool expanded: Notifs.expandedApps[modelData.app] === true
                            width: notifCol.width
                            spacing: 2 * root.s

                            Repeater {
                                model: group.modelData.criticals

                                NotifRow {
                                    required property var modelData
                                    entry: modelData
                                    critical: true
                                }
                            }

                            Rectangle {
                                id: groupHead
                                width: parent.width
                                height: 32 * root.s
                                radius: 8 * root.s
                                color: headHover.hovered ? Theme.frameBg : "transparent"

                                HoverHandler {
                                    id: headHover
                                    onHoveredChanged: root.reportRowHover(groupHead, hovered)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Notifs.toggleExpanded(group.modelData.app)
                                }

                                Rectangle {
                                    id: headTile
                                    anchors.left: parent.left
                                    anchors.leftMargin: 6 * root.s
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 20 * root.s
                                    height: 20 * root.s
                                    radius: 6 * root.s
                                    color: Theme.tileBg
                                    border.width: 1
                                    border.color: Theme.border

                                    Image {
                                        id: headImg
                                        anchors.fill: parent
                                        anchors.margins: group.modelData.newest.image ? 0 : 3 * root.s
                                        source: Notifs.iconFor(group.modelData.newest)
                                        sourceSize.width: 64
                                        sourceSize.height: 64
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        visible: source.toString().length > 0
                                    }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: !headImg.visible
                                        width: 6 * root.s
                                        height: 6 * root.s
                                        radius: 2 * root.s
                                        rotation: 45
                                        color: Theme.verm
                                    }
                                }

                                Text {
                                    id: headName
                                    anchors.left: headTile.right
                                    anchors.leftMargin: 8 * root.s
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, 110 * root.s)
                                    text: group.modelData.app
                                    color: Theme.subtle
                                    font.family: Theme.font
                                    font.pixelSize: 9 * root.s
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 1.2 * root.s
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: headCount
                                    anchors.left: headName.right
                                    anchors.leftMargin: 5 * root.s
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "· " + group.modelData.count
                                    color: Theme.faint
                                    font.family: Theme.font
                                    font.pixelSize: 9 * root.s
                                }

                                Text {
                                    anchors.left: headCount.right
                                    anchors.leftMargin: 8 * root.s
                                    anchors.right: headX.left
                                    anchors.rightMargin: 8 * root.s
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: group.modelData.preview.body.length > 0
                                        ? group.modelData.preview.body
                                        : group.modelData.preview.summary
                                    color: Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: 10 * root.s
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    textFormat: Text.PlainText
                                }

                                Text {
                                    id: headChev
                                    anchors.right: parent.right
                                    anchors.rightMargin: 8 * root.s
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: group.expanded ? "▾" : "▸"
                                    color: Theme.faint
                                    font.pixelSize: 9 * root.s
                                }

                                Text {
                                    id: headX
                                    anchors.right: headChev.left
                                    anchors.rightMargin: 7 * root.s
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: headHover.hovered ? 1 : 0
                                    text: "✕"
                                    color: headXArea.containsMouse ? Theme.cream : Theme.dim
                                    font.pixelSize: 10 * root.s
                                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                                    MouseArea {
                                        id: headXArea
                                        anchors.fill: parent
                                        anchors.margins: -6 * root.s
                                        enabled: headHover.hovered
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Notifs.dismissApp(group.modelData.app)
                                    }
                                }
                            }

                            Column {
                                visible: group.expanded
                                width: parent.width
                                spacing: 2 * root.s

                                Repeater {
                                    model: group.expanded ? group.modelData.entries : []

                                    NotifRow {
                                        required property var modelData
                                        entry: modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }

            WheelScroller {
                anchors.fill: parent
                s: root.s
                flick: notifFlick
            }
        }

        Column {
            visible: Notifs.count === 0
            width: parent.width
            topPadding: 18 * root.s
            bottomPadding: 18 * root.s
            spacing: 4 * root.s

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "IDLE"
                color: Theme.ghost
                opacity: 0.55
                font.family: Theme.font
                font.weight: Font.Medium
                font.pixelSize: 32 * root.s
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SILENCE"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 9 * root.s
                font.weight: Font.Bold
                font.letterSpacing: 2.2 * root.s
            }
        }
    }
}

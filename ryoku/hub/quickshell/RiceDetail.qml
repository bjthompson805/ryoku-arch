import QtQuick
import "Singletons"

// the drill-in for one rice: a large preview, the name and a plain-language
// summary of what applying it changes, an optional note of the behavior it also
// sets, and the primary Apply action beside Duplicate / Delete. Back returns to
// the grid. grows by implicitHeight so the Appearance tab's outer Flickable
// scrolls it.
Item {
    id: detail

    property var rice: ({})
    signal back()
    signal applied(var layers)
    signal forked()
    signal removed()

    implicitWidth: 600
    implicitHeight: col.implicitHeight

    readonly property var layerKeys: detail.rice.layers ? Object.keys(detail.rice.layers) : []

    function changeSummary() {
        var parts = [];
        var look = detail.rice.look || ({});
        if (look.hypr && Object.keys(look.hypr).length > 0)
            parts.push("windows");
        if (look.shell && Object.keys(look.shell).length > 0)
            parts.push("shell + bar");
        if (detail.rice.color)
            parts.push("colours");
        var a = detail.rice.assets || ({});
        if (a.wallpaper)
            parts.push("wallpaper");
        if (a.cursor)
            parts.push("cursor");
        if (a.hero)
            parts.push("launcher art");
        return parts.join("  \u00b7  ");
    }

    Column {
        id: col
        width: detail.width
        spacing: 16

        Row {
            spacing: 12
            Rectangle {
                width: 34
                height: 34
                radius: Theme.radius
                color: bh.hovered ? Theme.keyTop : "transparent"
                border.width: 1
                border.color: bh.hovered ? Theme.ember : Theme.line
                Behavior on border.color { ColorAnimation { duration: Theme.quick } }
                Icon {
                    anchors.centerIn: parent
                    name: "chevron"
                    rotation: 90
                    size: 15
                    weight: 2
                    tint: bh.hovered ? Theme.bright : Theme.dim
                }
                HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: detail.back() }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    text: detail.rice.name || detail.rice.slug || ""
                    color: Theme.bright
                    font.family: Theme.font
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Changes " + detail.changeSummary()
                    color: Theme.faint
                    font.family: Theme.mono
                    font.pixelSize: 11
                    font.letterSpacing: 0.5
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Math.min(320, parent.width * 0.5)
            radius: Theme.radius
            clip: true
            color: Theme.surfaceLo
            border.width: 1
            border.color: Theme.line
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Theme.radius
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.keyTop }
                    GradientStop { position: 1.0; color: Theme.surfaceLo }
                }
                Icon {
                    anchors.centerIn: parent
                    name: "palette"
                    size: 46
                    tint: Theme.faint
                    visible: pv.status !== Image.Ready
                }
            }
            Image {
                id: pv
                anchors.fill: parent
                anchors.margins: 1
                source: detail.rice.preview || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 1200
            }
        }

        Text {
            visible: (detail.rice.blurb || "") !== ""
            width: parent.width
            text: detail.rice.blurb || ""
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 13
            wrapMode: Text.WordWrap
            lineHeight: 1.4
        }

        // behavior the rice also carries: shown only when present, applied with
        // the look (kept out of the primary path so most rices read as one tap).
        Column {
            visible: detail.layerKeys.length > 0
            width: parent.width
            spacing: 6
            Text {
                text: "ALSO SETS"
                color: Theme.dim
                font.family: Theme.mono
                font.pixelSize: 10
                font.letterSpacing: 1.5
            }
            Text {
                width: parent.width
                text: detail.layerKeys.join(", ")
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        Row {
            spacing: 10
            HubButton {
                label: detail.rice.active ? "Applied" : "Apply this rice"
                icon: "check"
                primary: true
                enabled: !detail.rice.active
                onClicked: detail.applied(detail.layerKeys)
            }
            HubButton {
                label: "Duplicate"
                icon: "plus"
                onClicked: detail.forked()
            }
            HubButton {
                label: "Delete"
                icon: "trash"
                onClicked: detail.removed()
            }
        }
    }
}

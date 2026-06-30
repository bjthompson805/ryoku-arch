pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "Singletons"

// Wallhaven downloader: browse on the left, live rice preview on the right.
Rectangle {
    id: app

    implicitWidth: 1180
    implicitHeight: 760

    gradient: Gradient {
        GradientStop { position: 0.0; color: Theme.bgTop }
        GradientStop { position: 1.0; color: Theme.bgBot }
    }

    property bool settingsOpen: false
    readonly property bool fitOn: Wallhaven.ratios.length > 0

    // nearest wallhaven aspect for the primary monitor, for the Fit toggle.
    readonly property string screenRatio: {
        var s = (Quickshell.screens && Quickshell.screens.length > 0) ? Quickshell.screens[0] : null;
        if (!s || !s.width || !s.height)
            return "16x9";
        var a = s.width / s.height;
        var t = [["9x16", 0.5625], ["10x16", 0.625], ["1x1", 1], ["5x4", 1.25], ["4x3", 1.333],
            ["3x2", 1.5], ["16x10", 1.6], ["16x9", 1.777], ["21x9", 2.333], ["32x9", 3.555]];
        var best = "16x9", bd = 1e9;
        for (var i = 0; i < t.length; i++) {
            var d = Math.abs(t[i][1] - a);
            if (d < bd) { bd = d; best = t[i][0]; }
        }
        return best;
    }

    focus: true
    Keys.onEscapePressed: { if (app.settingsOpen) app.settingsOpen = false; else Qt.quit(); }
    Component.onCompleted: if (Wallhaven.results.length === 0) Wallhaven.searchLatest("")

    // ---- header -------------------------------------------------------------
    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 40
        anchors.rightMargin: 22
        anchors.topMargin: 18
        height: 54

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Row {
                spacing: 10
                Text { anchors.verticalCenter: parent.verticalCenter; text: "力"; color: Theme.brand; font.family: Theme.fontJp; font.pixelSize: 22 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Wallhaven"; color: Theme.bright; font.family: Theme.font; font.pixelSize: 26; font.weight: Font.DemiBold }
            }
            Text { text: "Find a wallpaper, preview the rice, set it."; color: Theme.dim; font.family: Theme.font; font.pixelSize: 12 }
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            IconBtn { name: "gear"; onClicked: app.settingsOpen = true }
            IconBtn { name: "close"; danger: true; onClicked: Qt.quit() }
        }
    }

    // ---- toolbar ------------------------------------------------------------
    Item {
        id: toolbar
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 40
        anchors.rightMargin: 24
        anchors.topMargin: 10
        height: 40

        Rectangle {
            id: searchBox
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 300
            height: 36
            radius: 9
            color: Theme.surfaceLo
            border.width: 1
            border.color: input.activeFocus ? Theme.ember : Theme.line
            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

            Icon { id: si; anchors.left: parent.left; anchors.leftMargin: 11; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 15; tint: Theme.dim }
            TextInput {
                id: input
                anchors.left: si.right
                anchors.leftMargin: 9
                anchors.right: parent.right
                anchors.rightMargin: 11
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.bright
                font.family: Theme.font
                font.pixelSize: 13
                selectByMouse: true
                selectionColor: Theme.frameBg
                clip: true
                onAccepted: Wallhaven.searchLatest(text)
                Text {
                    anchors.fill: parent
                    visible: input.text.length === 0
                    verticalAlignment: Text.AlignVCenter
                    text: "Search wallhaven"
                    color: Theme.faint
                    font: input.font
                }
            }
        }

        Segmented {
            id: sorter
            anchors.left: searchBox.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            segW: 96
            model: [{ key: "", label: "Latest" }, { key: "1w", label: "Top week" }, { key: "1M", label: "Top month" }]
            current: Wallhaven.topRange
            onSelected: (k) => Wallhaven.searchTop(k)
        }

        // Fit-to-screen toggle chip.
        Rectangle {
            id: fitChip
            anchors.left: sorter.right
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: 34
            width: fitRow.implicitWidth + 24
            radius: height / 2
            color: app.fitOn ? Theme.frameBg : Theme.surfaceLo
            border.width: 1
            border.color: app.fitOn ? Theme.ember : (fitHover.hovered ? Qt.alpha(Theme.ember, 0.6) : Theme.line)
            Behavior on border.color { ColorAnimation { duration: Theme.quick } }
            Behavior on color { ColorAnimation { duration: Theme.quick } }
            Row {
                id: fitRow
                anchors.centerIn: parent
                spacing: 7
                Icon { anchors.verticalCenter: parent.verticalCenter; name: "display"; size: 14; tint: app.fitOn ? Theme.ember : Theme.cream }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Fit screen"; color: app.fitOn ? Theme.ember : Theme.cream; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium }
            }
            HoverHandler { id: fitHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Wallhaven.setRatios(app.fitOn ? "" : app.screenRatio) }
        }

        // pager.
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            IconBtn { name: "chevron-left"; dim: Wallhaven.page <= 1 || Wallhaven.searching; onClicked: Wallhaven.prevPage() }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "" + Wallhaven.page
                color: Wallhaven.searching ? Theme.ember : Theme.subtle
                font.family: Theme.mono
                font.pixelSize: 13
                Behavior on color { ColorAnimation { duration: Theme.quick } }
            }
            IconBtn { name: "chevron-right"; dim: Wallhaven.searching; onClicked: Wallhaven.nextPage() }
        }
    }

    // ---- main: browse | preview --------------------------------------------
    Item {
        id: main
        anchors.top: toolbar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: statusBar.top
        anchors.leftMargin: 40
        anchors.rightMargin: 24
        anchors.topMargin: 12
        anchors.bottomMargin: 6

        WallGrid {
            id: grid
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.46
        }

        Rectangle {
            id: gutter
            anchors.left: grid.right
            anchors.leftMargin: 20
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            width: 1
            color: Theme.line
        }

        PreviewPane {
            anchors.left: gutter.right
            anchors.leftMargin: 24
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
        }
    }

    // ---- status bar ---------------------------------------------------------
    Item {
        id: statusBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 40
        anchors.rightMargin: 24
        height: 28

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Wallhaven.status.length > 0 ? Wallhaven.status
                : (Wallhaven.results.length > 0 ? Wallhaven.results.length + " wallpapers" : "")
            color: Wallhaven.status.length > 0 ? Theme.ember : Theme.faint
            font.family: Theme.mono
            font.pixelSize: 11
            font.letterSpacing: 0.5
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "wallhaven.cc"
            color: Theme.faint
            font.family: Theme.mono
            font.pixelSize: 11
        }
    }

    SettingsPanel {
        anchors.fill: parent
        open: app.settingsOpen
        onClosed: app.settingsOpen = false
    }

    component IconBtn: Item {
        id: ib
        property string name: ""
        property bool danger: false
        property bool dim: false
        signal clicked()
        width: 30
        height: 30
        opacity: ib.dim ? 0.35 : 1
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: ibHover.hovered && !ib.dim ? Theme.keyTop : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }
        Icon {
            anchors.centerIn: parent
            name: ib.name
            size: 16
            tint: ib.danger ? (ibHover.hovered ? Theme.ember : Theme.faint)
                : (ibHover.hovered && !ib.dim ? Theme.bright : Theme.cream)
            Behavior on tint { ColorAnimation { duration: Theme.quick } }
        }
        HoverHandler { id: ibHover; enabled: !ib.dim; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: !ib.dim; onTapped: ib.clicked() }
    }
}

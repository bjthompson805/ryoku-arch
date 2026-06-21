pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// Themes: full-system "rices". Each is a folder under ~/.config/hypr/themes/ with
// its look (rounding, gaps, blur, opacity, layout) and, for fixed palettes, a
// 16-colour scheme. Applying one (ryoku-hub hypr theme <slug>) sets the appearance
// store so the Look/Borders tabs reflect it, writes the palette every consumer
// reads (kitty, the visualiser, window borders), and reloads. The shell frame and
// island keep the Ryoku identity by design.
//
// Embedded as an Appearance tab: it has no Flickable of its own and grows by
// implicitHeight so the tab's outer Flickable scrolls it.
import Quickshell.Io

Item {
    id: page

    property var themes: []
    property bool loading: true
    property string applying: ""

    implicitWidth: 600
    implicitHeight: col.implicitHeight

    Component.onCompleted: page.reload()
    function reload() { listProc.running = true; }
    function apply(slug) {
        page.applying = slug;
        applyProc.command = ["ryoku-hub", "hypr", "theme", slug];
        applyProc.running = true;
    }

    Process {
        id: listProc
        command: ["ryoku-hub", "hypr", "themes"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.themes = JSON.parse(this.text); } catch (e) { page.themes = []; }
                page.loading = false;
            }
        }
    }
    Process {
        id: applyProc
        stdout: StdioCollector {
            onStreamFinished: {
                page.applying = "";
                listProc.running = true;
            }
        }
    }

    Column {
        id: col
        width: page.width
        spacing: 18

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Full-system looks. A theme restyles your windows, borders, terminal, and palette in one click. The frame and island keep the Ryoku identity."
            color: Theme.subtle
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Text {
            visible: page.loading
            text: "Loading themes\u2026"
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 14
        }

        Flow {
            width: parent.width
            spacing: 14

            Repeater {
                model: page.themes

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool active: !!card.modelData.active
                    readonly property bool busy: page.applying === card.modelData.slug

                    width: (col.width - 28) / 3
                    height: 170
                    radius: 14
                    color: hov.hovered ? Theme.surface : Theme.surfaceLo
                    border.width: card.active ? 2 : 1
                    border.color: card.active ? Theme.ember : Theme.line
                    scale: hov.hovered && !card.active ? 1.012 : 1
                    Behavior on border.color { ColorAnimation { duration: Theme.quick } }
                    Behavior on color { ColorAnimation { duration: Theme.quick } }
                    Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }

                    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: if (!card.active) page.apply(card.modelData.slug) }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Item {
                            width: parent.width
                            height: 22
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.modelData.name
                                color: Theme.bright
                                font.family: Theme.font
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                            }
                            Rectangle {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: card.active
                                width: 20; height: 20; radius: 10
                                color: Theme.ember
                                Icon { anchors.centerIn: parent; name: "check"; size: 12; tint: Theme.onAccent }
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: card.busy
                                text: "applying\u2026"
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: 11
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 5
                            Repeater {
                                model: card.modelData.swatch || []
                                delegate: Rectangle {
                                    required property string modelData
                                    width: (card.width - 32 - 25) / 6
                                    height: 22
                                    radius: 5
                                    color: modelData
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: card.modelData.blurb
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 12
                        }

                        Row {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: card.modelData.tags || []
                                delegate: Rectangle {
                                    required property string modelData
                                    height: 18
                                    width: tagText.width + 16
                                    radius: 9
                                    color: Theme.keyTop
                                    border.width: 1
                                    border.color: Theme.line
                                    Text {
                                        id: tagText
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        color: Theme.subtle
                                        font.family: Theme.font
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

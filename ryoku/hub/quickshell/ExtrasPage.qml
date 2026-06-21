pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Singletons"

// The Extras section: curated bundles of tools from the ryoku-extras catalogue,
// each installed or removed as a whole or item by item. ryoku-hub fetches the
// catalogue; ryoku-extras-install does the work in a floating terminal (it needs
// a TTY for the sudo and AUR prompts) and publishes a per-bundle report the cards
// watch. This page renders the list and routes the buttons.
Item {
    id: page

    property var bundles: []
    property var statusMap: ({})
    property bool loading: true
    property bool loadFailed: false

    readonly property string reportDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ryoku-extras"

    Component.onCompleted: page.reload()

    function reload() {
        page.loading = true;
        page.loadFailed = false;
        catalogProc.running = true;
    }

    Process {
        id: catalogProc
        command: ["ryoku-hub", "extras", "catalog"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(this.text);
                    page.bundles = o.bundles || [];
                    page.loadFailed = page.bundles.length === 0;
                } catch (e) {
                    page.bundles = [];
                    page.loadFailed = true;
                }
                page.loading = false;
                statusProc.running = true;
            }
        }
    }

    Process {
        id: statusProc
        command: ["ryoku-extras-install", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(this.text);
                    var m = ({});
                    var bs = o.bundles || [];
                    for (var i = 0; i < bs.length; i++) {
                        var im = ({});
                        var its = bs[i].items || [];
                        for (var j = 0; j < its.length; j++)
                            im[its[j].name] = its[j].status;
                        m[bs[i].id] = im;
                    }
                    page.statusMap = m;
                } catch (e) {
                    page.statusMap = ({});
                }
            }
        }
    }

    function runTerminal(args) {
        Quickshell.execDetached(["kitty", "--class", "ryoku-extras", "-e"].concat(args));
    }

    // --- loading / empty states --------------------------------------------
    Column {
        anchors.centerIn: parent
        visible: page.loading || page.loadFailed
        spacing: 16
        width: Math.min(page.width - 96, 420)

        Spinner {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.loading
            size: 26
        }
        Icon {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.loadFailed
            name: "sparkles"
            size: 44
            tint: Theme.faint
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.loadFailed
            text: "Couldn't load the extras catalogue."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
        }
        HubButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: page.loadFailed
            label: "Try again"
            icon: "refresh"
            onClicked: page.reload()
        }
    }

    // --- bundle list --------------------------------------------------------
    Flickable {
        id: flick
        anchors.fill: parent
        visible: !page.loading && !page.loadFailed
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            id: sb
            policy: ScrollBar.AsNeeded
            width: 7
            contentItem: Rectangle {
                implicitWidth: 4
                radius: 2
                color: Theme.line
                opacity: sb.pressed ? 0.9 : (sb.hovered ? 0.7 : 0.4)
                Behavior on opacity { NumberAnimation { duration: Theme.quick } }
            }
        }

        Column {
            id: col
            width: flick.width - 10
            spacing: 14
            topPadding: 4
            bottomPadding: 16

            Repeater {
                model: page.bundles
                delegate: ExtraBundleCard {
                    required property var modelData
                    width: col.width
                    bundle: modelData
                    statuses: page.statusMap[modelData.id] || ({})
                    reportDir: page.reportDir
                    onInstallAll: page.runTerminal(["ryoku-extras-install", "install", "bundle", modelData.id])
                    onRemoveAll: page.runTerminal(["ryoku-extras-install", "remove", "bundle", modelData.id])
                    onInstallItem: (name) => page.runTerminal(["ryoku-extras-install", "install", "item", modelData.id, name])
                    onRemoveItem: (name) => page.runTerminal(["ryoku-extras-install", "remove", "item", modelData.id, name])
                    onRefreshRequested: statusProc.running = true
                }
            }
        }
    }
}

import QtQuick
import "Singletons"

// Ryoku Store, unified: browse + install shell plugins and extras bundles in
// one place. segmented switch flips catalogues; one refresh sits left of the
// switch and re-pulls whichever side is showing. managing what's already
// installed lives on Add-ons, so this only browses + installs.
Item {
    id: store

    property string tab: "plugins"

    ShowcaseBackdrop { anchors.fill: parent }

    // refresh (left) + Plugins / Bundles switch.
    Row {
        id: head
        anchors.top: parent.top
        anchors.left: parent.left
        spacing: 12
        z: 3

        Rectangle {
            id: refreshBtn
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: 9
            readonly property bool spinning: store.tab === "plugins" ? pluginsPage.refreshing : extrasPage.loading
            color: rHover.hovered ? Theme.surface : "transparent"
            border.width: 1
            border.color: rHover.hovered ? Theme.ember : Theme.line
            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

            Icon {
                anchors.centerIn: parent
                name: "refresh"
                size: 15
                weight: 2
                tint: rHover.hovered ? Theme.bright : Theme.dim
                RotationAnimation on rotation { running: refreshBtn.spinning; loops: Animation.Infinite; from: 0; to: 360; duration: 800 }
            }
            HoverHandler { id: rHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    if (store.tab === "plugins") {
                        pluginsPage.refreshing = true;
                        pluginsPage.loadCatalog();
                        pluginsPage.refresh();
                    } else {
                        extrasPage.reload();
                    }
                }
            }
        }

        Segmented {
            id: seg
            anchors.verticalCenter: parent.verticalCenter
            model: [
                { "key": "plugins", "label": "Plugins" },
                { "key": "bundles", "label": "Bundles" }
            ]
            current: store.tab
            onSelected: (k) => store.tab = k
        }
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: head.bottom
        anchors.topMargin: 18
        anchors.bottom: parent.bottom

        PluginsPage {
            id: pluginsPage
            anchors.fill: parent
            visible: store.tab === "plugins"
            storeMode: true
        }

        ExtrasPage {
            id: extrasPage
            anchors.fill: parent
            visible: store.tab === "bundles"
            storeMode: true
        }
    }
}

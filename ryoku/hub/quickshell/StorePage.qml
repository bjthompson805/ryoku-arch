import QtQuick

/**
 * The unified Ryoku Store: browse and install shell plugins and extras bundles
 * from one place. A segmented switch flips between the two catalogues, each its
 * existing storefront (the plugin discover grid + showcase, and the bundle bento
 * grid + detail). Managing what is already installed lives on the Add-ons page, so
 * the store only browses and installs.
 */
Item {
    id: store

    property string tab: "plugins"

    Segmented {
        id: seg
        anchors.top: parent.top
        anchors.left: parent.left
        z: 3
        model: [
            { "key": "plugins", "label": "Plugins" },
            { "key": "bundles", "label": "Bundles" }
        ]
        current: store.tab
        onSelected: (k) => store.tab = k
    }

    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: seg.bottom
        anchors.topMargin: 18
        anchors.bottom: parent.bottom

        PluginsPage {
            anchors.fill: parent
            visible: store.tab === "plugins"
            storeMode: true
        }

        ExtrasPage {
            anchors.fill: parent
            visible: store.tab === "bundles"
        }
    }
}

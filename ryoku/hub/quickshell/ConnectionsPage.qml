pragma ComponentBehavior: Bound
import QtQuick
import "Singletons"

// The Connections section: Wi-Fi, Bluetooth, and Hotspot, each a subtab. The
// subtab bar reuses the hub Segmented control; each tab is a self-contained page
// backed by the Quickshell Networking/Bluetooth services (and nmcli/bluetoothctl).
Item {
    id: page

    property string sub: "wifi"

    Segmented {
        id: tabs
        anchors.left: parent.left
        anchors.top: parent.top
        model: [
            { "key": "wifi", "label": "Wi-Fi" },
            { "key": "bluetooth", "label": "Bluetooth" },
            { "key": "hotspot", "label": "Hotspot" }
        ]
        current: page.sub
        onSelected: (k) => page.sub = k
    }

    Loader {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: tabs.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 22
        sourceComponent: page.sub === "wifi" ? wifiComp
            : (page.sub === "bluetooth" ? btComp : hsComp)
    }

    Component { id: wifiComp; WifiTab {} }
    Component { id: btComp; BluetoothTab {} }
    Component { id: hsComp; HotspotTab {} }
}

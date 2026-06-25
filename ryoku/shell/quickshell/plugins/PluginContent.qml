import QtQuick

/**
 * Loads a plugin's content/Widget.qml from an external file and parents it here.
 * Uses Qt.createComponent + createObject rather than `Loader { source: url }`,
 * because an `Image` inside Loader-loaded external QML does not composite its
 * texture in a Quickshell surface (it reaches Ready with paintedWidth 0). Created
 * objects render correctly. The host sets `url` and the plugin properties via the
 * `configure` callback once the item exists.
 */
Item {
    id: root

    property string url: ""
    property var configure: null   // function(item) -> void, called after create
    property var item: null

    onUrlChanged: _build()
    Component.onCompleted: _build()

    function _build() {
        if (item) { item.destroy(); item = null; }
        if (!url || url.length === 0)
            return;
        var c = Qt.createComponent(url);
        function make() {
            if (c.status === Component.Ready) {
                item = c.createObject(root);
                if (item && configure)
                    configure(item);
            } else if (c.status === Component.Error) {
                console.warn("PluginContent:", c.errorString());
            }
        }
        if (c.status === Component.Loading)
            c.statusChanged.connect(make);
        else
            make();
    }

    // Size to the created item so the host (desktop slot) can measure it.
    implicitWidth: item ? item.implicitWidth : 0
    implicitHeight: item ? item.implicitHeight : 0
}

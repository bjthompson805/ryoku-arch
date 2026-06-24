pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Live config for the desktop widgets, the single source of truth for the knobs
 * Ryoku Settings' Desktop Widgets section edits, the desktop drag/right-click
 * actions write, and the shipped defaults everything falls back to. Persisted as
 * JSON at ~/.config/ryoku/widgets.json and watched, so a save in Ryoku Settings or
 * a drag on the desktop retunes the running widgets on the next file event.
 *
 * Placement is either a compass anchor (one of nine zones, kept across resolutions
 * by a fixed edge margin) or "free": an absolute x/y in monitor pixels, set by
 * dragging the widget on the desktop. Dragging switches a widget to "free";
 * snapping it to a zone (the right-click menu or Ryoku Settings) switches it back.
 * Scale, background, radius, opacity and design are independent knobs. The write
 * helpers below let the desktop edit the same file Ryoku Settings does.
 */
Singleton {
    id: root

    // --- Clock --------------------------------------------------------------
    property alias clockEnabled: adapter.clockEnabled
    property alias clockDesign:  adapter.clockDesign   // digital | minimal | analog | flip | rings
    property alias clock24h:     adapter.clock24h
    property alias clockSeconds: adapter.clockSeconds
    property alias clockAccent:  adapter.clockAccent   // wallust | brand | mono
    property alias clockScale:   adapter.clockScale
    property alias clockAnchor:  adapter.clockAnchor   // top-left .. center .. bottom-right | free
    property alias clockX:       adapter.clockX        // free placement, monitor pixels
    property alias clockY:       adapter.clockY
    property alias clockLocked:  adapter.clockLocked   // prevent drag/resize
    property alias clockOpacity: adapter.clockOpacity
    property alias clockBg:      adapter.clockBg        // none | card | glass
    property alias clockRadius:  adapter.clockRadius
    property alias dateShow:     adapter.dateShow
    property alias dateDesign:   adapter.dateDesign     // inline | badge | stacked

    // --- Weather ------------------------------------------------------------
    property alias weatherEnabled: adapter.weatherEnabled
    property alias weatherDesign:  adapter.weatherDesign  // card | minimal | strip
    property alias weatherUnit:    adapter.weatherUnit    // C | F
    property alias weatherScope:   adapter.weatherScope   // today | week
    property alias weatherAnimate: adapter.weatherAnimate
    property alias weatherScale:   adapter.weatherScale
    property alias weatherAnchor:  adapter.weatherAnchor
    property alias weatherX:       adapter.weatherX
    property alias weatherY:       adapter.weatherY
    property alias weatherLocked:  adapter.weatherLocked
    property alias weatherOpacity: adapter.weatherOpacity
    property alias weatherBg:      adapter.weatherBg       // none | card | glass
    property alias weatherRadius:  adapter.weatherRadius

    // Write helpers used by the desktop drag and right-click menu. Each writes the
    // same file Ryoku Settings does; the watch above reloads it (a no-op for the
    // values just written), so the running widgets and the next Settings open agree.
    function set(key, value) {
        adapter[key] = value;
        file.writeAdapter();
    }
    // In-memory only (no file write), for a live drag like resize: the aliases
    // update at once so the widget re-renders, and a setFree/set on release does
    // the single persisting write.
    function setLive(key, value) {
        adapter[key] = value;
    }
    function toggle(key) {
        adapter[key] = !adapter[key];
        file.writeAdapter();
    }
    function setAnchor(prefix, zone) {
        adapter[prefix + "Anchor"] = zone;
        file.writeAdapter();
    }
    function setFree(prefix, x, y) {
        adapter[prefix + "Anchor"] = "free";
        adapter[prefix + "X"] = x;
        adapter[prefix + "Y"] = y;
        file.writeAdapter();
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/widgets.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()

        JsonAdapter {
            id: adapter
            property bool clockEnabled: true
            property string clockDesign: "digital"
            property bool clock24h: true
            property bool clockSeconds: false
            property string clockAccent: "wallust"
            property real clockScale: 1.0
            property string clockAnchor: "top-left"
            property int clockX: 72
            property int clockY: 64
            property bool clockLocked: false
            property real clockOpacity: 1.0
            property string clockBg: "none"
            property int clockRadius: 26
            property bool dateShow: true
            property string dateDesign: "inline"

            property bool weatherEnabled: true
            property string weatherDesign: "card"
            property string weatherUnit: "C"
            property string weatherScope: "today"
            property bool weatherAnimate: true
            property real weatherScale: 1.0
            property string weatherAnchor: "top-right"
            property int weatherX: 72
            property int weatherY: 64
            property bool weatherLocked: false
            property real weatherOpacity: 1.0
            property string weatherBg: "glass"
            property int weatherRadius: 26
        }
    }

    Component.onCompleted: if (!file.text()) file.writeAdapter();
}

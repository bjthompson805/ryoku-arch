pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import "Singletons"

/**
 * Placement, shape and interaction frame for one desktop widget. It measures its
 * single child's natural size, pads it, and positions it either at a compass zone
 * (a fixed margin in from that screen edge) or, once dragged, at a free monitor
 * pixel. It draws the chosen backing (none/card/glass), and carries the desktop
 * interaction: drag to move (snapping to the grid, with a press bump), right-click
 * to raise the widget menu, and a per-widget lock that freezes it. Dragging
 * persists a "free" position to the widgets Config; the menu and Ryoku Settings
 * write the same file. The widget grip takes the press over the desktop catcher
 * beneath it, so a right-click on the widget opens its menu, not the desktop one.
 */
Item {
    id: slot

    property string widget: "clock"            // config prefix, for persistence
    property string anchor: "top-left"         // 9 zones | free
    property real freeX: 72
    property real freeY: 64
    property bool locked: false
    property real pad: 0
    property string bg: "none"                 // none | card | glass
    property real radius: 26
    property real gridSize: 32
    property real zoneMargin: 64
    property real scaleCfg: 1                   // current Config <widget>Scale, for the resize readout

    signal menuRequested(real x, real y, string widget)

    default property alias content: holder.data

    readonly property Item item: holder.children.length > 0 ? holder.children[0] : null
    readonly property real cw: slot.item ? slot.item.implicitWidth : 0
    readonly property real ch: slot.item ? slot.item.implicitHeight : 0

    // Drag state. While holding (dragging, or briefly after release until the
    // config write lands) the rendered position follows the drag so it never
    // flickers back to the old anchor for a frame.
    property bool dragging: false
    property real dragX: 0
    property real dragY: 0
    property bool resizing: false
    property real resizeOX: 0
    property real resizeOY: 0
    property real resizeStartScale: 1
    property real resizeStartDiag: 1
    readonly property bool holding: slot.dragging || slot.resizing || guard.running

    width: Math.max(1, slot.cw + slot.pad * 2)
    height: Math.max(1, slot.ch + slot.pad * 2)

    function clampX(v) { return Math.max(0, Math.min(v, (slot.parent ? slot.parent.width : v + slot.width) - slot.width)); }
    function clampY(v) { return Math.max(0, Math.min(v, (slot.parent ? slot.parent.height : v + slot.height) - slot.height)); }
    function snap(v) { return Math.round(v / slot.gridSize) * slot.gridSize; }
    function zoneX() {
        const w = slot.parent ? slot.parent.width : slot.width;
        if (slot.anchor.indexOf("left") >= 0) return slot.zoneMargin;
        if (slot.anchor.indexOf("right") >= 0) return w - slot.width - slot.zoneMargin;
        return (w - slot.width) / 2;
    }
    function zoneY() {
        const h = slot.parent ? slot.parent.height : slot.height;
        if (slot.anchor.indexOf("top") >= 0) return slot.zoneMargin;
        if (slot.anchor.indexOf("bottom") >= 0) return h - slot.height - slot.zoneMargin;
        return (h - slot.height) / 2;
    }

    x: slot.holding ? slot.dragX : (slot.anchor === "free" ? slot.clampX(slot.freeX) : slot.zoneX())
    y: slot.holding ? slot.dragY : (slot.anchor === "free" ? slot.clampY(slot.freeY) : slot.zoneY())

    Behavior on x { enabled: !slot.holding; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !slot.holding; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

    // Press bump: a gentle lift while dragging, so the widget feels picked up.
    scale: slot.dragging ? 1.03 : 1.0
    transformOrigin: Item.Center
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutExpo } }

    Timer { id: guard; interval: 90 }

    // Soft lift off the wallpaper for the backed styles.
    MultiEffect {
        source: backing
        anchors.fill: backing
        visible: slot.bg !== "none"
        shadowEnabled: true
        shadowColor: Qt.rgba(0, 0, 0, 0.5)
        shadowBlur: 1.0
        shadowVerticalOffset: 6
        blurMax: 32
        autoPaddingEnabled: true
    }

    Rectangle {
        id: backing
        anchors.fill: parent
        visible: slot.bg !== "none"
        radius: slot.radius
        color: slot.bg === "card" ? Qt.rgba(0, 0, 0, 0.42) : Qt.rgba(16 / 255, 16 / 255, 24 / 255, 0.26)
        border.width: 1
        border.color: slot.bg === "card" ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.16)

        // Glass sheen: a faint top-down highlight so the panel reads as a pane of
        // glass rather than a flat fill.
        Rectangle {
            visible: slot.bg === "glass"
            anchors.fill: parent
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.10) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.06) }
            }
        }
    }

    // Lift a bare widget off the wallpaper for legibility on any backdrop. A
    // card/glass panel already gives contrast, so the shadow is applied only when
    // the widget sits directly on the wallpaper.
    Item {
        id: holder
        x: slot.pad
        y: slot.pad
        width: slot.cw
        height: slot.ch
        layer.enabled: slot.bg === "none"
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(0, 0, 0, 0.5)
            shadowBlur: 0.8
            shadowVerticalOffset: 2
            blurMax: 28
            autoPaddingEnabled: true
        }
    }

    // Interaction: drag to move (snapped to the grid), right-click for the menu.
    MouseArea {
        id: grip
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: slot.locked ? Qt.ArrowCursor : (slot.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

        property bool leftDown: false
        property real grabOX: 0
        property real grabOY: 0

        onPressed: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                const pr = slot.mapToItem(slot.parent, mouse.x, mouse.y);
                slot.menuRequested(pr.x, pr.y, slot.widget);
                return;
            }
            if (slot.locked)
                return;
            grip.leftDown = true;
            const p = slot.mapToItem(slot.parent, mouse.x, mouse.y);
            grip.grabOX = p.x - slot.x;
            grip.grabOY = p.y - slot.y;
        }
        onPositionChanged: (mouse) => {
            if (!grip.leftDown || slot.locked)
                return;
            const p = slot.mapToItem(slot.parent, mouse.x, mouse.y);
            const nx = p.x - grip.grabOX;
            const ny = p.y - grip.grabOY;
            if (!slot.dragging) {
                if (Math.abs(nx - slot.x) < 6 && Math.abs(ny - slot.y) < 6)
                    return;
                slot.dragging = true;
            }
            slot.dragX = slot.clampX(slot.snap(nx));
            slot.dragY = slot.clampY(slot.snap(ny));
        }
        onReleased: (mouse) => {
            if (slot.dragging) {
                Config.setFree(slot.widget, Math.round(slot.dragX), Math.round(slot.dragY));
                slot.dragging = false;
                guard.restart();
            }
            grip.leftDown = false;
        }
    }

    // Hover state for the slot and its children, so the resize handle stays lit
    // while you reach across to it.
    HoverHandler { id: slotHover }

    // Quick resize: drag the bottom-right bracket to scrub the widget's scale. The
    // top-left is pinned while resizing so it grows toward the cursor; on release
    // the new scale and a pinned free position persist in one write.
    Item {
        id: handle
        width: 22
        height: 22
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        opacity: ((slotHover.hovered && !slot.locked && !slot.dragging) || slot.resizing) ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 13
            height: 2
            radius: 1
            color: (hgrip.containsMouse || slot.resizing) ? Theme.brand : Theme.faint
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        Rectangle {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 2
            height: 13
            radius: 1
            color: (hgrip.containsMouse || slot.resizing) ? Theme.brand : Theme.faint
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        MouseArea {
            id: hgrip
            anchors.fill: parent
            enabled: !slot.locked
            acceptedButtons: Qt.LeftButton
            hoverEnabled: true
            cursorShape: Qt.SizeFDiagCursor

            onPressed: (mouse) => {
                const ox = slot.x;
                const oy = slot.y;
                slot.dragX = ox;
                slot.dragY = oy;
                slot.resizeOX = ox;
                slot.resizeOY = oy;
                slot.resizeStartScale = slot.scaleCfg;
                const p = hgrip.mapToItem(slot.parent, mouse.x, mouse.y);
                slot.resizeStartDiag = Math.max(1, Math.hypot(p.x - ox, p.y - oy));
                slot.resizing = true;
            }
            onPositionChanged: (mouse) => {
                if (!slot.resizing)
                    return;
                const p = hgrip.mapToItem(slot.parent, mouse.x, mouse.y);
                const diag = Math.hypot(p.x - slot.resizeOX, p.y - slot.resizeOY);
                const ns = Math.max(0.5, Math.min(2.5, slot.resizeStartScale * diag / slot.resizeStartDiag));
                Config.setLive(slot.widget + "Scale", ns);
            }
            onReleased: (mouse) => {
                if (slot.resizing) {
                    Config.setFree(slot.widget, Math.round(slot.resizeOX), Math.round(slot.resizeOY));
                    slot.resizing = false;
                    guard.restart();
                }
            }
        }
    }

    // Live size readout while resizing.
    Rectangle {
        visible: slot.resizing
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 26
        anchors.bottomMargin: 26
        width: roText.implicitWidth + 16
        height: 20
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.62)
        Text {
            id: roText
            anchors.centerIn: parent
            text: Math.round(slot.scaleCfg * 100) + "%"
            color: Theme.ink
            font.family: Theme.mono
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
    }
}

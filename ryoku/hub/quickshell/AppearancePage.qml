pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "Singletons"
// Appearance: the system look and feel. Look/Borders/Cursor edit the Hyprland
// config live through the ryoku-hub hypr backend (settings.lua, applied via
// hyprctl eval; Save persists, Revert and leaving restore). Wallpaper retheme the
// desktop (the wallust palette follows the wallpaper) via ryoku-shell, and Comfort
// (backlight, night light) act at once through the shipped tools.
Item {
    id: page

    HyprStore { id: store }

    // Read by the hub to drop an unsaved live preview when this page is left.
    readonly property bool previewDirty: store.dirty

    property string group: "themes"
    property var cursorThemes: []

    Process {
        id: cursorsProc
        command: ["ryoku-hub", "hypr", "cursors"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.cursorThemes = JSON.parse(this.text); } catch (e) {}
            }
        }
    }

    readonly property bool storeTab: page.group === "look" || page.group === "borders" || page.group === "cursor"

    // --- Wallpaper (the theme): pick one to retheme via the wallust palette. Routes
    // through ryoku-shell wallpaper, the same path the shell's quick strip uses. ---
    readonly property string wpDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string wpState: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku-wallpaper"
    property var wallpapers: []
    property string currentWall: ""

    function refreshWalls() { wallListProc.running = true; wallStateProc.running = true; }
    function applyWall(p) {
        page.currentWall = p;
        wallApplyProc.command = ["ryoku-shell", "wallpaper", "set", p];
        wallApplyProc.running = true;
    }

    Process {
        id: wallListProc
        command: ["sh", "-c", "find \"$1\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -printf '%T@\\t%p\\n' | sort -rn", "_", page.wpDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n"), out = [];
                for (var i = 0; i < lines.length; i++) {
                    var tab = lines[i].indexOf("\t");
                    if (tab < 1)
                        continue;
                    var p = lines[i].substring(tab + 1);
                    out.push({ "path": p, "name": p.substring(p.lastIndexOf("/") + 1) });
                }
                page.wallpapers = out;
            }
        }
    }
    Process {
        id: wallStateProc
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "_", page.wpState]
        stdout: StdioCollector { onStreamFinished: page.currentWall = this.text.trim() }
    }
    Process { id: wallApplyProc; stdout: StdioCollector { onStreamFinished: wallStateProc.running = true } }

    // Theme palette mode: follow the wallpaper, or lock a curated light/dark, via
    // the hub's `hypr scheme` command (same backend as the theme colour source).
    property string scheme: "follow"
    function setScheme(k) {
        page.scheme = k;
        schemeApplyProc.command = ["ryoku-hub", "hypr", "scheme", k];
        schemeApplyProc.running = true;
    }
    Process {
        id: schemeQueryProc
        command: ["ryoku-hub", "hypr", "scheme"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { try { page.scheme = JSON.parse(this.text).scheme || "follow"; } catch (e) {} }
        }
    }
    Process { id: schemeApplyProc; stdout: StdioCollector { onStreamFinished: schemeQueryProc.running = true } }
    Process {
        id: wallNextProc
        command: ["ryoku-shell", "wallpaper", "next"]
        stdout: StdioCollector { onStreamFinished: wallStateProc.running = true }
    }

    // --- Comfort: backlight and night light, applied at once via the shipped tools. ---
    readonly property string scriptsDir: Quickshell.env("HOME") + "/.config/hypr/scripts/"
    property int brightness: -1
    property bool nightOn: false
    property int nightTemp: 4000
    property string comfortError: ""

    function refreshComfort() { brightGetProc.running = true; nightStatusProc.running = true; }
    function setBrightness(v) {
        page.brightness = v;
        brightSetProc.command = ["brightnessctl", "set", v + "%"];
        brightSetProc.running = true;
    }
    function setNight(on) {
        page.nightOn = on;
        nightProc.command = on ? [page.scriptsDir + "ryoku-cmd-nightlight", "on", String(page.nightTemp)]
                               : [page.scriptsDir + "ryoku-cmd-nightlight", "off"];
        nightProc.running = true;
    }
    function setNightTemp(t) { page.nightTemp = t; if (page.nightOn) nightDebounce.restart(); }

    Process {
        id: brightGetProc
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector {
            onStreamFinished: {
                var first = this.text.trim().split("\n")[0];
                var pct = parseInt((first.split(",")[3] || "").replace("%", ""), 10);
                if (!isNaN(pct))
                    page.brightness = pct;
            }
        }
    }
    Process {
        id: brightSetProc
        onExited: (code, status) => {
            page.comfortError = code === 0 ? "" : "Couldn't set brightness.";
            if (page.comfortError !== "")
                comfortErrorClear.restart();
        }
    }
    Process {
        id: nightStatusProc
        command: [page.scriptsDir + "ryoku-cmd-nightlight", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim().split(" ");
                page.nightOn = t[0] === "on";
                if (t.length > 1) {
                    var k = parseInt(t[1], 10);
                    if (!isNaN(k))
                        page.nightTemp = k;
                }
            }
        }
    }
    Process {
        id: nightProc
        onExited: (code, status) => {
            page.comfortError = code === 0 ? "" : "Couldn't change the night light.";
            if (page.comfortError !== "")
                comfortErrorClear.restart();
        }
    }
    Timer { id: nightDebounce; interval: 300; onTriggered: if (page.nightOn) page.setNight(true) }
    Timer { id: comfortErrorClear; interval: 6000; onTriggered: page.comfortError = "" }

    onGroupChanged: {
        if (page.group === "wallpaper")
            page.refreshWalls();
        else if (page.group === "comfort")
            page.refreshComfort();
        else if (page.group === "borders")
            schemeQueryProc.running = true;
    }
    Component.onCompleted: { page.refreshWalls(); page.refreshComfort(); }

    Segmented {
        id: tabs
        anchors.left: parent.left
        anchors.top: parent.top
        model: [
            { "key": "themes", "label": "Themes" },
            { "key": "look", "label": "Look" },
            { "key": "borders", "label": "Borders" },
            { "key": "cursor", "label": "Cursor" },
            { "key": "wallpaper", "label": "Wallpaper" },
            { "key": "comfort", "label": "Comfort" }
        ]
        current: page.group
        onSelected: (k) => page.group = k
    }

    Text {
        anchors.left: tabs.right
        anchors.leftMargin: 18
        anchors.verticalCenter: tabs.verticalCenter
        text: "Edits show on your desktop as you make them"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 12
        font.weight: Font.Medium
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: tabs.bottom
        anchors.topMargin: 26
        anchors.bottom: page.storeTab ? bar.top : parent.bottom
        anchors.bottomMargin: 18
        contentWidth: width
        contentHeight: Math.max(loader.height, height)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            id: sb
            policy: ScrollBar.AsNeeded
            width: 7
            contentItem: Rectangle {
                implicitWidth: 4
                radius: Theme.radius
                color: Theme.line
                opacity: sb.pressed ? 0.9 : (sb.hovered ? 0.7 : 0.4)
                Behavior on opacity { NumberAnimation { duration: Theme.quick } }
            }
        }

        Loader {
            id: loader
            width: flick.width - 12
            height: item ? item.implicitHeight : 0
            y: 0
            sourceComponent: page.group === "themes" ? themeComp
                : page.group === "look" ? lookComp
                : page.group === "borders" ? bordersComp
                : page.group === "cursor" ? cursorComp
                : page.group === "wallpaper" ? wallpaperComp
                : comfortComp
            onLoaded: {
                if (!item)
                    return;
                item.opacity = 0;
                fade.restart();
            }
        }

        NumberAnimation { id: fade; target: loader.item; property: "opacity"; to: 1; duration: Theme.medium; easing.type: Theme.ease }
    }

    Component {
        id: themeComp
        ThemesPage {}
    }

    Component {
        id: lookComp
        Row {
            id: lookRow
            spacing: 56
            readonly property real colW: (width - spacing) / 2

            Column {
                width: lookRow.colW
                spacing: 30

                SettingSection {
                    width: parent.width
                    title: "SHAPE"
                    NumberField {
                        width: parent.width; label: "Corner radius"; unit: "px"
                        from: 0; to: 30; value: store.rounding
                        onModified: (v) => store.edit("rounding", v)
                    }
                    SliderRow {
                        width: parent.width; label: "Corner softness"
                        from: 2; to: 8; step: 0.5; decimals: 1; value: store.roundingPower
                        onModified: (v) => store.edit("roundingPower", v)
                    }
                    NumberField {
                        width: parent.width; label: "Border thickness"; unit: "px"
                        from: 0; to: 12; value: store.borderSize
                        onModified: (v) => store.edit("borderSize", v)
                    }
                    ChoiceRow {
                        width: parent.width; label: "Tiling layout"
                        options: [{ "key": "dwindle", "label": "Dwindle" }, { "key": "master", "label": "Master" }, { "key": "scrolling", "label": "Scrolling" }]
                        current: store.layout
                        onChosen: (k) => store.edit("layout", k)
                    }
                    SliderRow {
                        width: parent.width; label: "Column width"; percent: true
                        from: 0.1; to: 1; step: 0.05
                        value: store.plugins.hyprscrolling.columnWidth
                        visible: store.layout === "scrolling"
                        onModified: (v) => store.editPlugin("hyprscrolling", "columnWidth", v)
                    }
                    ToggleRow {
                        width: parent.width; label: "Scroll to follow focus"
                        checked: store.plugins.hyprscrolling.followFocus
                        visible: store.layout === "scrolling"
                        onToggled: (v) => store.editPlugin("hyprscrolling", "followFocus", v)
                    }
                }

                SettingSection {
                    width: parent.width
                    title: "GAPS"
                    NumberField {
                        width: parent.width; label: "Inner (between windows)"; unit: "px"
                        from: 0; to: 40; value: store.gapsIn
                        onModified: (v) => store.edit("gapsIn", v)
                    }
                    NumberField {
                        width: parent.width; label: "Outer (screen edge)"; unit: "px"
                        from: 0; to: 60; value: store.gapsOut
                        onModified: (v) => store.edit("gapsOut", v)
                    }
                }

                SettingSection {
                    width: parent.width
                    title: "BEHAVIOUR"
                    ToggleRow {
                        width: parent.width; label: "Drag to resize at window edges"
                        checked: store.resizeOnBorder
                        onToggled: (v) => store.edit("resizeOnBorder", v)
                    }
                    ToggleRow {
                        width: parent.width; label: "Snap floating windows"
                        checked: store.snapEnabled
                        onToggled: (v) => store.edit("snapEnabled", v)
                    }
                }

                SettingSection {
                    width: parent.width
                    title: "TITLE BARS"
                    ToggleRow {
                        width: parent.width; label: "Window title bars"
                        checked: store.plugins.hyprbars.enabled
                        onToggled: (v) => store.editPlugin("hyprbars", "enabled", v)
                    }
                    NumberField {
                        width: parent.width; label: "Bar height"; unit: "px"
                        from: 12; to: 48; value: store.plugins.hyprbars.height
                        visible: store.plugins.hyprbars.enabled
                        onModified: (v) => store.editPlugin("hyprbars", "height", v)
                    }
                    NumberField {
                        width: parent.width; label: "Title text size"; unit: "px"
                        from: 8; to: 20; value: store.plugins.hyprbars.textSize
                        visible: store.plugins.hyprbars.enabled
                        onModified: (v) => store.editPlugin("hyprbars", "textSize", v)
                    }
                    ToggleRow {
                        width: parent.width; label: "Blur the bar"
                        checked: store.plugins.hyprbars.blur
                        visible: store.plugins.hyprbars.enabled
                        onToggled: (v) => store.editPlugin("hyprbars", "blur", v)
                    }
                    ToggleRow {
                        width: parent.width; label: "Close and maximise buttons"
                        checked: store.plugins.hyprbars.buttons
                        visible: store.plugins.hyprbars.enabled
                        onToggled: (v) => store.editPlugin("hyprbars", "buttons", v)
                    }
                    Text {
                        width: Math.min(parent.width, 620)
                        wrapMode: Text.WordWrap
                        text: "Adds a title bar with window buttons. Applies on Save."
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12
                        visible: store.plugins.hyprbars.enabled
                    }
                }
            }

            Column {
                width: lookRow.colW
                spacing: 30

                SettingSection {
                    width: parent.width
                    title: "OPACITY"
                    SliderRow {
                        width: parent.width; label: "Active"; percent: true
                        from: 0.4; to: 1; step: 0.01; value: store.activeOpacity
                        onModified: (v) => store.edit("activeOpacity", v)
                    }
                    SliderRow {
                        width: parent.width; label: "Inactive"; percent: true
                        from: 0.4; to: 1; step: 0.01; value: store.inactiveOpacity
                        onModified: (v) => store.edit("inactiveOpacity", v)
                    }
                    ToggleRow {
                        width: parent.width; label: "Dim inactive windows"
                        checked: store.dimInactive
                        onToggled: (v) => store.edit("dimInactive", v)
                    }
                    SliderRow {
                        width: parent.width; label: "Dim strength"; percent: true
                        from: 0; to: 1; step: 0.05; value: store.dimStrength
                        visible: store.dimInactive
                        onModified: (v) => store.edit("dimStrength", v)
                    }
                }

                SettingSection {
                    width: parent.width
                    title: "BLUR"
                    ToggleRow {
                        width: parent.width; label: "Enabled"
                        checked: store.blurEnabled
                        onToggled: (v) => store.edit("blurEnabled", v)
                    }
                    NumberField {
                        width: parent.width; label: "Size"; unit: "px"
                        from: 0; to: 20; value: store.blurSize
                        onModified: (v) => store.edit("blurSize", v)
                    }
                    NumberField {
                        width: parent.width; label: "Passes"
                        from: 1; to: 6; value: store.blurPasses
                        onModified: (v) => store.edit("blurPasses", v)
                    }
                    ToggleRow {
                        width: parent.width; label: "X-ray (blur shows the wallpaper)"
                        checked: store.blurXray
                        onToggled: (v) => store.edit("blurXray", v)
                    }
                    SliderRow {
                        width: parent.width; label: "Vibrancy"
                        from: 0; to: 0.5; step: 0.01; decimals: 2; value: store.blurVibrancy
                        onModified: (v) => store.edit("blurVibrancy", v)
                    }
                    SliderRow {
                        width: parent.width; label: "Noise"
                        from: 0; to: 0.1; step: 0.005; decimals: 3; value: store.blurNoise
                        onModified: (v) => store.edit("blurNoise", v)
                    }
                }

                SettingSection {
                    width: parent.width
                    title: "DEPTH & MOTION"
                    ToggleRow {
                        width: parent.width; label: "Window shadows"
                        checked: store.shadowEnabled
                        onToggled: (v) => store.edit("shadowEnabled", v)
                    }
                    NumberField {
                        width: parent.width; label: "Shadow range"; unit: "px"
                        from: 0; to: 60; value: store.shadowRange
                        onModified: (v) => store.edit("shadowRange", v)
                    }
                    NumberField {
                        width: parent.width; label: "Shadow sharpness"
                        from: 1; to: 4; value: store.shadowPower
                        onModified: (v) => store.edit("shadowPower", v)
                    }
                    ToggleRow {
                        width: parent.width; label: "Animations"
                        checked: store.animations
                        onToggled: (v) => store.edit("animations", v)
                    }
                    ToggleRow {
                        width: parent.width; label: "Wobbly windows"
                        checked: store.wobblyWindows
                        visible: store.animations
                        onToggled: (v) => store.edit("wobblyWindows", v)
                    }
                    ChoiceRow {
                        width: parent.width; label: "Open / close"
                        options: [{ "key": "pop", "label": "Pop" }, { "key": "slide", "label": "Slide" }, { "key": "gnomed", "label": "Gnome" }]
                        current: store.windowStyle
                        visible: store.animations
                        onChosen: (k) => store.edit("windowStyle", k)
                    }
                }

                SettingSection {
                    width: parent.width
                    title: "GLOW"
                    ToggleRow {
                        width: parent.width; label: "Glow behind windows"
                        checked: store.glowEnabled
                        onToggled: (v) => store.edit("glowEnabled", v)
                    }
                    NumberField {
                        width: parent.width; label: "Range"; unit: "px"
                        from: 4; to: 60; value: store.glowRange
                        visible: store.glowEnabled
                        onModified: (v) => store.edit("glowRange", v)
                    }
                    ColorField {
                        width: parent.width; label: "Colour"
                        value: store.glowColor
                        visible: store.glowEnabled
                        onModified: (v) => store.edit("glowColor", v)
                    }
                }

                SettingSection {
                    width: parent.width
                    title: "GLASS"
                    ToggleRow {
                        width: parent.width; label: "Liquid glass windows"
                        checked: store.plugins.hyprglass.enabled
                        onToggled: (v) => store.editPlugin("hyprglass", "enabled", v)
                    }
                    ChoiceRow {
                        width: parent.width; label: "Preset"
                        options: [{ "key": "clear", "label": "Clear" }, { "key": "subtle", "label": "Subtle" }, { "key": "high_contrast", "label": "Contrast" }, { "key": "glass", "label": "Glass" }]
                        current: store.plugins.hyprglass.preset
                        visible: store.plugins.hyprglass.enabled
                        onChosen: (k) => store.editPlugin("hyprglass", "preset", k)
                    }
                    SliderRow {
                        width: parent.width; label: "Blur strength"
                        from: 0; to: 5; step: 0.1; decimals: 1
                        value: store.plugins.hyprglass.blurStrength
                        visible: store.plugins.hyprglass.enabled
                        onModified: (v) => store.editPlugin("hyprglass", "blurStrength", v)
                    }
                    SliderRow {
                        width: parent.width; label: "Glass opacity"; percent: true
                        from: 0; to: 1; step: 0.05
                        value: store.plugins.hyprglass.opacity
                        visible: store.plugins.hyprglass.enabled
                        onModified: (v) => store.editPlugin("hyprglass", "opacity", v)
                    }
                    Text {
                        width: Math.min(parent.width, 620)
                        wrapMode: Text.WordWrap
                        text: "A liquid-glass blur and refraction on windows. Applies on Save."
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12
                        visible: store.plugins.hyprglass.enabled
                    }
                }
            }
        }
    }

    Component {
        id: bordersComp
        Column {
            spacing: 30

            Text {
                width: Math.min(parent.width, 620)
                wrapMode: Text.WordWrap
                text: page.scheme === "follow"
                    ? "Border colours follow the wallpaper palette. Turn off \u201cColours follow wallpaper\u201d in Themes to set fixed colours."
                    : "Borders use the fixed colours below."
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 12
            }

            SettingSection {
                width: parent.width
                visible: page.scheme !== "follow"
                title: "FIXED COLOURS"
                ColorField {
                    width: parent.width; label: "Active window"
                    value: store.activeBorder
                    onModified: (v) => store.edit("activeBorder", v)
                }
                ColorField {
                    width: parent.width; label: "Inactive window"
                    value: store.inactiveBorder
                    onModified: (v) => store.edit("inactiveBorder", v)
                }
            }

            SettingSection {
                width: parent.width
                title: "ANIMATED BORDER"
                ToggleRow {
                    width: parent.width; label: "Rotating gradient border"
                    checked: store.animatedBorder
                    onToggled: (v) => store.edit("animatedBorder", v)
                }
                SliderRow {
                    width: parent.width; label: "Rotation speed"
                    from: 1; to: 10; step: 1; decimals: 0; value: store.borderAngleSpeed
                    visible: store.animatedBorder
                    onModified: (v) => store.edit("borderAngleSpeed", v)
                }
                Text {
                    width: Math.min(parent.width, 620)
                    wrapMode: Text.WordWrap
                    text: "The active window's border sweeps a rotating gradient of your accent colours. Needs a border thickness above 0."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }

            SettingSection {
                width: parent.width
                title: "IMAGE BORDER"
                ToggleRow {
                    width: parent.width; label: "Image border around windows"
                    checked: store.plugins.imgborders.enabled
                    onToggled: (v) => store.editPlugin("imgborders", "enabled", v)
                }
                Row {
                    width: parent.width
                    spacing: 12
                    visible: store.plugins.imgborders.enabled
                    Text {
                        width: parent.width - chooseBtn.width - 12
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideMiddle
                        text: store.plugins.imgborders.image === "" ? "No image chosen" : store.plugins.imgborders.image
                        color: store.plugins.imgborders.image === "" ? Theme.faint : Theme.cream
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                    HubButton {
                        id: chooseBtn
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Choose image"
                        icon: "image"
                        onClicked: imgPicker.open()
                    }
                }
                SliderRow {
                    width: parent.width; label: "Border scale"
                    from: 0.5; to: 3; step: 0.1; decimals: 1
                    value: store.plugins.imgborders.scale
                    visible: store.plugins.imgborders.enabled
                    onModified: (v) => store.editPlugin("imgborders", "scale", v)
                }
                ToggleRow {
                    width: parent.width; label: "Smooth scaling"
                    checked: store.plugins.imgborders.smooth
                    visible: store.plugins.imgborders.enabled
                    onToggled: (v) => store.editPlugin("imgborders", "smooth", v)
                }
                Text {
                    width: Math.min(parent.width, 620)
                    wrapMode: Text.WordWrap
                    text: "Tiles an image around each window as its border. Pick an image, then Save."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                    visible: store.plugins.imgborders.enabled
                }
            }
        }
    }

    Component {
        id: cursorComp
        Column {
            spacing: 30

            SettingSection {
                width: parent.width
                title: "CURSOR"
                Dropdown {
                    width: Math.min(parent.width, 460); label: "Theme"
                    fieldWidth: 240
                    options: page.cursorThemes
                    current: store.cursorTheme
                    placeholder: store.cursorTheme
                    onChosen: (k) => store.edit("cursorTheme", k)
                }
                NumberField {
                    width: Math.min(parent.width, 460); label: "Size"; unit: "px"
                    from: 12; to: 64; step: 4; value: store.cursorSize
                    onModified: (v) => store.edit("cursorSize", v)
                }
                NumberField {
                    width: Math.min(parent.width, 460); label: "Hide after idle"; unit: "s"
                    from: 0; to: 30; value: store.cursorInactiveTimeout
                    onModified: (v) => store.edit("cursorInactiveTimeout", v)
                }
                Text {
                    width: Math.min(parent.width, 620)
                    wrapMode: Text.WordWrap
                    text: "0 seconds keeps the cursor always visible."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Hide while typing"
                    checked: store.cursorHideOnKeyPress
                    onToggled: (v) => store.edit("cursorHideOnKeyPress", v)
                }
                Text {
                    width: Math.min(parent.width, 620)
                    wrapMode: Text.WordWrap
                    text: "Themes are read from your installed icon sets. The change applies to the running session at once and to apps you open next."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }

            SettingSection {
                width: parent.width
                title: "MOTION"
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Realistic cursor motion"
                    checked: store.plugins.dynamicCursors.enabled
                    onToggled: (v) => store.editPlugin("dynamicCursors", "enabled", v)
                }
                ChoiceRow {
                    width: Math.min(parent.width, 460); label: "Style"
                    options: [{ "key": "rotate", "label": "Rotate" }, { "key": "tilt", "label": "Tilt" }, { "key": "stretch", "label": "Stretch" }]
                    current: store.plugins.dynamicCursors.mode
                    visible: store.plugins.dynamicCursors.enabled
                    onChosen: (k) => store.editPlugin("dynamicCursors", "mode", k)
                }
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Shake to find (magnify)"
                    checked: store.plugins.dynamicCursors.shake
                    visible: store.plugins.dynamicCursors.enabled
                    onToggled: (v) => store.editPlugin("dynamicCursors", "shake", v)
                }
                Text {
                    width: Math.min(parent.width, 620)
                    wrapMode: Text.WordWrap
                    text: "The cursor tilts, rotates, or stretches as it moves; shake it to briefly magnify and find it. Applies on Save."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                    visible: store.plugins.dynamicCursors.enabled
                }
            }
        }
    }

    Component {
        id: wallpaperComp
        Column {
            spacing: 22
            SettingSection {
                width: parent.width
                title: "THEME PALETTE"
                ChoiceRow {
                    width: Math.min(parent.width, 460)
                    label: "Colours"
                    options: [{ "key": "follow", "label": "Follow wallpaper" }, { "key": "light", "label": "Light" }, { "key": "dark", "label": "Dark" }]
                    current: page.scheme
                    onChosen: (k) => page.setScheme(k)
                }
                Text {
                    width: Math.min(parent.width, 620)
                    wrapMode: Text.WordWrap
                    text: page.scheme === "light" || page.scheme === "dark"
                        ? "A fixed " + page.scheme + " palette, kept across wallpaper changes."
                        : page.scheme === "custom"
                          ? "A theme owns the palette now. Pick Follow, Light, or Dark to change it."
                          : "Colours are derived from your wallpaper and update when it changes."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            SettingSection {
                width: parent.width
                title: "WALLPAPER"
                Row {
                    width: parent.width
                    spacing: 12
                    Text {
                        width: parent.width - shuffleBtn.width - 12
                        anchors.verticalCenter: parent.verticalCenter
                        wrapMode: Text.WordWrap
                        text: "Pick a wallpaper to retheme the desktop. The palette (borders, accents) follows it."
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    HubButton {
                        id: shuffleBtn
                        anchors.verticalCenter: parent.verticalCenter
                        label: "Shuffle"
                        icon: "refresh"
                        onClicked: wallNextProc.running = true
                    }
                }
                Flow {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: page.wallpapers
                        delegate: Rectangle {
                            id: wp
                            required property var modelData
                            readonly property bool active: page.currentWall === wp.modelData.path
                            width: 172
                            height: 104
                            radius: Theme.radius
                            color: Theme.surfaceLo
                            border.width: wp.active ? 2 : 1
                            border.color: wp.active ? Theme.ember : (wpHov.hovered ? Theme.cream : Theme.line)
                            clip: true
                            Behavior on border.color { ColorAnimation { duration: Theme.quick } }

                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: "file://" + wp.modelData.path
                                fillMode: Image.PreserveAspectCrop
                                sourceSize.width: 360
                                sourceSize.height: 220
                                asynchronous: true
                                cache: false
                            }

                            HoverHandler { id: wpHov; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: page.applyWall(wp.modelData.path) }
                            scale: wpHov.hovered ? 1.03 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.quick; easing.type: Theme.ease } }
                        }
                    }
                }
                Text {
                    visible: page.wallpapers.length === 0
                    text: "No wallpapers in ~/Pictures/Wallpapers."
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 13
                }
            }
        }
    }

    Component {
        id: comfortComp
        Column {
            spacing: 30
            SettingSection {
                width: parent.width
                title: "BACKLIGHT"
                SliderRow {
                    width: Math.min(parent.width, 460); label: "Brightness"; percent: true
                    from: 0.05; to: 1; step: 0.01
                    value: page.brightness < 0 ? 1 : page.brightness / 100
                    onModified: (v) => page.setBrightness(Math.round(v * 100))
                }
            }
            SettingSection {
                width: parent.width
                title: "NIGHT LIGHT"
                ToggleRow {
                    width: Math.min(parent.width, 460); label: "Warm the screen"
                    checked: page.nightOn
                    onToggled: (v) => page.setNight(v)
                }
                SliderRow {
                    width: Math.min(parent.width, 460); label: "Temperature"
                    from: 2500; to: 6500; step: 100; decimals: 0
                    value: page.nightTemp
                    onModified: (v) => page.setNightTemp(Math.round(v))
                }
                Text {
                    width: Math.min(parent.width, 620)
                    wrapMode: Text.WordWrap
                    text: "Lowers blue light for evening use. Stays on until you turn it off, across sessions."
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            Text {
                visible: page.comfortError !== ""
                width: Math.min(parent.width, 620)
                wrapMode: Text.WordWrap
                text: page.comfortError
                color: Theme.ember
                font.family: Theme.font
                font.pixelSize: 12
            }
        }
    }

    // --- action bar (mirrors Shell Settings) --------------------------------
    Rectangle {
        id: bar
        visible: page.storeTab
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        height: 60
        radius: Theme.radius
        color: store.dirty ? Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.08) : Theme.surfaceLo
        border.width: 1
        border.color: store.dirty ? Qt.rgba(Theme.ember.r, Theme.ember.g, Theme.ember.b, 0.4) : Theme.line
        Behavior on color { ColorAnimation { duration: Theme.medium } }
        Behavior on border.color { ColorAnimation { duration: Theme.medium } }

        Rectangle {
            id: statusDot
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            width: 9
            height: 9
            radius: 4.5
            color: store.dirty ? Theme.ember : Theme.ok
            Behavior on color { ColorAnimation { duration: Theme.quick } }
        }

        Text {
            anchors.left: statusDot.right
            anchors.leftMargin: 11
            anchors.verticalCenter: parent.verticalCenter
            text: store.dirty ? "Previewing unsaved changes" : "Saved \u00b7 live on your desktop"
            color: store.dirty ? Theme.bright : Theme.dim
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10

            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Reset to defaults"
                icon: "refresh"
                onClicked: store.resetAppearance()
            }
            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Revert"
                icon: "close"
                enabled: store.dirty
                onClicked: store.revert()
            }
            HubButton {
                anchors.verticalCenter: parent.verticalCenter
                label: "Save"
                icon: "check"
                primary: true
                enabled: store.dirty
                onClicked: store.save()
            }
        }
    }

    // image picker for the imgborders plugin (Borders tab). page-level so its
    // modal overlay covers the whole page, not just the borders column.
    ImagePicker {
        id: imgPicker
        onPicked: (p) => { store.editPlugin("imgborders", "image", p); imgPicker.active = false; }
        onCanceled: imgPicker.active = false
    }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// wallpaper bridge: warm in-memory snapshot of ~/Pictures/Wallpapers so the
// strip opens without shelling out. refresh = thumbnail script (generate
// missing 512px previews, prune ones whose source vanished), then re-list
// newest-first, then re-read the state file ryoku-shell wallpaper writes so
// `current` always names what's on screen. thumbs land before the list so
// strip delegates never bind to a not-yet-existing file. a refresh that
// arrives mid-pipeline sets `pending` and replays once state lands. apply
// goes through ryoku-shell wallpaper so the picker shares the transition,
// palette and state path with the random keybind.
//
// entries = { path, name, mtime, thumb }. path absolute, mtime epoch sec,
// thumb the cached preview png path.
Singleton {
    id: root

    property var entries: []
    readonly property int count: entries.length
    property string current: ""
    property bool pending: false

    readonly property string wpDir: Quickshell.env("HOME") + "/Pictures/Wallpapers"
    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/ryoku-wp-thumbs/"
    readonly property string thumbScript: Quickshell.env("HOME") + "/.config/hypr/scripts/wallpaper-thumbs.sh"
    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku-wallpaper"

    function refresh() {
        if (thumbProc.running || listProc.running || stateProc.running) {
            pending = true;
            return;
        }
        thumbProc.running = true;
    }

    // ryoku-shell wallpaper returns once the daemon has kicked off the
    // transition (~150ms; wave + palette + reload run in the background).
    // a pick landing while applyProc is still in flight would be dropped,
    // so the newest one queues and replays on exit -- rapid clicks converge
    // on the last pick.
    property string queuedApply: ""

    function apply(path) {
        if (applyProc.running) {
            queuedApply = path;
            return;
        }
        applyProc.command = ["ryoku-shell", "wallpaper", "set", path];
        applyProc.running = true;
    }

    function trash(path) {
        trashProc.command = ["gio", "trash", path];
        trashProc.running = true;
        var kept = [];
        for (var i = 0; i < entries.length; i++)
            if (entries[i].path !== path)
                kept.push(entries[i]);
        entries = kept;
    }

    Process {
        id: trashProc
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.refresh();
        }
    }

    Process {
        id: thumbProc
        command: ["sh", root.thumbScript]
        onExited: listProc.running = true
    }

    Process {
        id: listProc
        command: ["sh", "-c", "find \"$1\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) -printf '%T@\\t%p\\n' | sort -rn", "_", root.wpDir]
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.split("\n");
                var out = [];
                for (var i = 0; i < lines.length; i++) {
                    var tab = lines[i].indexOf("\t");
                    if (tab < 1)
                        continue;
                    var path = lines[i].substring(tab + 1);
                    var name = path.substring(path.lastIndexOf("/") + 1);
                    out.push({
                        path: path,
                        name: name,
                        mtime: parseFloat(lines[i].substring(0, tab)),
                        thumb: root.thumbDir + name + ".png"
                    });
                }
                root.entries = out;
                stateProc.running = true;
            }
        }
    }

    Process {
        id: stateProc
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null || true", "_", root.stateFile]
        stdout: StdioCollector {
            onStreamFinished: {
                root.current = this.text.trim();
                if (root.pending) {
                    root.pending = false;
                    Qt.callLater(root.refresh);
                }
            }
        }
    }

    Process {
        id: applyProc
        onExited: {
            if (root.queuedApply.length) {
                var next = root.queuedApply;
                root.queuedApply = "";
                applyProc.command = ["ryoku-shell", "wallpaper", "set", next];
                applyProc.running = true;
                return;
            }
            stateProc.running = true;
        }
    }

    Component.onCompleted: refresh()
}

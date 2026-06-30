pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The app's state: browse results, the preview palette, the apply pipeline and
// persisted settings, driven through the ryoku-wallhaven engine and ryoku-shell.
Singleton {
    id: root

    // ---- browse state -------------------------------------------------------
    property string query
    property string topRange            // "" (latest) | "1w" | "1M"
    property string ratios              // "" | "16x9" ... (Fit screen)
    property int page: 1
    property var results: []
    property bool searching
    property string error
    property string _searchErr

    // ---- selection + live preview palette -----------------------------------
    property var selected: null
    property var palette: []            // 16 wallust colours for the picked image
    property bool paletteLoading

    // ---- apply --------------------------------------------------------------
    property bool busy
    property string status
    property string _dlPath

    // ---- settings (persisted to ~/.config/ryoku/wallhaven.json) -------------
    readonly property string apiKey: cfg.apiKey || ""
    readonly property var keyPrefix: apiKey.length > 0 ? ["env", "WALLHAVEN_API_KEY=" + apiKey] : []

    function cmd(args) { return keyPrefix.concat(["ryoku-wallhaven"]).concat(args); }

    // safe palette read: index into the 16 colours with a fallback.
    function col(i, fallback) {
        return (palette && palette.length > i && palette[i]) ? palette[i] : (fallback || "#000000");
    }

    // ---- search -------------------------------------------------------------
    function search(q, p, range) {
        query = (q || "").trim();
        page = Math.max(1, p || 1);
        topRange = range || "";
        error = "";
        _searchErr = "";
        searching = true;
        var args = ["search", "--query", query, "--page", "" + page, "--json"];
        if (topRange.length > 0) args.push("--top-range", topRange);
        if (ratios.length > 0) args.push("--ratios", ratios);
        if (cfg.nsfw && apiKey.length > 0) args.push("--purity", "111");
        searchProc.running = false;
        searchProc.command = cmd(args);
        searchProc.running = true;
    }
    function searchLatest(q) { search(q, 1, ""); }
    function searchTop(range) { search(query, 1, range); }
    function nextPage() { if (!searching) search(query, page + 1, topRange); }
    function prevPage() { if (page > 1 && !searching) search(query, page - 1, topRange); }
    function setRatios(r) { ratios = r || ""; search(query, 1, topRange); }

    function _parseResults(text) {
        var rows = [];
        var lines = text.split("\n").filter(l => l.trim().length > 0);
        try {
            for (const l of lines)
                rows.push(JSON.parse(l));
            results = rows;
            error = "";
        } catch (e) {
            error = "Could not read results";
            results = [];
        }
        // keep a live preview: follow the search with the first result.
        if (results.length > 0)
            select(results[0]);
        else
            selected = null;
    }

    // ---- selection + palette ------------------------------------------------
    function select(item) {
        if (!item)
            return;
        selected = item;
        palette = [];
        paletteLoading = true;
        palProc.running = false;
        palProc.command = cmd(["palette", item.thumb]);
        palProc.running = true;
    }

    // ---- apply (download full res, then set + theme through the shell) -------
    function apply(item) {
        var it = item || selected;
        if (!it || busy)
            return;
        busy = true;
        status = "Downloading";
        _dlPath = "";
        dlProc.command = cmd(["download", it.id, it.path]);
        dlProc.running = true;
    }
    function download(item) {
        var it = item || selected;
        if (!it || busy)
            return;
        busy = true;
        status = "Downloading";
        _dlPath = "";
        _setAfter = false;
        dlProc.command = cmd(["download", it.id, it.path]);
        dlProc.running = true;
    }
    property bool _setAfter: true
    function openWeb(item) {
        var it = item || selected;
        if (it && it.wallhaven_url)
            Qt.openUrlExternally(it.wallhaven_url);
    }

    function saveSettings() { cfgFile.writeAdapter(); }

    // status lines clear themselves so the bar never carries a stale message.
    onStatusChanged: if (status.length > 0) statusClear.restart()
    Timer { id: statusClear; interval: 4000; onTriggered: root.status = "" }

    Process {
        id: searchProc
        stdout: StdioCollector { onStreamFinished: root._parseResults(text) }
        stderr: StdioCollector { onStreamFinished: root._searchErr = text }
        onExited: code => {
            root.searching = false;
            if (code !== 0) {
                root.error = root._searchErr.trim() || "Search failed";
                root.results = [];
            }
        }
    }

    Process {
        id: palProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.palette = text.trim().split("\n").filter(l => l.trim().length > 0);
                root.paletteLoading = false;
            }
        }
        onExited: code => { if (code !== 0) { root.palette = []; root.paletteLoading = false; } }
    }

    Process {
        id: dlProc
        stdout: StdioCollector { onStreamFinished: root._dlPath = (text.trim().split("\n").pop() || "") }
        onExited: code => {
            if (code === 0 && root._dlPath.length > 0 && root._setAfter) {
                root.status = "Setting wallpaper";
                setProc.command = ["ryoku-shell", "wallpaper", "set", root._dlPath];
                setProc.running = true;
            } else {
                root.busy = false;
                root.status = code === 0 ? "Saved to Pictures" : "Download failed";
                root._setAfter = true;
            }
        }
    }

    Process {
        id: setProc
        onExited: code => {
            root.busy = false;
            root.status = code === 0 ? "Wallpaper set" : "Could not set wallpaper";
        }
    }

    FileView {
        id: cfgFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/wallhaven.json"
        watchChanges: true
        printErrors: false
        onLoadFailed: cfgFile.writeAdapter()
        JsonAdapter {
            id: cfg
            property string apiKey: ""
            property bool nsfw: false
            property bool fitScreen: false
        }
    }
    readonly property var settings: cfg
}

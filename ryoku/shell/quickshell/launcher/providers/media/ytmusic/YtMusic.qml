import QtQuick
import Quickshell.Io
import "../../../Singletons"
import "ytmusic.js" as YtMusic
import "../.."

// YouTube Music search provider (`@` prefix): searches YouTube Music's keyless
// InnerTube API with curl and parses proper songs (clean title/artist/album +
// square album art inline), so results are song-grade and covers are free. A
// prefix cache makes refining a query feel instant; when InnerTube is
// unreachable it falls back to yt-dlp flat search so results never disappear.
// Playing a track hands off to the Radio engine (Singletons/Radio.qml), which
// streams it with mpv and auto-extends an endless YouTube Music radio; this
// provider owns no player. Routed by a dedicated prefix so a plain query never
// forks a search. Availability-gated on yt-dlp + mpv (needed for playback).
Provider {
    id: ytmusic

    providerId: "ytmusic"
    prefix: "@"
    defaultProvider: false

    property bool available: false
    property string pendingQuery: ""

    // Prefix-LRU cache: query -> rows. Keeps the last few resolved searches so
    // that refining ("daft" -> "daft punk") shows the widest cached prefix's rows
    // immediately while the network refine runs. Bounded so memory stays flat.
    property var cache: ({})
    property var cacheOrder: []
    readonly property int cacheMax: 16

    function cachePut(q, rows) {
        var c = ytmusic.cache;
        if (!c[q])
            ytmusic.cacheOrder.push(q);
        c[q] = rows;
        while (ytmusic.cacheOrder.length > ytmusic.cacheMax) {
            var evict = ytmusic.cacheOrder.shift();
            delete c[evict];
        }
        ytmusic.cache = c;
    }

    // Exact hit, else the longest cached query that is a prefix of `q` (its rows
    // are a good instant stand-in while the exact search resolves).
    function cacheLookup(q) {
        if (ytmusic.cache[q])
            return ytmusic.cache[q];
        var best = null, bestLen = -1;
        for (var i = 0; i < ytmusic.cacheOrder.length; i++) {
            var k = ytmusic.cacheOrder[i];
            if (q.indexOf(k) === 0 && k.length > bestLen) {
                best = ytmusic.cache[k];
                bestLen = k.length;
            }
        }
        return best;
    }

    function rowFor(track) {
        return {
            id: "ytm:" + track.id,
            title: track.title,
            subtitle: (track.artist ? track.artist : "YouTube Music")
                + (track.album ? "  \u00b7  " + track.album : "")
                + (track.durationLabel ? "  \u00b7  " + track.durationLabel : ""),
            icon: track.cover || "",
            type: "YT Music",
            score: 0,
            actions: [
                { name: "Play", icon: "", execute: function () { Radio.play(track); } },
                { name: "Open", icon: "", execute: function () { Qt.openUrlExternally("https://music.youtube.com/watch?v=" + track.id); } }
            ]
        };
    }

    function query(text) {
        if (!ytmusic.available)
            return [];
        var t = (text || "").trim();
        if (t.length < 2)
            return [];
        var cached = ytmusic.cacheLookup(t);
        if (ytmusic.cache[t])
            return cached.map(ytmusic.rowFor);   // exact hit: no refetch
        ytmusic.pendingQuery = t;
        debounce.restart();
        // prefix hit: show the widest cached prefix's rows while we refine.
        return cached ? cached.map(ytmusic.rowFor) : [];
    }

    Timer {
        id: debounce
        interval: 200
        repeat: false
        onTriggered: {
            searchProc.term = ytmusic.pendingQuery;
            Dispatcher.setBusy("ytmusic", true);
            searchProc.running = false;
            searchProc.running = true;
        }
    }

    Process {
        id: availProc
        command: ["sh", "-c", "command -v yt-dlp >/dev/null 2>&1 && command -v mpv >/dev/null 2>&1"]
        onExited: (code) => { ytmusic.available = (code === 0); }
    }

    // Primary search: InnerTube WEB_REMIX /search. One big JSON object, so it is
    // collected whole and parsed once. Empty results fall through to yt-dlp.
    Process {
        id: searchProc
        property string term: ""
        command: ["curl", "-s", "--max-time", "12",
            "https://music.youtube.com/youtubei/v1/search?prettyPrint=false",
            "-H", "Content-Type: application/json",
            "-H", "User-Agent: Mozilla/5.0",
            "--data-raw", YtMusic.innertubeBody(term)]
        stdout: StdioCollector {
            onStreamFinished: {
                var rows = YtMusic.parse(this.text);
                if (rows.length > 0) {
                    ytmusic.cachePut(searchProc.term, rows);
                    Dispatcher.setBusy("ytmusic", false);
                    Dispatcher.notifyAsync();
                } else {
                    // InnerTube empty/unreachable: try the yt-dlp fallback.
                    fallbackProc.term = searchProc.term;
                    fallbackProc.out = "";
                    fallbackProc.running = false;
                    fallbackProc.running = true;
                }
            }
        }
    }

    // Fallback: yt-dlp flat search (NDJSON), only when InnerTube yields nothing.
    Process {
        id: fallbackProc
        property string term: ""
        property string out: ""
        command: ["yt-dlp", "ytsearch12:" + term, "--flat-playlist", "-j", "--no-warnings"]
        stdout: SplitParser {
            onRead: line => fallbackProc.out += line + "\n"
        }
        onExited: {
            ytmusic.cachePut(fallbackProc.term, YtMusic.parseFlat(fallbackProc.out));
            Dispatcher.setBusy("ytmusic", false);
            Dispatcher.notifyAsync();
        }
    }

    Component.onCompleted: {
        availProc.running = true;
        Dispatcher.register(ytmusic);
    }
    Component.onDestruction: Radio.stop()
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Saved-playlist cache for RyoTunes. When a pasted YouTube playlist or mix link
// resolves, its full track list (ids, titles, artists, covers) is stored here so
// the user can replay the whole thing instantly later, with no /next round-trip.
// A small LRU keyed by playlistId, newest first, persisted as JSON under the
// cache dir. The launcher's SavedPlaylists strip reads `items` and calls back
// into the Radio engine's playCached with the stored tracks.
Singleton {
    id: root

    readonly property string file: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/ryoku/ryotunes-playlists.json"
    // [{ id, label, cover, count, tracks:[{id,title,artist,album,cover,durationLabel}], ts }]
    property var items: []
    readonly property int maxSaved: 12

    // A human label for a playlist: its first track's title, so the chip reads as
    // "what you were listening to" without a real playlist name (which /next omits).
    function labelFor(tracks) {
        if (!tracks || tracks.length === 0)
            return "Playlist";
        var t = tracks[0];
        return (t.title && t.title.length) ? t.title : "Playlist";
    }

    // Save (or refresh) a playlist to the front of the LRU. Re-saving an id moves
    // it up and refreshes its tracks; the list is capped so the cache stays small.
    function save(playlistId, tracks) {
        if (!playlistId || !tracks || tracks.length === 0)
            return;
        var entry = {
            id: playlistId,
            label: root.labelFor(tracks),
            cover: tracks[0].cover || "",
            count: tracks.length,
            tracks: tracks,
            ts: Date.now()
        };
        var next = [entry];
        for (var i = 0; i < root.items.length; i++) {
            if (root.items[i].id !== playlistId)
                next.push(root.items[i]);
        }
        if (next.length > root.maxSaved)
            next = next.slice(0, root.maxSaved);
        root.items = next;
        root.persist();
    }

    function remove(playlistId) {
        var next = [];
        for (var i = 0; i < root.items.length; i++) {
            if (root.items[i].id !== playlistId)
                next.push(root.items[i]);
        }
        root.items = next;
        root.persist();
    }

    // Look up a saved entry's tracks by id (for instant replay).
    function tracksFor(playlistId) {
        for (var i = 0; i < root.items.length; i++) {
            if (root.items[i].id === playlistId)
                return root.items[i].tracks;
        }
        return [];
    }

    function persist() { store.setText(JSON.stringify(root.items)); }

    FileView {
        id: store
        path: root.file
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    Component.onCompleted: {
        var raw = store.text();
        try {
            var parsed = raw && raw.length ? JSON.parse(raw) : [];
            root.items = Array.isArray(parsed) ? parsed : [];
        } catch (e) {
            root.items = [];
        }
    }
}

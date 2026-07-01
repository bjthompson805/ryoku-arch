// Parse YouTube Music's InnerTube radio continuation into a track queue. Playing
// a track POSTs to the keyless WEB_REMIX `/youtubei/v1/next` endpoint with the
// track's radio playlist (`RDAMVM<videoId>`); this parses the resulting
// `playlistPanelVideoRenderer` list into the same track shape ytmusic.js emits,
// so the launcher can append an endless auto-DJ queue to mpv. Pure so the parse
// is node-tested without the network. Consumed by YtMusic.qml.

var YtMusic = (typeof require !== "undefined") ? require("./ytmusic.js") : null;

// A track's radio playlist id: "RDAMVM" + the seed videoId. This is the
// auto-generated station YouTube Music plays after a song.
function radioPlaylistId(videoId) {
    return "RDAMVM" + String(videoId == null ? "" : videoId);
}

// Body for the continuation POST. isAudioOnly trims video-only entries; the
// playlistId seeds the station from the picked track.
function radioBody(videoId) {
    return JSON.stringify({
        context: { client: { clientName: "WEB_REMIX", clientVersion: "1.20240101.01.00", hl: "en", gl: "US" } },
        videoId: String(videoId == null ? "" : videoId),
        playlistId: radioPlaylistId(videoId),
        isAudioOnly: true
    });
}

// runsText/hiResCover/splitByline/clockToSec are shared with ytmusic.js; in QML
// both files are imported so the functions resolve, in node we require the sibling.
function runsText(runs) { return YtMusic ? YtMusic.runsText(runs) : ""; }
function hiResCover(u) { return YtMusic ? YtMusic.hiResCover(u) : u; }
function splitByline(t) { return YtMusic ? YtMusic.splitByline(t) : { artist: "", album: "", durationLabel: "" }; }
function clockToSec(l) { return YtMusic ? YtMusic.clockToSec(l) : 0; }

// Collect playlistPanelVideoRenderer entries in queue order.
function collectRenderers(obj) {
    var out = [];
    var stack = [obj];
    while (stack.length) {
        var o = stack.pop();
        if (!o || typeof o !== "object")
            continue;
        if (o.playlistPanelVideoRenderer)
            out.push(o.playlistPanelVideoRenderer);
        var keys = Object.keys(o);
        for (var i = keys.length - 1; i >= 0; i--) {
            var v = o[keys[i]];
            if (v && typeof v === "object")
                stack.push(v);
        }
    }
    return out;
}

// One radio renderer -> track, or null without a videoId. Duration is an explicit
// lengthText here; the byline carries artist/album (year sometimes trails, which
// splitByline leaves in album harmlessly). Radio art is served up to w544 already.
function trackFromRenderer(r) {
    var videoId = r.videoId || "";
    var title = runsText(r.title && r.title.runs);
    if (!videoId || !title)
        return null;
    var meta = splitByline(runsText(r.longBylineText && r.longBylineText.runs));
    var lengthLabel = runsText(r.lengthText && r.lengthText.runs);
    var thumbs = ((r.thumbnail || {}).thumbnails) || [];
    var cover = thumbs.length ? hiResCover(thumbs[thumbs.length - 1].url) : "";
    return {
        id: videoId,
        title: title,
        artist: meta.artist,
        album: meta.album,
        duration: clockToSec(lengthLabel),
        durationLabel: lengthLabel,
        cover: cover
    };
}

// Parse a `/next` response into a de-duplicated track queue. Malformed JSON or an
// empty panel resolves to []. The seed track is usually the first entry; callers
// that already play it can drop index 0.
function parseRadio(text) {
    var obj;
    try {
        obj = JSON.parse(String(text == null ? "" : text));
    } catch (e) {
        return [];
    }
    var renderers = collectRenderers(obj);
    var out = [];
    var seen = {};
    for (var i = 0; i < renderers.length; i++) {
        var t = trackFromRenderer(renderers[i]);
        if (t && !seen[t.id]) {
            seen[t.id] = 1;
            out.push(t);
        }
    }
    return out;
}

if (typeof module !== "undefined" && module.exports) {
    module.exports = { parseRadio, radioBody, radioPlaylistId };
}

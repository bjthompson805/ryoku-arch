import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { parseRadio, radioBody, radioPlaylistId } = require("./ytmusic.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}
function ok(cond, msg) { eq(!!cond, true, msg); }

// --- builders: assemble the InnerTube /next queue shape our parser walks. ---
const runs = (arr) => ({ runs: arr.map(t => ({ text: t })) });
function radioItem(title, byline, length, thumbs, videoId) {
    return { playlistPanelVideoRenderer: {
        title: runs([title]),
        longBylineText: runs(byline),
        lengthText: runs([length]),
        thumbnail: { thumbnails: thumbs.map(([url, width]) => ({ url, width })) },
        videoId
    } };
}
const radioResponse = (items) => JSON.stringify({ contents: { singleColumnMusicWatchNextResultsRenderer: { tabbedRenderer: { watchNextTabbedResultsRenderer: { tabs: [
    { tabRenderer: { content: { musicQueueRenderer: { content: { playlistPanelRenderer: { contents: items } } } } } }
] } } } } });

// playlist id + body
eq(radioPlaylistId("JhulBGMA7G4"), "RDAMVMJhulBGMA7G4", "radio playlist id is RDAMVM + videoId");
ok(radioBody("JhulBGMA7G4").indexOf("RDAMVMJhulBGMA7G4") !== -1, "body carries the radio playlist");
eq(JSON.parse(radioBody("vid")).isAudioOnly, true, "body requests audio-only");
eq(JSON.parse(radioBody("vid")).videoId, "vid", "body carries seed videoId");

// full radio parse against a faithful (minimized) /next fixture
const radioFixture = radioResponse([
    radioItem("Harder, Better, Faster, Stronger", ["Daft Punk", " \u2022 ", "Discovery", " \u2022 ", "2001"], "3:47",
        [["https://yt3.ggpht.com/aaa=w60-h60-l90-rj", 60], ["https://yt3.ggpht.com/aaa=w544-h544-l90-rj", 544]], "JhulBGMA7G4"),
    radioItem("Billie Jean", ["Michael Jackson", " \u2022 ", "Thriller", " \u2022 ", "1982"], "4:54",
        [["https://yt3.ggpht.com/bbb=w226-h226-l90-rj", 226]], "Zi_XLOBDo_Y"),
    radioItem("Feel Good Inc.", ["Gorillaz & De La Soul", " \u2022 ", "Demon Days", " \u2022 ", "2005"], "3:41",
        [["https://yt3.ggpht.com/ccc=w120-h120-l90-rj", 120]], "HyHNuVaZJ-k")
]);

const q = parseRadio(radioFixture);
eq(q.length, 3, "parses the full radio queue");
eq(q[0], { id: "JhulBGMA7G4", title: "Harder, Better, Faster, Stronger", artist: "Daft Punk", album: "Discovery", duration: 227, durationLabel: "3:47", cover: "https://yt3.ggpht.com/aaa=w544-h544-l90-rj" }, "seed track fully parsed");
eq(q[1].artist, "Michael Jackson", "second track artist");
eq(q[2].artist, "Gorillaz & De La Soul", "multi-artist survives");
eq(q[1].cover, "https://yt3.ggpht.com/bbb=w544-h544-l90-rj", "226 cover bumped to 544");
eq(q[2].cover, "https://yt3.ggpht.com/ccc=w544-h544-l90-rj", "120 cover bumped to 544");

// robustness
eq(parseRadio("not json"), [], "malformed JSON yields empty queue");
eq(parseRadio("{}"), [], "empty object yields empty queue");
const noVid = JSON.stringify({ c: [{ playlistPanelVideoRenderer: { title: runs(["x"]) } }] });
eq(parseRadio(noVid), [], "renderer without videoId dropped");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");

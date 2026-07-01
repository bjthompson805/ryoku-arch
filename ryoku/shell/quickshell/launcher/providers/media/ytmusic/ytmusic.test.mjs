import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { parse, parseFlat, hiResCover, clockToSec, fmtDuration, splitByline, innertubeBody, SONGS_PARAMS } = require("./ytmusic.js");

let failed = 0;
function eq(actual, expected, msg) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    if (a === e) console.log("PASS " + msg);
    else { failed++; console.log("FAIL " + msg + "\n  expected " + e + "\n  got      " + a); }
}
function ok(cond, msg) { eq(!!cond, true, msg); }

// --- builders: assemble the InnerTube search shape our parser walks, so the
// fixture reads as structure instead of a wall of nested braces. ---
const runs = (arr) => ({ text: { runs: arr.map(t => ({ text: t })) } });
const flexcol = (arr) => ({ musicResponsiveListItemFlexColumnRenderer: runs(arr) });
function searchItem(title, byline, thumbs, videoId, cols2) {
    const cols = [flexcol([title]), flexcol(byline)];
    if (cols2) cols.push(flexcol(cols2));
    return { musicResponsiveListItemRenderer: {
        flexColumns: cols,
        thumbnail: { musicThumbnailRenderer: { thumbnail: { thumbnails: thumbs.map(([url, width]) => ({ url, width })) } } },
        overlay: { musicItemThumbnailOverlayRenderer: { content: { musicPlayButtonRenderer: { playNavigationEndpoint: { watchEndpoint: { videoId } } } } } }
    } };
}
const searchResponse = (items) => JSON.stringify({ contents: { tabbedSearchResultsRenderer: { tabs: [
    { tabRenderer: { content: { sectionListRenderer: { contents: [{ musicShelfRenderer: { contents: items } }] } } } }
] } } });

// helpers
eq(hiResCover("https://x/abc=w120-h120-l90-rj"), "https://x/abc=w544-h544-l90-rj", "cover bumped to 544 square");
eq(hiResCover(""), "", "empty cover stays empty");
eq(hiResCover("https://x/no-token.jpg"), "https://x/no-token.jpg", "cover without size token is untouched");
eq(clockToSec("3:47"), 227, "m:ss to seconds");
eq(clockToSec("1:02:03"), 3723, "h:mm:ss to seconds");
eq(clockToSec(""), 0, "blank clock is zero");
eq(clockToSec("nope"), 0, "malformed clock is zero");
eq(fmtDuration(227), "3:47", "seconds to m:ss");
eq(fmtDuration(0), "", "zero duration blank");

// byline splitting
eq(splitByline("Daft Punk \u2022 Discovery \u2022 3:47"), { artist: "Daft Punk", album: "Discovery", durationLabel: "3:47" }, "artist/album/duration byline");
eq(splitByline("Song \u2022 Daft Punk \u2022 Discovery \u2022 3:47"), { artist: "Daft Punk", album: "Discovery", durationLabel: "3:47" }, "leading type word dropped");
eq(splitByline("Daft Punk, Pharrell Williams & Nile Rodgers \u2022 Random Access Memories \u2022 6:09"), { artist: "Daft Punk, Pharrell Williams & Nile Rodgers", album: "Random Access Memories", durationLabel: "6:09" }, "multi-artist kept whole");
eq(splitByline("Some Artist \u2022 2001"), { artist: "Some Artist", album: "2001", durationLabel: "" }, "year with no duration lands in album, not duration");

// request body
ok(innertubeBody("daft punk").indexOf("WEB_REMIX") !== -1, "body targets WEB_REMIX client");
ok(innertubeBody("daft punk").indexOf(SONGS_PARAMS) !== -1, "body carries songs filter");
eq(JSON.parse(innertubeBody("a & b")).query, "a & b", "query is JSON-escaped, not URL-mangled");

// full search parse against a faithful (minimized) InnerTube fixture
const searchFixture = searchResponse([
    searchItem("Harder, Better, Faster, Stronger", ["Daft Punk", " \u2022 ", "Discovery", " \u2022 ", "3:47"],
        [["https://yt3.ggpht.com/aaa=w60-h60-l90-rj", 60], ["https://yt3.ggpht.com/aaa=w120-h120-l90-rj", 120]], "JhulBGMA7G4", ["390M plays"]),
    searchItem("One More Time", ["Daft Punk", " \u2022 ", "Discovery", " \u2022 ", "5:20"],
        [["https://yt3.ggpht.com/bbb=w120-h120-l90-rj", 120]], "wU26xVT_vBU")
]);

const rows = parse(searchFixture);
eq(rows.length, 2, "parses both songs from the shelf");
eq(rows[0], { id: "JhulBGMA7G4", title: "Harder, Better, Faster, Stronger", artist: "Daft Punk", album: "Discovery", duration: 227, durationLabel: "3:47", cover: "https://yt3.ggpht.com/aaa=w544-h544-l90-rj" }, "first song fully parsed with hi-res cover");
eq(rows[1].id, "wU26xVT_vBU", "second song videoId");
eq(rows[1].cover, "https://yt3.ggpht.com/bbb=w544-h544-l90-rj", "second song cover bumped");
eq(rows[0].cover.indexOf("w120"), -1, "no w120 leaks through");

// order + de-dup + robustness
const dup = searchResponse([
    searchItem("A", ["X"], [], "same"),
    searchItem("A dup", ["Y"], [], "same")
]);
eq(parse(dup).length, 1, "duplicate videoId collapsed");
eq(parse("not json"), [], "malformed JSON yields no rows");
eq(parse("{}"), [], "empty object yields no rows");
// a renderer with no videoId (album/artist card) is dropped
const noVid = JSON.stringify({ a: { musicResponsiveListItemRenderer: { flexColumns: [flexcol(["Some Album"])] } } });
eq(parse(noVid), [], "renderer without videoId is dropped");

// fallback (yt-dlp NDJSON) still works and now carries a cover
const ndjson = [
    JSON.stringify({ id: "aaa", title: "Song A", uploader: "Artist A", duration: 200, thumbnails: [{ url: "https://i.ytimg.com/aaa/hq720.jpg" }] }),
    JSON.stringify({ id: "bbb", title: "Clip", uploader: "X", duration: 10 }),
    "not json",
    JSON.stringify({ title: "No ID", duration: 100 })
].join("\n");
eq(parseFlat(ndjson).length, 1, "flat fallback keeps the one valid song");
eq(parseFlat(ndjson)[0], { id: "aaa", title: "Song A", artist: "Artist A", album: "", duration: 200, durationLabel: "3:20", cover: "https://i.ytimg.com/aaa/hq720.jpg" }, "flat song carries thumbnail as cover");
eq(parseFlat(""), [], "empty flat text yields no tracks");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");

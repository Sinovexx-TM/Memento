// deno run --allow-read tools/manga_test.js
const src = Deno.readTextFileSync(new URL("../src/qml/util/Manga.js", import.meta.url))
    .replace(".pragma library", "");
const M = new Function(src + "; return { countChars, pageChars, hitTest, charRect, seriesTitle, volumeLabel, groupSeries, describe, addActive, formatMinutes, dwellNeededMs, rate };")();

let fails = 0;
function eq(a, b, what) {
    const ok = JSON.stringify(a) === JSON.stringify(b);
    if (!ok) { fails++; console.log("FAIL", what, "got", JSON.stringify(a), "want", JSON.stringify(b)); }
}

eq(M.countChars("「なんでだよ！」"), 5, "punctuation dropped");
eq(M.countChars("ちょっと…待って？"), 7, "ellipsis and ？");
eq(M.countChars("ラーメン"), 4, "ー counts");
eq(M.countChars("ABC 123"), 6, "letters/digits count");
eq(M.countChars("♡♪"), 0, "symbols dropped");

const vblock = { vertical: true, lines: ["あいう", "えお"],
    coords: [[[100, 0], [120, 0], [120, 30], [100, 30]], [[70, 0], [90, 0], [90, 20], [70, 20]]] };
eq(M.hitTest(vblock, 110, 15), { text: "あいうえお", index: 1 }, "vertical line 1 middle");
eq(M.hitTest(vblock, 80, 15), { text: "あいうえお", index: 4 }, "vertical line 2");
eq(M.hitTest(vblock, 95, 5), null, "between lines");
eq(M.charRect(vblock, 4), { x: 70, y: 10, w: 20, h: 10 }, "char rect");
const hblock = { vertical: false, lines: ["ABCD"], coords: [[[0, 0], [40, 0], [40, 10], [0, 10]]] };
eq(M.hitTest(hblock, 25, 5).index, 2, "horizontal");
eq(M.pageChars({ blocks: [vblock, hblock] }), 9, "page chars");

eq(M.seriesTitle("13DL.me-Fire_Punch_ vol 01-08"), "Fire Punch", "13DL");
eq(M.seriesTitle("[SoM] Dragon Ball Kanzenban v01-34, Neko Majin v01 (Raw Scans)"), "Dragon Ball Kanzenban", "SoM");
eq(M.seriesTitle("Kagurabachi"), "Kagurabachi", "plain");
eq(M.seriesTitle("ドラゴンボール超"), "ドラゴンボール超", "jp");
eq(M.volumeLabel("13DL.me-Fire_Punch_v03"), "Vol. 3", "v03");
eq(M.volumeLabel("13DL.me-Fire_Punch_v08e"), "Vol. 8", "v08e");
eq(M.volumeLabel("ドラゴンボール超 第05巻"), "Vol. 5", "第05巻");
eq(M.volumeLabel("[外薗健] カグラバチ 第09巻"), "Vol. 9", "kagura");
eq(M.volumeLabel("カグラバチ v08"), "Vol. 8", "kagura v08");
eq(M.volumeLabel("Neko Majin Kanzenban"), "Neko Majin Kanzenban", "no number");

eq(M.describe("{show} {volume}", "Fire Punch", "Vol. 1"), "Fire Punch Vol. 1", "describe");
eq(M.describe("Manga - {show} v{volume}", "X", ""), "Manga - X", "describe no volume");
eq(M.addActive(10, 100000, 99000, 1000, 300000), 11, "active");
eq(M.addActive(10, 1000000, 0, 1000, 300000), 10, "idle");
eq(M.formatMinutes(3900), "1 h 5 min", "minutes");

eq(M.dwellNeededMs(186), 22320, "dwell 186 chars");
eq(M.dwellNeededMs(0), 0, "dwell no text");
eq(M.rate(3862, 2817), (4935).toLocaleString(), "rate");
eq(M.rate(2711, 219), "", "rate too short");
eq(M.rate(0, 900), "", "rate no chars");
const g = M.groupSeries([
    { seriesPath: "a", series: "A_ vol 01-02", cover: "c1" },
    { seriesPath: "a", series: "A_ vol 01-02", cover: "c2" },
    { seriesPath: "b", series: "B", cover: "c3" }]);
eq(g.map(s => [s.title, s.volumes.length, s.cover]), [["A", 2, "c1"], ["B", 1, "c3"]], "group");

console.log(fails ? `${fails} failed` : "all passed");

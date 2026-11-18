// Run: deno run --allow-read tools/library_test.js [library folder]
const read = (p) => Deno.readTextFileSync(new URL(p, import.meta.url));
const SubMatch = new Function(read("../src/qml/util/SubMatch.js").replace(".pragma library", "") +
  "; return { parseEpisode, splitExt, cleanName };")();
const L = new Function("SubMatch", read("../src/qml/util/Library.js")
  .replace(".pragma library", "").replace(/^\.import.*$/m, "") +
  "; return { key, seriesTitle, buildSeries, nextEpisode, continueList, keysUpTo, formatTime, formatDate, extraLabel };")(SubMatch);

let fails = 0;
function eq(label, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want);
  if (g !== w) { fails++; console.log("FAIL", label, "\n  got ", g, "\n  want", w); }
}

eq("title vcb", L.seriesTitle("[VCB-Studio] Fullmetal Alchemist꞉ Brotherhood [Ma10p_1080p]"), "Fullmetal Alchemist꞉ Brotherhood");
eq("title moozzi", L.seriesTitle("[Moozzi2] Hirogaru Sky! Precure BD-BOX [ x265-10Bit Ver. ] - TV + SP"), "Hirogaru Sky! Precure");
eq("title nanako", L.seriesTitle("[NanakoRaws] Shin Samurai-den Yaiba (NTV 1920x1080 x265 AAC)"), "Shin Samurai-den Yaiba");
eq("title reinforce", L.seriesTitle("[ReinForce] Fate／Kaleid Liner Prisma Illya (BDRip 1920x1080 x264 FLAC)"), "Fate／Kaleid Liner Prisma Illya");
eq("extra drama", L.extraLabel("[VCB-Studio] Fullmetal Alchemist꞉ Brotherhood [Drama01][Ma10p_1080p][x265_flac]"), "Drama01");
eq("extra ncop", L.extraLabel("[Group] Show - NCOP1 [1080p]"), "NCOP1");
eq("extra fma ed", L.extraLabel("[VCB-Studio] Fullmetal Alchemist꞉ Brotherhood [ED_EP45(O.A. Ver.)][Ma10p_1080p][x265_flac]"), "ED EP45(O.A. Ver.)");
eq("extra ep", L.extraLabel("[ReinForce] Fate／Kaleid Liner Prisma Illya - ED ep.9 (BDRip 1920x1080 x264 FLAC)"), "ED ep.9");
eq("time", [L.formatTime(751), L.formatTime(3909)], ["12:31", "1:05:09"]);

// Next-episode logic
const F = (n, dir = "") => ({ rel: (dir ? dir + "/" : "") + `[G] Show - ${String(n).padStart(2, "0")} [1080p].mkv`, path: `C:/A/Show/${dir ? dir + "/" : ""}[G] Show - ${String(n).padStart(2, "0")} [1080p].mkv` });
const files = [3, 1, 2, 10, 4].map(n => F(n));
const k = (n) => L.key(F(n).path);
let s = L.buildSeries({ name: "[G] Show", path: "C:/A/Show" }, files, {});
eq("order", s.main.map(e => e.num), [1, 2, 3, 4, 10]);
eq("not started", [s.started, s.next.num], [false, 1]);
s = L.buildSeries({ name: "[G] Show", path: "C:/A/Show" }, files, { [k(1)]: { done: true, watchedDate: 10, date: 10 }, [k(2)]: { done: true, watchedDate: 20, date: 20 } });
eq("next after 2", [s.next.num, s.resume, s.watched], [3, false, 2]);
s = L.buildSeries({ name: "[G] Show", path: "C:/A/Show" }, files, { [k(2)]: { done: true, watchedDate: 20, date: 20 }, [k(3)]: { pos: 600, dur: 1400, date: 30 } });
eq("resume 3", [s.next.num, s.resume], [3, true]);
s = L.buildSeries({ name: "[G] Show", path: "C:/A/Show" }, files, { [k(4)]: { done: true, watchedDate: 50, date: 50 }, [k(1)]: { pos: 600, dur: 1400, date: 30 } });
eq("older half-watched ignored", [s.next.num, s.resume], [10, false]);
s = L.buildSeries({ name: "[G] Show", path: "C:/A/Show" }, files, Object.fromEntries([1,2,3,4,10].map(n => [k(n), { done: true, date: 1 }])));
eq("finished", [s.finished, s.next], [true, null]);
eq("keysUpTo", L.keysUpTo(s, s.main[2]).length, 3);
// Seasons + extras
const sf = [F(1, "S1"), F(2, "S1"), F(1, "S2"), { rel: "S1/Extra/[G] Show - NCOP1 [1080p].mkv", path: "C:/A/Show/S1/Extra/x.mkv" }, { rel: "[G] Show - SP01 [1080p].mkv", path: "C:/A/Show/sp.mkv" }];
s = L.buildSeries({ name: "[G] Show", path: "C:/A/Show" }, sf, {});
eq("sections", s.sections.map(x => x.title), ["Season 1", "Season 2", "Extras", "Season 1 · Extras"]);
eq("short", s.main.map(e => e.short), ["S1 E1", "S1 E2", "S2 E1"]);
eq("date", [L.formatDate(Date.parse("2026-11-17T12:00"), Date.parse("2026-11-18T09:00")), L.formatDate(Date.parse("2026-11-10T12:00"), Date.parse("2026-11-18T09:00"))], ["yesterday", "10 Nov"]);

// Real folders
const root = Deno.args[0];
if (root) {
  const VIDEO = /\.(mkv|mp4|avi|webm|m4v|mov)$/i;
  function walk(dir, rel = "", depth = 0, out = []) {
    for (const e of Deno.readDirSync(dir)) {
      const r = rel ? rel + "/" + e.name : e.name;
      if (e.isDirectory && depth < 3) walk(dir + "/" + e.name, r, depth + 1, out);
      else if (e.isFile && VIDEO.test(e.name)) out.push({ rel: r, path: dir + "/" + e.name });
    }
    return out;
  }
  for (const e of [...Deno.readDirSync(root)].filter(e => e.isDirectory).map(e => e.name).sort()) {
    const sr = L.buildSeries({ name: e, path: root + "/" + e }, walk(root + "/" + e), {});
    console.log(`\n== ${sr.title}   (${sr.total} episodes)`);
    for (const sec of sr.sections) {
      console.log(`  [${sec.title || "-"}] ${sec.episodes.map(x => x.short).join(", ")}`);
    }
  }
}
console.log(fails ? `\n${fails} FAILED` : "\nall tests passed");

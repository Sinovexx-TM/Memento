// Run: deno run --allow-read tools/library_test.js [library folder]
const read = (p) => Deno.readTextFileSync(new URL(p, import.meta.url));
const SubMatch = new Function(read("../src/qml/util/SubMatch.js").replace(".pragma library", "") +
  "; return { parseEpisode, splitExt, cleanName };")();
const L = new Function("SubMatch", read("../src/qml/util/Library.js")
  .replace(".pragma library", "").replace(/^\.import.*$/m, "") +
  "; return { key, seriesTitle, buildSeries, nextEpisode, continueList, keysUpTo, formatTime, formatDate, extraLabel, looseShowName, groupLoose };")(SubMatch);

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
eq("loose dbs", L.looseShowName("Dragon.Ball.Super.Beerus.S01E06.1080p.AMZN.WEB-DL.JPN.DDP2.0.H.264-ToonsHub.mkv"), "Dragon Ball Super Beerus");
eq("loose dash", L.looseShowName("[SubsPlease] Sousou no Frieren - 12 (1080p) [ABCD1234].mkv"), "Sousou no Frieren");
eq("loose bracket", L.looseShowName("[VCB-Studio] Show Name [03][Ma10p_1080p].mkv"), "Show Name");
eq("loose movie", L.looseShowName("Kimi no Na wa (2016) [1080p].mkv"), "Kimi no Na wa");
eq("loose dotted movie", L.looseShowName("Dragon.Ball.Super.Broly.2018.v3.BluRay.1080p.Dual-Audio.FLAC.5.1.Hi10P.x264-JySzE.mkv"), "Dragon Ball Super Broly");
eq("loose movie no year", L.looseShowName("Akira.1080p.BluRay.x264.mkv"), "Akira");
{
  const g = L.groupLoose("C:/A", [{ rel: "Dragon.Ball.Super.Beerus.S01E06.1080p.AMZN.WEB-DL.JPN.DDP2.0.H.264-ToonsHub.mkv", path: "C:/A/x6.mkv" }, { rel: "Dragon.Ball.Super.Beerus.S01E07.1080p.AMZN.WEB-DL.JPN.DDP2.0.H.264-ToonsHub.mkv", path: "C:/A/x7.mkv" }]);
  eq("loose group", g.length, 1);
  const s = L.buildSeries(g[0].folder, g[0].files, {});
  eq("loose series", [s.title, s.main.map(e => e.label)], ["Dragon Ball Super Beerus", ["Episode 6", "Episode 7"]]);
}
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
{
  // FMA-style: E1-2 watched then deleted, E3 on disk
  const h = { [k(1)]: { done: true, watchedDate: 10, date: 10 }, [k(2)]: { done: true, watchedDate: 20, date: 20 } };
  const s2 = L.buildSeries({ name: "[G] Show", path: "C:/A/Show" }, [F(3), F(4)], h);
  eq("ghost counts", [s2.watched, s2.total, s2.started, s2.next.num], [2, 4, true, 3]);
  eq("ghost hidden flag", s2.main.filter(e => e.ghost).map(e => e.num), [1, 2]);
  const g = L.groupLoose("C:/A", []);
  eq("loose all deleted -> no group", g.length, 0);
  const lg = L.groupLoose("C:/A", [{ rel: "Dragon.Ball.Super.Beerus.S01E07.mkv", path: "C:/A/Dragon.Ball.Super.Beerus.S01E07.mkv" }])[0];
  const ls = L.buildSeries(lg.folder, lg.files, { [L.key("C:/A/Dragon.Ball.Super.Beerus.S01E06.mkv")]: { done: true, date: 5 }, [L.key("C:/A/Other.Show.S01E01.mkv")]: { done: true, date: 5 } });
  eq("loose ghost", [ls.watched, ls.total, ls.next.num], [1, 2, 7]);
}
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
if (root) {
  const loose = [...Deno.readDirSync(root)].filter(e => e.isFile && /\.(mkv|mp4)$/i.test(e.name)).map(e => ({ rel: e.name, path: root + "/" + e.name }));
  for (const g of L.groupLoose(root, loose)) {
    const sr = L.buildSeries(g.folder, g.files, {});
    console.log(`
== (loose) ${sr.title}: ${sr.main.map(x => x.label).join(", ")}`);
  }
}
console.log(fails ? `\n${fails} FAILED` : "\nall tests passed");

// Run: deno run --allow-read tools/submatch_test.js [folder ...]
const src = Deno.readTextFileSync(new URL("../src/qml/util/SubMatch.js", import.meta.url))
  .replace(".pragma library", "");
const M = new Function(src + "; return { parseEpisode, matchFolder, subsForVideo, isVideo, isSub, langOf };")();

let fails = 0;
function eq(label, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want);
  if (g !== w) { fails++; console.log("FAIL", label, "\n  got ", g, "\n  want", w); }
}
const ep = (n) => { const e = M.parseEpisode(n); return e.kind === "episode" ? [e.season, e.ep] : e.kind; };

// Parsing
eq("vcb", ep("[VCB-Studio] Fullmetal Alchemist꞉ Brotherhood [03][Ma10p_1080p][x265_flac]"), [0, 3]);
eq("moozzi", ep("[Moozzi2] Hirogaru Sky! Precure - 13 (BD 1920x1080 x265-10Bit Flac)"), [0, 13]);
eq("end", ep("[NanakoRaws] Shin Samurai-den Yaiba - 24 END (NTV 1920x1080 x265 AAC)"), [0, 24]);
eq("sxxeyy", ep("[geckyzz] Click Me All Over - S01E05 [UNCENSORED, OVEIL.WEB-DL 720P AVC, AAC][C21A2B4F]"), [1, 5]);
eq("year", ep("Show (2019) - 05 [1080p]"), [0, 5]);
eq("year bare", ep("Show 2019 05"), [0, 5]);
eq("aac2.0", ep("Show - 07 [WEB 1080p H264 AAC2.0]"), [0, 7]);
eq("res", ep("Show 08 1920x1080 H264"), [0, 8]);
eq("ep word", ep("Show Episode 12"), [0, 12]);
eq("dai", ep("ショー 第5話"), [0, 5]);
eq("decimal", ep("Show - 12.5 [1080p]"), [0, 12.5]);
eq("v2", ep("[Group] Show - 05v2 [1080p]"), [0, 5]);
eq("ncop", ep("[Group] Show - NCOP1 [1080p]"), "extra");
eq("nced", ep("[Group] Show NCED 02"), "extra");
eq("ova", ep("Show OVA 01"), "extra");
eq("sp", ep("[Moozzi2] Hirogaru Sky! Precure - SP01 (BD)"), "extra");
eq("menu", ep("[VCB-Studio] Show [Menu01][Ma10p_1080p]"), "extra");
eq("preview", ep("Show - Preview 03"), "extra");
eq("brackets num", ep("Show [36]"), [0, 36]);
eq("lang", M.langOf("Show - 05.ja"), { lang: "ja", stem: "Show - 05" });
eq("lang eng", M.langOf("Show - 05.eng"), { lang: "en", stem: "Show - 05" });
eq("lang bracket", M.langOf("Show - 05 [JP]"), { lang: "ja", stem: "Show - 05" });

const names = (r) => r.renames.map(x => `${x.sub.name} -> ${x.newName}`).sort();
const S = (name, lang = "", dir = "") => ({ name, dir, lang });

// FMA: videos S02E01-12, subs 27-38
{
  const v = Array.from({ length: 12 }, (_, i) => `FMA S02E${String(i + 1).padStart(2, "0")}.mkv`);
  const s = Array.from({ length: 12 }, (_, i) => S(`FMA ${27 + i}.srt`, "ja"));
  const r = M.matchFolder(v, s);
  eq("fma count", r.renames.length, 12);
  eq("fma first", r.renames.find(x => x.sub.name === "FMA 27.srt").newName, "FMA S02E01.srt");
  eq("fma last", r.renames.find(x => x.sub.name === "FMA 38.srt").newName, "FMA S02E12.srt");
}
// Offset, both absolute: videos 1-12, subs 27-38
{
  const v = Array.from({ length: 12 }, (_, i) => `Show - ${String(i + 1).padStart(2, "0")}.mkv`);
  const s = Array.from({ length: 12 }, (_, i) => S(`Sub ${27 + i}.srt`));
  const r = M.matchFolder(v, s);
  eq("offset", r.renames.find(x => x.sub.name === "Sub 27.srt").newName, "Show - 01.srt");
}
// Full pack 1-64, videos S02E01-03 only: must NOT pair S02E03 with 03 -> unclear
{
  const v = ["X S02E01.mkv", "X S02E02.mkv", "X S02E03.mkv"];
  const s = Array.from({ length: 64 }, (_, i) => S(`X - ${i + 1}.ass`));
  const r = M.matchFolder(v, s);
  eq("pack partial no guess", r.renames.length, 0);
  eq("pack partial unclear", r.unclear.length, 3);
}
// Full pack with videos S01E01..S02E02 continuous -> positions
{
  const v = [...Array.from({ length: 26 }, (_, i) => `X S01E${String(i + 1).padStart(2, "0")}.mkv`), "X S02E01.mkv", "X S02E02.mkv"];
  const s = Array.from({ length: 64 }, (_, i) => S(`X - ${i + 1}.ass`));
  const r = M.matchFolder(v, s);
  eq("pack from start", r.renames.find(x => x.video === "X S02E02.mkv")?.sub.name, "X - 28.ass");
}
// Full pack, absolute both, some videos: direct
{
  const v = ["[VCB] FMA [03][1080p].mkv", "[VCB] FMA [04][1080p].mkv"];
  const s = Array.from({ length: 64 }, (_, i) => S(`[VCB] FMA [${String(i + 1).padStart(2, "0")}][1080p].srt`));
  const r = M.matchFolder(v, s);
  eq("pack direct", r.renames.length, 0);
  eq("pack direct matched", r.matched.length, 2);
}
// Two languages
{
  const v = ["Show - 01.mkv", "Show - 02.mkv"];
  const s = [S("Show 01.ja.srt"), S("Show 01.en.srt"), S("Show 02.ja.srt"), S("Show 02.en.srt")];
  const r = M.matchFolder(v, s);
  eq("langs", names(r), ["Show 01.en.srt -> Show - 01.en.srt", "Show 01.ja.srt -> Show - 01.ja.srt", "Show 02.en.srt -> Show - 02.en.srt", "Show 02.ja.srt -> Show - 02.ja.srt"]);
  eq("ja first", M.subsForVideo("Show - 01.mkv", r).subs[0].name, "Show 01.ja.srt");
}
// Already matched ja + extra NCOP sub + decimal
{
  const v = ["Show - 01.mkv", "Show - 12.mkv", "Show - 12.5.mkv"];
  const s = [S("Show - 01.ja.srt"), S("Show NCOP.srt"), S("Sub 12.srt"), S("Sub 12.5.srt")];
  const r = M.matchFolder(v, s);
  eq("already", r.matched.map(m => m.sub.name), ["Show - 01.ja.srt"]);
  eq("ncop unmatched", r.unmatched.map(x => x.name).includes("Show NCOP.srt"), true);
  eq("decimal", names(r), ["Sub 12.5.srt -> Show - 12.5.srt", "Sub 12.srt -> Show - 12.srt"]);
}

console.log(fails ? `${fails} failed` : "all synthetic tests passed");

// Real folders
for (const dir of Deno.args) {
  const files = [...Deno.readDirSync(dir)].filter(e => e.isFile).map(e => e.name);
  const v = files.filter(M.isVideo), s = files.filter(M.isSub).map(n => S(n));
  const r = M.matchFolder(v, s);
  console.log(`\n== ${dir.split(/[\/]/).pop()}: ${v.length} videos, ${s.length} subs`);
  console.log(`matched ${r.matched.length}, renames ${r.renames.length}, unclear ${r.unclear.length}, unmatched ${r.unmatched.length}`);
  r.renames.slice(0, 4).forEach(x => console.log("  ", x.sub.name, "->", x.newName));
  r.unmatched.slice(0, 4).forEach(x => console.log("   unmatched:", x.name));
  r.unclear.slice(0, 2).forEach(x => console.log("   unclear:", x.video, x.candidates.length));
}

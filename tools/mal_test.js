// Run: deno run --allow-read tools/mal_test.js
const read = (p) => Deno.readTextFileSync(new URL(p, import.meta.url));
const SubMatch = new Function(read("../src/qml/util/SubMatch.js").replace(".pragma library", "") +
  "; return { parseEpisode, splitExt, cleanName };")();
const M = new Function("SubMatch", read("../src/qml/util/Mal.js")
  .replace(".pragma library", "").replace(/^\.import.*$/m, "") +
  "; return { norm, seasonOf, episodeOf, matchKey, similarity, titleSeason, autoMatch, planUpdate, manualCount, today };")(SubMatch);

let fails = 0;
function eq(label, got, want) {
  const g = JSON.stringify(got), w = JSON.stringify(want);
  if (g !== w) { fails++; console.log("FAIL", label, "\n  got ", g, "\n  want", w); }
}

eq("season sxxexx", M.seasonOf("C:/A/Dragon.Ball.Super.Beerus.S01E06.mkv"), 1);
eq("season folder", M.seasonOf("C:/A/Prisma (BD)/S2/[R] Prisma - 05 (BD).mkv"), 2);
eq("season none", M.seasonOf("C:/A/[G] Show - 05.mkv"), 1);
eq("ep", M.episodeOf("C:/A/[NanakoRaws] Shin Samurai-den Yaiba - 14 (NTV 1920x1080 x265 AAC).mkv"), 14);
eq("ep vcb", M.episodeOf("C:/A/[VCB-Studio] Fullmetal Alchemist꞉ Brotherhood [03][Ma10p_1080p][x265_flac].mkv"), 3);
eq("ep extra", M.episodeOf("C:/A/[G] Show - NCOP1 [1080p].mkv"), null);
eq("ep extra dir", M.episodeOf("C:/A/S1/Extra/Special/[R] Prisma - SP1 (BD).mkv"), null);
eq("ep decimal", M.episodeOf("C:/A/Show - 12.5.mkv"), null);
eq("title season", [M.titleSeason("Fate/kaleid liner Prisma☆Illya 2wei!"), M.titleSeason("Shingeki no Kyojin Season 2"), M.titleSeason("Overlord II"), M.titleSeason("Mob Psycho 100 III")], [0, 2, 2, 3]);

const list = [
  { id: 1, title: "Fullmetal Alchemist: Brotherhood", en: "Fullmetal Alchemist: Brotherhood", synonyms: ["Hagane no Renkinjutsushi: Fullmetal Alchemist"], status: "watching", watched: 2, episodes: 64 },
  { id: 2, title: "Fullmetal Alchemist", en: "Fullmetal Alchemist", synonyms: [], status: "completed", watched: 51, episodes: 51 },
  { id: 3, title: "Hirogaru Sky! Precure", en: "Soaring Sky! Pretty Cure", status: "watching", watched: 35, episodes: 50 },
  { id: 4, title: "Shin Samurai-den Yaiba", en: "Yaiba: Samurai Legend", status: "watching", watched: 13, episodes: 0 },
  { id: 5, title: "Fate/kaleid liner Prisma☆Illya", status: "completed", watched: 10, episodes: 10 },
  { id: 6, title: "Fate/kaleid liner Prisma☆Illya 2wei!", status: "watching", watched: 4, episodes: 10 },
  { id: 7, title: "Shingeki no Kyojin", en: "Attack on Titan", status: "completed", watched: 25, episodes: 25 },
  { id: 8, title: "Shingeki no Kyojin Season 2", en: "Attack on Titan Season 2", status: "watching", watched: 3, episodes: 12 },
  { id: 9, title: "Dragon Ball Super: Broly", status: "plan_to_watch", watched: 0, episodes: 1 },
];
const id = (x) => x ? x.id : null;
eq("fma", id(M.autoMatch("Fullmetal Alchemist꞉ Brotherhood", 1, list)), 1);
eq("precure", id(M.autoMatch("Hirogaru Sky! Precure", 1, list)), 3);
eq("yaiba", id(M.autoMatch("Shin Samurai-den Yaiba", 1, list)), 4);
eq("prisma s1", id(M.autoMatch("Fate／Kaleid Liner Prisma Illya", 1, list)), 5);
eq("prisma s2 unsure (2wei)", id(M.autoMatch("Fate／Kaleid Liner Prisma Illya", 2, list)), null);
eq("aot s1", id(M.autoMatch("Shingeki no Kyojin", 1, list)), 7);
eq("aot s2", id(M.autoMatch("Shingeki no Kyojin", 2, list)), 8);
eq("dbs beerus not broly", id(M.autoMatch("Dragon Ball Super Beerus", 1, list)), null);
eq("unknown", id(M.autoMatch("Sousou no Frieren", 1, list)), null);

const T = "2026-11-18";
eq("forward", M.planUpdate(list[3], 14, T), { change: true, fields: { num_watched_episodes: 14, status: "watching" }, from: 13, to: 14, status: "watching", statusChanged: false });
eq("behind", M.planUpdate(list[3], 12, T).change, false);
eq("complete", M.planUpdate(list[2], 50, T).fields, { num_watched_episodes: 50, status: "completed", finish_date: T });
eq("past total", M.planUpdate(list[2], 51, T).change, false);
eq("new entry", M.planUpdate({ id: 10, title: "X", status: "", watched: 0, episodes: 12 }, 1, T).fields, { num_watched_episodes: 1, status: "watching", start_date: T });
eq("completed rewatch keeps status", M.planUpdate({ status: "completed", watched: 5, episodes: 0 }, 6, T).fields, { num_watched_episodes: 6 });
eq("manual +1 to end", M.manualCount(list[2], 50, T), { num_watched_episodes: 50, status: "completed", finish_date: T });
eq("manual start", M.manualCount(list[8], 1, T), { num_watched_episodes: 1, status: "completed", finish_date: T });
eq("today", M.today(Date.parse("2026-11-18T09:00")), "2026-11-18");

console.log(fails ? `\n${fails} FAILED` : "all tests passed");

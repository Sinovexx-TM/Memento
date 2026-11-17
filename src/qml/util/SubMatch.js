.pragma library

/*
 * Subtitle <-> video matching by episode number (port of match-subs.ps1 with
 * fixes). Pure functions, no Qt: tested with Deno (tools/submatch_test.js).
 */

var VIDEO_EXT = [".mkv", ".mp4", ".avi", ".webm", ".m4v", ".mov"];
var SUB_EXT = [".srt", ".ass", ".ssa", ".vtt"];

var LANGS = {
    ja: "ja", jp: "ja", jpn: "ja", japanese: "ja", "ja-jp": "ja", jap: "ja",
    en: "en", eng: "en", english: "en", "en-us": "en", "en-gb": "en"
};

function splitExt(name) {
    var dot = name.lastIndexOf(".");
    if (dot <= 0) {
        return { base: name, ext: "" };
    }
    return { base: name.substring(0, dot), ext: name.substring(dot).toLowerCase() };
}

function isVideo(name) { return VIDEO_EXT.indexOf(splitExt(name).ext) >= 0; }
function isSub(name) { return SUB_EXT.indexOf(splitExt(name).ext) >= 0; }

/* Language tag at the end of a subtitle name ("x.ja", "x.eng", "x [JP]") */
function langOf(base) {
    var m = base.match(/\.([A-Za-z]{2,8}(?:-[A-Za-z]{2})?)$/);
    if (m && LANGS[m[1].toLowerCase()]) {
        return { lang: LANGS[m[1].toLowerCase()], stem: base.substring(0, base.length - m[0].length) };
    }
    m = base.match(/[\[(]\s*(ja|jp|jpn|japanese|en|eng|english)\s*[\])]\s*$/i);
    if (m) {
        return { lang: LANGS[m[1].toLowerCase()], stem: base.substring(0, m.index).trim() };
    }
    return { lang: "", stem: base };
}

var EXTRA_RE = /(?:^|[^A-Za-z])(NCOP|NCED|OP|ED|SP|OVA|OAD|ONA|PV|CM|Menu|Preview|Trailer|Teaser|Special|Specials|Bonus|Extra|Extras)(?:\s*\d{0,3})(?=$|[^A-Za-z])/i;

function cleanName(s) {
    s = s.replace(/\[[0-9A-Fa-f]{8}\]/g, " ");                          /* CRC */
    s = s.replace(/\[(?!\s*\d{1,4}(?:\.\d)?(?:v\d)?\s*\])[^\]]*\]/g, " "); /* [tags], keep [36] */
    s = s.replace(/\((?!\s*\d{1,4}(?:\.\d)?(?:v\d)?\s*\))[^)]*\)/g, " "); /* (tags), keep (36) */
    s = s.replace(/[\[(]\s*(?:19[5-9]\d|20[0-4]\d)\s*[\])]/g, " ");       /* (2019) */
    s = s.replace(/\b\d{3,4}\s*x\s*\d{3,4}\b/gi, " ");                     /* 1920x1080 */
    s = s.replace(/\b\d{3,4}[pi]\b/gi, " ");                               /* 1080p */
    s = s.replace(/\b(?:[xh]\.?26[45]|hevc|avc|av1|vp9|xvid|divx)\b/gi, " ");
    s = s.replace(/\b(?:aac|flac|ac-?3|e-?ac-?3|ddp?|dts|opus|mp3|truehd|pcm)\s*\d?(?:\.\d)?\b/gi, " ");
    s = s.replace(/\b\d{1,2}\s*-?\s*bits?\b/gi, " ");                     /* 10bit */
    s = s.replace(/\b(?:ma|hi)10p?\b/gi, " ");
    s = s.replace(/\b[257]\.[01]\b/g, " ");                               /* 5.1, 2.0 */
    s = s.replace(/\b(?:19[5-9]\d|20[0-4]\d)\b/g, " ");                   /* bare years */
    s = s.replace(/[_]+/g, " ");
    return s;
}

/*
 * Episode info from a file name (without extension).
 * kind: "episode" | "extra" | "none"; season: number or 0; ep: number
 */
function parseEpisode(base) {
    var m = base.match(/S(\d{1,2})[ ._-]?E(\d{1,4}(?:\.\d)?)(?!\d)/i);
    if (m) {
        return { kind: "episode", season: parseInt(m[1], 10), ep: parseFloat(m[2]) };
    }
    var clean = cleanName(base);
    /* Extras can also sit in a tag ("[Menu01]"); the leading [Group] is skipped */
    if (EXTRA_RE.test(clean) || EXTRA_RE.test(base.replace(/^\s*\[[^\]]*\]/, " "))) {
        return { kind: "extra", season: 0, ep: 0 };
    }
    var patterns = [
        /\[\s*(\d{1,4}(?:\.\d)?)(?:v\d)?\s*\]/,
        /(?:\bep?|\bepisode|第)\s*\.?\s*(\d{1,4}(?:\.\d)?)/i,
        /\s-\s*(\d{1,4}(?:\.\d)?)(?:v\d)?\b/,
        /(\d{1,4}(?:\.\d)?)(?:v\d)?(?!.*\d)/
    ];
    for (var i = 0; i < patterns.length; ++i) {
        m = clean.match(patterns[i]);
        if (m) {
            return { kind: "episode", season: 0, ep: parseFloat(m[1]) };
        }
    }
    return { kind: "none", season: 0, ep: 0 };
}

function isWhole(n) { return Math.floor(n) === n; }

function sortKey(item) { return item.season * 100000 + item.ep; }

function consecutive(items) {
    for (var i = 1; i < items.length; ++i) {
        var a = items[i - 1], b = items[i];
        var next = (a.season === b.season && b.ep === a.ep + 1) ||
                   (b.season === a.season + 1 && b.ep === 1);
        if (!next) {
            return false;
        }
    }
    return true;
}

/*
 * Match one language group of subtitles to the videos.
 * Returns { pairs: [[video, sub]], unclear: [video] }
 */
function matchGroup(videos, subs) {
    var result = { pairs: [], unclear: [] };
    if (videos.length === 0 || subs.length === 0) {
        return result;
    }

    var vSeason = videos.every(function (v) { return v.season > 0; });
    var sSeason = subs.every(function (s) { return s.season > 0; });
    var vAbs = videos.every(function (v) { return v.season === 0; });
    var sAbs = subs.every(function (s) { return s.season === 0; });
    var sameScheme = (vSeason && sSeason) || (vAbs && sAbs);

    function sameEp(v, s) { return v.season === s.season && v.ep === s.ep; }

    /* Several subs for one episode in one language: the user picks */
    function addPair(v, list) {
        if (list.length === 1) {
            result.pairs.push([v, list[0]]);
        } else if (list.length > 1) {
            result.unclear.push({ video: v, candidates: list });
        }
    }

    if (sameScheme) {
        var hits = 0;
        var direct = videos.map(function (v) {
            var list = subs.filter(function (s) { return sameEp(v, s); });
            if (list.length > 0) { ++hits; }
            return list;
        });
        var wholeSubs = subs.filter(function (s) { return isWhole(s.ep); }).length;
        /* Numbers line up: every video that could have a sub found one */
        if (hits > 0 && hits >= Math.min(videos.length, wholeSubs)) {
            videos.forEach(function (v, i) { addPair(v, direct[i]); });
            return result;
        }
    }

    /* Numbers don't line up (different schemes or an offset). Decimal
     * episodes only ever match the same number, never by order. */
    var vw = videos.filter(function (v) { return isWhole(v.ep); }).sort(function (a, b) { return sortKey(a) - sortKey(b); });
    var sw = subs.filter(function (s) { return isWhole(s.ep); }).sort(function (a, b) { return sortKey(a) - sortKey(b); });
    videos.filter(function (v) { return !isWhole(v.ep); }).forEach(function (v) {
        addPair(v, subs.filter(function (s) { return s.ep === v.ep && (v.season === s.season || !sameScheme); }));
    });

    if (vw.length === 0 || sw.length === 0) {
        return result;
    }

    /* Same count: pair in sorted order (S02E01-12 <-> 27-38) */
    if (vw.length === sw.length) {
        vw.forEach(function (v, i) { result.pairs.push([v, sw[i]]); });
        return result;
    }

    /* Videos from the very first episode on, no gaps: their position is the
     * absolute number (S01E01..S02E12 with a 1-64 sub pack) */
    var first = vw[0];
    if (consecutive(vw) && first.ep === 1 && (first.season <= 1) &&
            sw.every(function (s) { return s.season === 0; })) {
        vw.forEach(function (v, i) {
            addPair(v, sw.filter(function (s) { return s.ep === i + 1; }));
        });
        return result;
    }

    /* Anything else would be a guess */
    vw.forEach(function (v) { result.unclear.push({ video: v, candidates: sw.slice() }); });
    return result;
}

/*
 * videoNames: file names of the videos in the folder.
 * subs: [{ name, dir, lang }] where lang is "ja"/"en"/... from the name or the
 *       caller's look at the text ("" = unknown). dir = "" or "subs".
 * Returns {
 *   matched: [{ video, sub }]            already named for their video
 *   renames: [{ video, sub, newName }]   proposed renames (newName in the video's folder)
 *   unclear: [{ video, candidates }]     the user has to pick
 *   unmatched: [sub]
 * }  (video = file name, sub = { name, dir, lang })
 */
function matchFolder(videoNames, subs) {
    var videos = [];
    var videoByBase = {};
    videoNames.forEach(function (name) {
        var base = splitExt(name).base;
        videoByBase[base.toLowerCase()] = name;
        var e = parseEpisode(base);
        if (e.kind === "episode") {
            videos.push({ name: name, base: base, season: e.season, ep: e.ep });
        }
    });

    var out = { matched: [], renames: [], unclear: [], unmatched: [] };
    var groups = {};
    var usedNames = {};

    subs.forEach(function (sub) {
        var parts = splitExt(sub.name);
        var tag = langOf(parts.base);
        var lang = tag.lang || sub.lang || "";
        var already = videoByBase[tag.stem.toLowerCase()];
        sub.lang = lang;
        if (already) {
            out.matched.push({ video: already, sub: sub, lang: lang });
            usedNames[sub.name.toLowerCase()] = true;
            return;
        }
        var e = parseEpisode(tag.stem);
        if (e.kind !== "episode") {
            out.unmatched.push(sub);
            return;
        }
        var item = { sub: sub, ext: parts.ext, tagged: tag.lang !== "", lang: lang, season: e.season, ep: e.ep };
        (groups[lang] = groups[lang] || []).push(item);
    });

    var byVideo = {};
    Object.keys(groups).forEach(function (lang) {
        var r = matchGroup(videos, groups[lang]);
        r.pairs.forEach(function (p) {
            (byVideo[p[0].name] = byVideo[p[0].name] || []).push(p[1]);
        });
        r.unclear.forEach(function (u) {
            out.unclear.push({ video: u.video.name, candidates: u.candidates.map(function (c) { return c.sub; }) });
        });
        var paired = {};
        r.pairs.forEach(function (p) { paired[p[1].sub.name + "|" + p[1].sub.dir] = true; });
        r.unclear.forEach(function (u) { u.candidates.forEach(function (c) { paired[c.sub.name + "|" + c.sub.dir] = true; }); });
        groups[lang].forEach(function (s) {
            if (!paired[s.sub.name + "|" + s.sub.dir]) {
                out.unmatched.push(s.sub);
            }
        });
    });

    Object.keys(byVideo).forEach(function (videoName) {
        var list = byVideo[videoName];
        var videoBase = splitExt(videoName).base;
        var already = out.matched.filter(function (m) { return m.video === videoName; });
        list.forEach(function (s) {
            /* Keep a language tag when the sub had one or the video gets more than one sub */
            var needTag = s.tagged || list.length + already.length > 1;
            var newName = videoBase + (needTag && s.lang ? "." + s.lang : "") + s.ext;
            if (usedNames[newName.toLowerCase()]) {
                out.unmatched.push(s.sub);
                return;
            }
            usedNames[newName.toLowerCase()] = true;
            out.renames.push({ video: videoName, sub: s.sub, newName: newName, lang: s.lang });
        });
    });

    return out;
}

/*
 * Subtitles for one video, Japanese first.
 * Returns { subs: [sub], unclear: [candidates] }
 */
function subsForVideo(videoName, result) {
    var picks = [];
    result.matched.forEach(function (m) { if (m.video === videoName) picks.push(m.sub); });
    result.renames.forEach(function (r) { if (r.video === videoName) picks.push(r.sub); });
    var unclear = [];
    result.unclear.forEach(function (u) { if (u.video === videoName) unclear = unclear.concat(u.candidates); });
    picks.sort(function (a, b) { return (b.lang === "ja") - (a.lang === "ja"); });
    return { subs: picks, unclear: unclear };
}

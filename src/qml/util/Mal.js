.pragma library
.import "SubMatch.js" as SubMatch

/*
 * MyAnimeList: which list entry a file belongs to and what to send.
 * Pure functions, no Qt: tested with Deno (tools/mal_test.js).
 */

var STATUS_LABELS = {
    watching: "Watching",
    completed: "Completed",
    on_hold: "On Hold",
    dropped: "Dropped",
    plan_to_watch: "Plan to Watch"
};

/* Compact form for comparing titles */
function norm(s) {
    s = String(s || "");
    if (s.normalize) {
        s = s.normalize("NFKC");
    }
    return s.toLowerCase().replace(/[\s\-_:;,.!?'"’‘“”()\[\]{}\/\\☆★♪・～~&+×꞉＝=]+/g, "");
}

function words(s) {
    s = String(s || "");
    if (s.normalize) {
        s = s.normalize("NFKC");
    }
    return s.toLowerCase().split(/[\s\-_:;,.!?'"’‘“”()\[\]{}\/\\☆★♪・～~&+×꞉＝=]+/).filter(function (w) { return w.length > 0; });
}

/* Season of a file: S02E05 in the name, else a folder "S2"/"Season 2",
 * else 1 */
function seasonOf(path) {
    var parts = String(path || "").split(/[\\/]/);
    var name = parts.pop();
    var m = name.match(/S(\d{1,2})[ ._-]?E\d{1,4}/i);
    if (m) {
        return Math.max(1, parseInt(m[1], 10));
    }
    for (var i = parts.length - 1; i >= Math.max(0, parts.length - 2); --i) {
        m = parts[i].match(/^(?:S|Season\s*)(\d{1,2})$/i);
        if (m) {
            return Math.max(1, parseInt(m[1], 10));
        }
    }
    return 1;
}

/* Episode number from the file name; null for extras and decimals */
function episodeOf(path) {
    var name = String(path || "").split(/[\\/]/).pop();
    var parts = String(path || "").split(/[\\/]/);
    for (var i = 0; i < parts.length - 1; ++i) {
        if (/^(?:extras?|sps?|specials?|bonus|menus?|nc|creditless|pv|ova)$/i.test(parts[i])) {
            return null;
        }
    }
    var info = SubMatch.parseEpisode(SubMatch.splitExt(name).base);
    if (info.kind !== "episode" || Math.floor(info.ep) !== info.ep || info.ep < 1) {
        return null;
    }
    return info.ep;
}

function matchKey(show, season) {
    return norm(show) + "|" + (season || 1);
}

function titlesOf(entry) {
    var t = [entry.title, entry.en, entry.ja].concat(entry.synonyms || []);
    return t.filter(function (x) { return x && String(x).length > 0; });
}

/* Word overlap of two titles, 0..1 (1 = same) */
function similarity(a, b) {
    if (norm(a).length === 0 || norm(b).length === 0) {
        return 0;
    }
    if (norm(a) === norm(b)) {
        return 1;
    }
    var wa = words(a), wb = words(b);
    var setB = {};
    wb.forEach(function (w) { setB[w] = true; });
    var common = 0;
    var seen = {};
    wa.forEach(function (w) {
        if (setB[w] && !seen[w]) {
            ++common;
            seen[w] = true;
        }
    });
    var union = Object.keys(seen).length + (wa.length - common) + (wb.length - common);
    var jaccard = union > 0 ? common / union : 0;
    /* One title is the other plus a subtitle ("Show" vs "Show: The Movie") */
    var na = norm(a), nb = norm(b);
    var prefix = (na.length >= 6 && nb.indexOf(na) === 0) || (nb.length >= 6 && na.indexOf(nb) === 0) ? 0.7 : 0;
    return Math.max(jaccard, prefix);
}

var ORDINALS = ["", "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th"];
var ROMAN = ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix"];

/* Season number a MAL title states, or 0 */
function titleSeason(title) {
    var t = String(title || "").toLowerCase();
    var m = t.match(/\bseason\s*(\d{1,2})\b/) || t.match(/\b(\d{1,2})(?:st|nd|rd|th)\s+season\b/) ||
            t.match(/\bpart\s*(\d{1,2})\b/);
    if (m) {
        return parseInt(m[1], 10);
    }
    m = t.match(/\s(ii|iii|iv|v|vi)\s*$/);
    if (m) {
        return ROMAN.indexOf(m[1]);
    }
    m = t.match(/\s(\d)\s*$/);
    if (m) {
        return parseInt(m[1], 10);
    }
    return 0;
}

/* Similarity with the season part removed from the MAL title */
function baseSimilarity(show, title) {
    var t = String(title).replace(/\b(?:season\s*\d{1,2}|\d{1,2}(?:st|nd|rd|th)\s+season|part\s*\d{1,2})\b/ig, " ")
                         .replace(/\s(?:ii|iii|iv|v|vi|\d)\s*$/i, " ");
    return similarity(show, t);
}

/*
 * The list entry for a show and season, or null when unsure.
 * Season 1: the best title match (an entry that says "season 2" loses).
 * Season n > 1: only an entry whose title says season n.
 * Unsure when the best score is under 0.75 or two different entries tie.
 */
function autoMatch(show, season, list) {
    season = season || 1;
    var scored = [];
    for (var i = 0; i < list.length; ++i) {
        var e = list[i];
        var best = 0;
        var titles = titlesOf(e);
        for (var j = 0; j < titles.length; ++j) {
            var ts = titleSeason(titles[j]);
            var score;
            if (season > 1) {
                score = ts === season ? baseSimilarity(show, titles[j]) : 0;
            } else {
                score = similarity(show, titles[j]);
                if (ts > 1) {
                    score -= 0.3;
                }
            }
            best = Math.max(best, score);
        }
        if (e.status === "watching") {
            best += 0.05;
        } else if (e.status === "plan_to_watch" || e.status === "on_hold") {
            best += 0.02;
        }
        if (best > 0) {
            scored.push({ entry: e, score: best });
        }
    }
    scored.sort(function (a, b) { return b.score - a.score; });
    if (scored.length === 0 || scored[0].score < 0.75) {
        return null;
    }
    if (scored.length > 1 && scored[1].score >= scored[0].score - 0.04 &&
            scored[1].entry.id !== scored[0].entry.id) {
        return null;
    }
    return scored[0].entry;
}

function findEntry(list, id) {
    for (var i = 0; i < list.length; ++i) {
        if (list[i].id === id) {
            return list[i];
        }
    }
    return null;
}

/*
 * What to send for "episode ep watched".
 * entry: the list entry (or a search result; status "" = not on the list).
 * Returns { change, fields, from, to, status, note }.
 * Only ever forward: the count never goes down, Completed is never undone.
 */
function planUpdate(entry, ep, today) {
    var current = entry && entry.watched ? entry.watched : 0;
    var status = entry && entry.status ? entry.status : "";
    var total = entry && entry.episodes ? entry.episodes : 0;
    if (ep === null || ep === undefined) {
        return { change: false, note: "no episode number in the file name" };
    }
    if (total > 0 && ep > total) {
        return { change: false, note: "episode " + ep + " is past MAL's " + total + " (wrong match or offset?)" };
    }
    if (ep <= current) {
        return { change: false, from: current, to: current, note: "already at " + current };
    }
    var fields = { num_watched_episodes: ep };
    var newStatus = status;
    if (status !== "completed") {
        newStatus = total > 0 && ep >= total ? "completed" : "watching";
        fields.status = newStatus;
    }
    /* Start date only when starting the show (not on the list / planned) */
    if (!(entry && entry.startDate) && (status === "" || status === "plan_to_watch")) {
        fields.start_date = today;
    }
    if (newStatus === "completed" && status !== "completed" && !(entry && entry.finishDate)) {
        fields.finish_date = today;
    }
    return { change: true, fields: fields, from: current, to: ep, status: newStatus, statusChanged: newStatus !== status };
}

/* Fields for the list panel's buttons (manual: may go down) */
function manualCount(entry, count, today) {
    var total = entry.episodes || 0;
    count = Math.max(0, total > 0 ? Math.min(total, count) : count);
    var fields = { num_watched_episodes: count };
    if (total > 0 && count >= total && entry.status !== "completed") {
        fields.status = "completed";
        if (!entry.finishDate) {
            fields.finish_date = today;
        }
    } else if (count > 0 && (entry.status === "plan_to_watch" || !entry.status)) {
        fields.status = "watching";
        if (!entry.startDate) {
            fields.start_date = today;
        }
    }
    return fields;
}

/* YYYY-MM-DD in local time */
function today(ms) {
    var d = new Date(ms || Date.now());
    var two = function (n) { return (n < 10 ? "0" : "") + n; };
    return d.getFullYear() + "-" + two(d.getMonth() + 1) + "-" + two(d.getDate());
}

/* --- Manga list --- */

var MANGA_STATUS_LABELS = {
    reading: "Reading",
    completed: "Completed",
    on_hold: "On Hold",
    dropped: "Dropped",
    plan_to_read: "Plan to Read"
};

/* Fields for a manual chapter or volume count (−/+1). kind: "chapters" or
 * "volumes". Reaching the total marks the entry completed (both counts set
 * to their totals, finish date today); the first count above 0 on a
 * planned entry marks it reading (start date today). */
function mangaCount(entry, kind, count, today) {
    var total = (kind === "chapters" ? entry.chapters : entry.volumes) || 0;
    count = Math.max(0, total > 0 ? Math.min(total, count) : count);
    var fields = {};
    fields[kind === "chapters" ? "num_chapters_read" : "num_volumes_read"] = count;
    if (total > 0 && count >= total && entry.status !== "completed") {
        fields.status = "completed";
        if (entry.chapters > 0) {
            fields.num_chapters_read = entry.chapters;
        }
        if (entry.volumes > 0) {
            fields.num_volumes_read = entry.volumes;
        }
        if (!entry.finishDate) {
            fields.finish_date = today;
        }
    } else if (count > 0 && (entry.status === "plan_to_read" || !entry.status)) {
        fields.status = "reading";
        if (!entry.startDate) {
            fields.start_date = today;
        }
    }
    return fields;
}

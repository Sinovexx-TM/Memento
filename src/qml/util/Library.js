.pragma library
.import "SubMatch.js" as SubMatch

/*
 * Anime library: series folders -> sections and episodes, watch state and
 * the next episode. Pure functions, no Qt: tested with Deno
 * (tools/library_test.js).
 */

/* Folder names that hold extras (NCOP/ED, specials, menus, CDs, ...) */
var EXTRA_DIR_RE = /^(?:extras?|sps?|specials?|bonus|menus?|nc|ncop|nced|creditless|cds?|scans?|cm|cms|pv|pvs|trailers?|ova|ovas|oad|omake|featurettes?)$/i;

/* Minimum position (s) that counts as started */
var STARTED_SECONDS = 30;

/* History key of a file: "/" separators, lower case (Windows paths) */
function key(path) {
    return String(path || "").replace(/\\/g, "/").replace(/\/+$/, "").toLowerCase();
}

/* Display title of a series folder name */
function seriesTitle(folderName) {
    var s = String(folderName);
    s = s.replace(/\[[^\]]*\]|\([^)]*\)|\{[^}]*\}|【[^】]*】/g, " ");
    s = s.replace(/\b(?:BD|DVD)[ -]?BOX\b/gi, " ");
    s = s.replace(/\s+-\s+(?:TV(?:\s*\+\s*\w+)*|SP|Complete|Batch|BD|BDRip)\s*$/i, " ");
    s = s.replace(/[_]+/g, " ").replace(/\s+/g, " ").trim();
    s = s.replace(/^[-\s]+|[-\s]+$/g, "");
    return s.length > 0 ? s : String(folderName);
}

/* "S1" -> "Season 1"; "Season 2" stays; others as they are */
function sectionTitle(dir) {
    var m = dir.match(/^(?:S|Season\s*)(\d{1,2})$/i);
    return m ? "Season " + parseInt(m[1], 10) : dir;
}

/* Label of an extra: a tag in brackets ([Drama01], [ED_EP45(O.A. Ver.)])
 * or the part after " - " ("ED ep.9"), otherwise the cleaned name */
function extraLabel(base) {
    var rest = base.replace(/^\s*\[[^\]]*\]/, " ");
    var tags = rest.match(/\[[^\]]{2,40}\]/g) || [];
    for (var i = 0; i < tags.length; ++i) {
        var inner = tags[i].slice(1, -1);
        if (/[A-Za-z]/.test(inner) && SubMatch.cleanName(inner).replace(/[\s._-]+/g, "").length > 0) {
            return inner.replace(/_/g, " ").trim();
        }
    }
    var m = rest.match(/\s-\s+(.+?)\s*(?:\(|\[|$)/);
    if (m && m[1].trim().length > 0) {
        return m[1].trim();
    }
    var clean = SubMatch.cleanName(base).replace(/\s+/g, " ").trim();
    return clean.length > 0 ? clean : base;
}

/* Show name of a loose file: the part before the episode number, without
 * the group and release tags ("Dragon.Ball.Super.Beerus.S01E06.1080p..."
 * -> "Dragon Ball Super Beerus") */
function looseShowName(fileName) {
    var base = SubMatch.splitExt(fileName).base;
    var s = base.replace(/^\s*\[[^\]]*\]\s*/, "");
    /* Dots and underscores as spaces, but keep decimals like 12.5 */
    s = s.replace(/[._](?!\d(?:\D|$))/g, " ").replace(/_/g, " ");
    var cuts = [
        /\bS\d{1,2}\s?E\d{1,4}\b/i,
        /\s-\s*\d{1,4}(?:\.\d)?(?:v\d)?\b/,
        /\[\s*\d{1,4}(?:v\d)?\s*\]/,
        /\b(?:Episode|Ep)\s*\d{1,4}\b/i,
        /第\s*\d{1,4}\s*[話话回]/,
        /\s\d{1,3}(?:v\d)?(?:\s|$)/
    ];
    for (var i = 0; i < cuts.length; ++i) {
        var m = s.match(cuts[i]);
        if (m && m.index > 0) {
            s = s.substring(0, m.index);
            break;
        }
    }
    s = SubMatch.cleanName(s);
    s = s.replace(/\b(?:AMZN|NF|CR|DSNP|HULU|ABEMA|B-Global|WEB(?:-?DL|-?Rip)?|BD(?:Rip)?|BluRay|JPN|Dual[- ]Audio)\b/gi, " ");
    s = s.replace(/\s+/g, " ").replace(/^[-\s]+|[-\s]+$/g, "");
    return s.length > 0 ? s : base;
}

/* Loose files grouped into series: [{ folder: { name, path }, files }].
 * The path is a made-up key under the library folder, so history and
 * custom names work as for folders. */
function groupLoose(root, files) {
    var groups = {};
    var order = [];
    for (var i = 0; i < files.length; ++i) {
        var name = looseShowName(files[i].rel);
        var k = name.toLowerCase();
        if (!groups[k]) {
            groups[k] = { folder: { name: name, path: root + "/:loose:/" + name, loose: true }, files: [] };
            order.push(k);
        }
        groups[k].files.push(files[i]);
    }
    return order.map(function (k) { return groups[k]; });
}

function compareNatural(a, b) {
    return a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" });
}

function formatNumber(n) {
    return String(Math.round(n * 10) / 10);
}

/*
 * Builds a series.
 * folder: { name, path }; files: [{ rel, path }]; history: key -> entry;
 * names: key -> custom name.
 * Returns { key, path, folderName, title, sections: [{ title, extra,
 * episodes }], main: [episode], watched, total, next, resume, started,
 * finished, lastDate }.
 * episode: { path, key, rel, label, short, num, extra, done, pos, dur,
 * date, watchedDate, progress, index }
 */
function buildSeries(folder, files, history, names) {
    history = history || {};
    names = names || {};
    var sectionsByDir = {};
    var order = [];

    for (var i = 0; i < files.length; ++i) {
        var f = files[i];
        var parts = f.rel.split("/");
        var fileName = parts.pop();
        var dirs = parts;
        var base = SubMatch.splitExt(fileName).base;
        var info = SubMatch.parseEpisode(base);

        var extraDir = false;
        for (var d = 0; d < dirs.length; ++d) {
            if (EXTRA_DIR_RE.test(dirs[d])) {
                extraDir = true;
            }
        }
        var extra = extraDir || info.kind === "extra";

        /* Section: the folder (without its extras subfolder) + extra flag */
        var mainDirs = [];
        for (var md = 0; md < dirs.length && !EXTRA_DIR_RE.test(dirs[md]); ++md) {
            mainDirs.push(dirs[md]);
        }
        var dirKey = mainDirs.join("/");
        var sectionKey = dirKey + (extra ? "|extra" : "");
        if (!sectionsByDir[sectionKey]) {
            var title = mainDirs.length > 0 ? mainDirs.map(sectionTitle).join(" · ") : "";
            if (extra) {
                title = title.length > 0 ? title + " · Extras" : "Extras";
            }
            sectionsByDir[sectionKey] = { dir: dirKey, title: title, extra: extra, episodes: [] };
            order.push(sectionKey);
        }

        var k = key(f.path);
        var h = history[k] || {};
        var num = !extra && info.kind === "episode" ? info.ep : null;
        var label;
        var shortLabel;
        if (num !== null) {
            label = "Episode " + formatNumber(num);
            shortLabel = "E" + formatNumber(num);
        } else if (extra) {
            label = extraLabel(base);
            /* "ED flash/01.mkv": a bare number needs its folder */
            if (/^\d{1,3}$/.test(label) && dirs.length > mainDirs.length + 1) {
                label = dirs[dirs.length - 1] + " " + label;
            }
            shortLabel = label;
        } else {
            label = SubMatch.cleanName(base).replace(/\s+/g, " ").trim() || base;
            shortLabel = label;
        }
        var dur = h.dur || 0;
        var pos = h.pos || 0;
        sectionsByDir[sectionKey].episodes.push({
            path: f.path,
            key: k,
            rel: f.rel,
            fileName: fileName,
            label: label,
            short: shortLabel,
            num: num,
            extra: extra,
            done: !!h.done,
            pos: pos,
            dur: dur,
            date: h.date || 0,
            watchedDate: h.watchedDate || 0,
            progress: !h.done && dur > 0 && pos >= STARTED_SECONDS ? Math.min(1, pos / dur) : 0
        });
    }

    var sections = order.map(function (sk) { return sectionsByDir[sk]; });
    sections.forEach(function (s) {
        s.episodes.sort(function (a, b) {
            if (a.num !== null && b.num !== null && a.num !== b.num) {
                return a.num - b.num;
            }
            if ((a.num === null) !== (b.num === null)) {
                return a.num === null ? 1 : -1;
            }
            return compareNatural(a.fileName, b.fileName);
        });
    });
    /* Main sections first (the folder itself, then subfolders naturally),
     * extras last in the same order */
    sections.sort(function (a, b) {
        if (a.extra !== b.extra) {
            return a.extra ? 1 : -1;
        }
        if ((a.dir === "") !== (b.dir === "")) {
            return a.dir === "" ? -1 : 1;
        }
        return compareNatural(a.dir, b.dir);
    });
    /* A lone main section needs no heading */
    var mainSections = sections.filter(function (s) { return !s.extra; });
    if (mainSections.length === 1 && mainSections[0].title.length === 0) {
        mainSections[0].title = "";
    } else {
        mainSections.forEach(function (s) {
            if (s.title.length === 0) {
                s.title = "Episodes";
            }
        });
    }

    var main = [];
    mainSections.forEach(function (s) {
        s.episodes.forEach(function (e) {
            e.index = main.length;
            main.push(e);
        });
    });
    /* Short labels need the season when there are several */
    if (mainSections.length > 1) {
        mainSections.forEach(function (s) {
            var m = s.title.match(/^Season (\d+)/);
            if (m) {
                s.episodes.forEach(function (e) {
                    if (e.num !== null) {
                        e.short = "S" + m[1] + " " + e.short;
                    }
                });
            }
        });
    }

    var folderKey = key(folder.path);
    var series = {
        key: folderKey,
        path: folder.path,
        folderName: folder.name,
        title: names[folderKey] || (folder.loose ? folder.name : seriesTitle(folder.name)),
        loose: !!folder.loose,
        sections: sections,
        main: main,
        watched: main.filter(function (e) { return e.done; }).length,
        total: main.length
    };
    var state = nextEpisode(main);
    series.next = state.next;
    series.resume = state.resume;
    series.started = state.started;
    series.finished = state.finished;

    var last = 0;
    sections.forEach(function (s) {
        s.episodes.forEach(function (e) {
            last = Math.max(last, e.date, e.watchedDate);
        });
    });
    series.lastDate = last;
    return series;
}

/*
 * The episode to watch next.
 * - an unfinished episode watched more recently than the last finished one
 *   -> resume it
 * - else the first unwatched episode after the last watched one
 * started: anything watched or begun; finished: all watched
 */
function nextEpisode(main) {
    var lastDone = -1;
    var lastDoneDate = 0;
    var resume = null;
    for (var i = 0; i < main.length; ++i) {
        var e = main[i];
        if (e.done) {
            lastDone = i;
            lastDoneDate = Math.max(lastDoneDate, e.watchedDate || e.date);
        } else if (e.progress > 0 && (resume === null || e.date > resume.date)) {
            resume = e;
        }
    }
    var started = lastDone >= 0 || resume !== null;
    if (resume !== null && resume.date >= lastDoneDate) {
        return { next: resume, resume: true, started: true, finished: false };
    }
    if (lastDone >= 0) {
        for (var j = lastDone + 1; j < main.length; ++j) {
            if (!main[j].done) {
                return { next: main[j], resume: main[j].progress > 0, started: true, finished: false };
            }
        }
        /* Gaps before the last watched one: the first unwatched episode */
        for (var k = 0; k < main.length; ++k) {
            if (!main[k].done) {
                return { next: main[k], resume: main[k].progress > 0, started: true, finished: false };
            }
        }
        return { next: null, resume: false, started: true, finished: main.length > 0 };
    }
    return {
        next: main.length > 0 ? main[0] : null,
        resume: false,
        started: started,
        finished: false
    };
}

/* Series to show in "Continue watching", most recent first */
function continueList(seriesList) {
    return seriesList
        .filter(function (s) { return s.started && !s.finished && s.next !== null; })
        .sort(function (a, b) { return b.lastDate - a.lastDate; });
}

/* Keys of all main episodes before (and including) an episode */
function keysUpTo(series, episode) {
    var keys = [];
    for (var i = 0; i <= episode.index && i < series.main.length; ++i) {
        keys.push(series.main[i].key);
    }
    return keys;
}

/* 1:05:09 / 12:31 */
function formatTime(seconds) {
    seconds = Math.max(0, Math.round(seconds));
    var h = Math.floor(seconds / 3600);
    var m = Math.floor(seconds % 3600 / 60);
    var s = seconds % 60;
    var two = function (n) { return (n < 10 ? "0" : "") + n; };
    return h > 0 ? h + ":" + two(m) + ":" + two(s) : m + ":" + two(s);
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/* "today", "yesterday", "17 Nov", "17 Nov 2025" */
function formatDate(ms, nowMs) {
    if (!ms) {
        return "";
    }
    var d = new Date(ms);
    var now = new Date(nowMs || Date.now());
    var day = function (x) { return new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime(); };
    var diff = Math.round((day(now) - day(d)) / 86400000);
    if (diff === 0) {
        return "today";
    }
    if (diff === 1) {
        return "yesterday";
    }
    var text = d.getDate() + " " + MONTHS[d.getMonth()];
    return d.getFullYear() === now.getFullYear() ? text : text + " " + d.getFullYear();
}

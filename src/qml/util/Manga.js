.pragma library

/* Pure helpers for the manga reader (tested in tools/manga_test.js). */

/* Characters that don't count as read text: whitespace, ASCII and CJK
 * punctuation, fullwidth punctuation and common symbols (GSM-like: letters,
 * digits and ー count). */
const NOT_COUNTED = /[\s!-\/:-@\[-`{-~ -¿ -⁯←-⇿①-⓿─-➿　-〄〇-〿・！-／：-＠［-｀｛-･︰-﹏]/g;

function countChars(text) {
    if (!text) {
        return 0;
    }
    return String(text).replace(NOT_COUNTED, "").length;
}

function blockText(block) {
    return (block.lines || []).join("");
}

function pageChars(page) {
    let total = 0;
    for (const block of page.blocks || []) {
        total += countChars(blockText(block));
    }
    return total;
}

function quadRect(quad) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const p of quad) {
        x0 = Math.min(x0, p[0]);
        y0 = Math.min(y0, p[1]);
        x1 = Math.max(x1, p[0]);
        y1 = Math.max(y1, p[1]);
    }
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
}

/**
 * Which character of a block is at image point (x, y).
 * Returns { text, index } (index into blockText) or null.
 */
function hitTest(block, x, y) {
    const lines = block.lines || [];
    const coords = block.coords || [];
    let offset = 0;
    for (let i = 0; i < lines.length; ++i) {
        const line = String(lines[i]);
        const quad = coords[i];
        if (quad && line.length > 0) {
            const r = quadRect(quad);
            /* A little slack across the line, none along it */
            const slackX = block.vertical ? r.w * 0.15 : 0;
            const slackY = block.vertical ? 0 : r.h * 0.15;
            if (x >= r.x - slackX && x <= r.x + r.w + slackX &&
                y >= r.y - slackY && y <= r.y + r.h + slackY) {
                const t = block.vertical ? (y - r.y) / Math.max(r.h, 1)
                                         : (x - r.x) / Math.max(r.w, 1);
                const at = Math.min(line.length - 1, Math.max(0, Math.floor(t * line.length)));
                return { text: blockText(block), index: offset + at };
            }
        }
        offset += line.length;
    }
    return null;
}

/* Rectangle of one character, for the hover highlight */
function charRect(block, index) {
    const lines = block.lines || [];
    const coords = block.coords || [];
    let offset = 0;
    for (let i = 0; i < lines.length; ++i) {
        const line = String(lines[i]);
        if (index < offset + line.length && coords[i]) {
            const r = quadRect(coords[i]);
            const k = index - offset;
            if (block.vertical) {
                const step = r.h / line.length;
                return { x: r.x, y: r.y + k * step, w: r.w, h: step };
            }
            const step = r.w / line.length;
            return { x: r.x + k * step, y: r.y, w: step, h: r.h };
        }
        offset += line.length;
    }
    return null;
}

/* "13DL.me-Fire_Punch_ vol 01-08" → "Fire Punch" */
function seriesTitle(name) {
    let s = String(name || "");
    s = s.replace(/\[[^\]]*\]|\([^)]*\)|【[^】]*】/g, " ");
    s = s.replace(/^\s*[A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+[-_ ]+/, "");
    s = s.replace(/_/g, " ");
    s = s.split(/[,、]/)[0];
    s = s.replace(/\s+(?:vol\.?|v|volume)\s*\d+(?:\s*-\s*\d+)?\s*$/i, "");
    s = s.replace(/\s+/g, " ").trim();
    return s.length > 0 ? s : String(name || "");
}

/* "13DL.me-Fire_Punch_v03" → "Vol. 3", "ドラゴンボール超 第05巻" → "Vol. 5" */
function volumeLabel(name) {
    const s = String(name || "");
    const m = s.match(/第\s*0*(\d+)\s*巻/) ||
              s.match(/(?:^|[^A-Za-z])(?:vol(?:ume)?\.?|v)\s*0*(\d+)(?![\d-])/i);
    if (m) {
        return "Vol. " + m[1];
    }
    return seriesTitle(s);
}

/**
 * Groups volumes into series: [{ key, title, volumes, cover }] in the
 * volumes' order (already naturally sorted).
 */
function groupSeries(volumes) {
    const map = {};
    const order = [];
    for (const v of volumes) {
        if (!map[v.seriesPath]) {
            map[v.seriesPath] = { key: v.seriesPath, title: seriesTitle(v.series), volumes: [], cover: v.cover };
            order.push(v.seriesPath);
        }
        map[v.seriesPath].volumes.push(v);
    }
    return order.map(k => map[k]);
}

/**
 * Adds reading time from one activity tick.
 * Counts elapsed time only when the last activity was within idleMs.
 */
function addActive(seconds, nowMs, lastActivityMs, elapsedMs, idleMs) {
    if (nowMs - lastActivityMs > idleMs) {
        return seconds;
    }
    return seconds + elapsedMs / 1000;
}

function formatMinutes(seconds) {
    const m = Math.round(seconds / 60);
    if (m < 60) {
        return m + " min";
    }
    return Math.floor(m / 60) + " h " + (m % 60) + " min";
}

/* Toggl description: {show} and {volume} filled in */
function describe(template, show, volume) {
    let text = String(template || "{show} {volume}");
    if (!volume) {
        text = text.replace(/\S*\{volume\}\S*/g, "");
    }
    return text.replace(/\{show\}/g, show || "").replace(/\{volume\}/g, volume || "")
               .replace(/\s+/g, " ").trim();
}

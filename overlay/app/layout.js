/*
 * Pure layout maths for the overlay page (tested by tools/overlay_test.js).
 *
 * Memento sends every character's screen box. The page can't place each
 * character absolutely (Yomitan treats absolutely placed elements as
 * separate paragraphs and would not scan across them), so each block becomes
 * one absolutely placed box holding normal-flow lines of inline-block
 * characters. Everything is worked out in "logical" units so the same code
 * does horizontal subtitles and vertical (top-to-bottom, right-to-left)
 * manga columns:
 *   inline = along the line (x for horizontal, y for vertical)
 *   block  = across lines   (y downwards, or x leftwards from the right edge)
 */
'use strict';

/* Joins surrogate pairs so a character and its box stay together */
function splitChars(text, rects) {
    const out = [];
    for (let k = 0; k < text.length && k < rects.length; ++k) {
        const code = text.charCodeAt(k);
        const r = rects[k];
        if (!r) {
            continue;
        }
        if (code >= 0xd800 && code <= 0xdbff && k + 1 < text.length && rects[k + 1]) {
            const r2 = rects[k + 1];
            const x0 = Math.min(r[0], r2[0]);
            const y0 = Math.min(r[1], r2[1]);
            const x1 = Math.max(r[0] + r[2], r2[0] + r2[2]);
            const y1 = Math.max(r[1] + r[3], r2[1] + r2[3]);
            out.push({ ch: text.substr(k, 2), rect: [x0, y0, x1 - x0, y1 - y0] });
            ++k;
            continue;
        }
        out.push({ ch: text[k], rect: r });
    }
    return out;
}

/**
 * @param block {vertical, lines: [{text, rects: [[x, y, w, h], ...]}]}
 * @return {vertical, left, top, width, height,
 *          lines: [{marginBlock, blockSize, chars: [{ch, marginInline, inlineSize}]}]}
 *         or null when the block has no characters.
 */
function layoutBlock(block) {
    const vertical = !!block.vertical;
    const lines = (block.lines || []).map(l => splitChars(String(l.text || ''), l.rects || []))
        .filter(chars => chars.length > 0);
    if (lines.length === 0) {
        return null;
    }

    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const chars of lines) {
        for (const c of chars) {
            const [x, y, w, h] = c.rect;
            x0 = Math.min(x0, x);
            y0 = Math.min(y0, y);
            x1 = Math.max(x1, x + w);
            y1 = Math.max(y1, y + h);
        }
    }

    const logical = rect => {
        const [x, y, w, h] = rect;
        return vertical
            ? { i: y - y0, il: h, b: x1 - (x + w), bl: w }
            : { i: x - x0, il: w, b: y - y0, bl: h };
    };

    /* Lines in block order (top to bottom, or right to left) */
    const prepared = lines.map(chars => {
        const ls = chars.map(c => ({ ch: c.ch, ...logical(c.rect) }));
        const b0 = Math.min(...ls.map(c => c.b));
        const b1 = Math.max(...ls.map(c => c.b + c.bl));
        return { ls, b0, b1 };
    }).sort((a, b) => a.b0 - b.b0);

    let blockCursor = 0;
    const out = [];
    for (const line of prepared) {
        const blockSize = Math.max(1, line.b1 - Math.max(line.b0, blockCursor));
        const marginBlock = Math.max(0, line.b0 - blockCursor);
        blockCursor = Math.max(blockCursor, line.b0) + blockSize;

        let inlineCursor = 0;
        const chars = [];
        for (const c of line.ls) {
            const inlineSize = Math.max(1, c.il);
            chars.push({ ch: c.ch, marginInline: c.i - inlineCursor, inlineSize });
            inlineCursor = c.i + inlineSize;
        }
        out.push({ marginBlock, blockSize, chars });
    }

    return { vertical, left: x0, top: y0, width: x1 - x0, height: y1 - y0, lines: out };
}

/**
 * Font size that makes a glyph fill its box.
 * @param advance Width of the character at font size 1 (0 if unknown).
 */
function fontSizeFor(inlineSize, blockSize, advance, vertical) {
    const max = blockSize * 1.3;
    if (vertical) {
        /* Upright characters advance by 1em down the column */
        return Math.max(4, Math.min(inlineSize, max));
    }
    if (!(advance > 0.05)) {
        return Math.max(4, Math.min(blockSize * 0.8, max));
    }
    return Math.max(4, Math.min(inlineSize / advance, max));
}

if (typeof module !== 'undefined') {
    module.exports = { splitChars, layoutBlock, fontSizeFor };
}

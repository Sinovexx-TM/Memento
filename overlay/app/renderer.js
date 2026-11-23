/* Overlay page: draws Memento's text invisibly for Yomitan and reports what
 * is under the cursor (layoutBlock and fontSizeFor come from layout.js). */
'use strict';

const textRoot = document.getElementById('text-root');
const bridge = window.overlayBridge;

let fontFamily = '';
let lastState = '';
let popupOpen = false;
let cursor = null;

/* Glyph widths at font size 1, per font, measured once */
const measureCanvas = document.createElement('canvas').getContext('2d');
const advanceCache = new Map();

function advanceOf(ch) {
    const key = fontFamily + '\u0000' + ch;
    let value = advanceCache.get(key);
    if (value === undefined) {
        measureCanvas.font = `100px ${fontFamily ? `"${fontFamily}", ` : ''}sans-serif`;
        value = measureCanvas.measureText(ch).width / 100;
        advanceCache.set(key, value);
    }
    return value;
}

function render(blocks) {
    const fragment = document.createDocumentFragment();
    for (const block of blocks || []) {
        const layout = layoutBlock(block);
        if (!layout) {
            continue;
        }
        const div = document.createElement('div');
        div.className = 'ov-block' + (layout.vertical ? ' vertical' : '');
        div.style.left = layout.left + 'px';
        div.style.top = layout.top + 'px';
        div.style.width = layout.width + 'px';
        div.style.height = layout.height + 'px';
        if (fontFamily) {
            div.style.fontFamily = `"${fontFamily}", sans-serif`;
        }
        for (const line of layout.lines) {
            const lineDiv = document.createElement('div');
            lineDiv.className = 'ov-line';
            lineDiv.style.marginBlockStart = line.marginBlock + 'px';
            lineDiv.style.blockSize = line.blockSize + 'px';
            lineDiv.style.lineHeight = line.blockSize + 'px';
            for (const c of line.chars) {
                const span = document.createElement('span');
                span.className = 'ov-char';
                span.textContent = c.ch;
                span.style.marginInlineStart = c.marginInline + 'px';
                span.style.inlineSize = c.inlineSize + 'px';
                span.style.fontSize = fontSizeFor(
                    c.inlineSize, line.blockSize,
                    layout.vertical ? 1 : advanceOf(c.ch), layout.vertical) + 'px';
                lineDiv.appendChild(span);
            }
            div.appendChild(lineDiv);
        }
        fragment.appendChild(div);
    }
    textRoot.replaceChildren(fragment);
    updateState();
}

function ours(el) {
    return el === textRoot || el === document.body || el === document.documentElement;
}

function updateState() {
    let interactive = false;
    let overText = false;
    if (cursor) {
        const el = document.elementFromPoint(cursor.x, cursor.y);
        if (el && !ours(el)) {
            interactive = true;
            overText = !!el.closest && !!el.closest('.ov-block');
        }
    }
    const key = interactive + ',' + overText;
    if (key !== lastState) {
        lastState = key;
        bridge.state({ interactive, overText });
    }
}

/* Yomitan's popup is an iframe it adds to this page */
function popupVisible() {
    for (const frame of document.querySelectorAll('iframe.yomitan-popup')) {
        const style = getComputedStyle(frame);
        if (style.visibility === 'hidden' || style.display === 'none') {
            continue;
        }
        const rect = frame.getBoundingClientRect();
        if (rect.width > 0 && rect.height > 0) {
            return true;
        }
    }
    return false;
}

setInterval(() => {
    const open = popupVisible();
    if (open !== popupOpen) {
        popupOpen = open;
        bridge.popup(open);
    }
}, 120);

bridge.onCursor(point => {
    cursor = point;
    updateState();
});

bridge.onMemento(msg => {
    if (msg.type === 'text') {
        fontFamily = msg.font || '';
        render(msg.blocks);
    } else if (msg.type === 'debug') {
        document.body.classList.toggle('debug', !!msg.on);
    }
});

bridge.loaded();

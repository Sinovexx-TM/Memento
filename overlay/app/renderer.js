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

/* Text of the blocks shown now, to tell "same text, moved" from "new text" */
let shownSignature = '';

function signatureOf(layouts) {
    return JSON.stringify(layouts.map(l => [l.vertical, l.lines.map(line => line.chars.map(c => c.ch).join(''))]));
}

function placeBlock(div, layout) {
    div.className = 'ov-block' + (layout.vertical ? ' vertical' : '');
    div.style.left = layout.left + 'px';
    div.style.top = layout.top + 'px';
    div.style.width = layout.width + 'px';
    div.style.height = layout.height + 'px';
    div.style.fontFamily = fontFamily ? `"${fontFamily}", sans-serif` : '';
}

function placeLine(lineDiv, line) {
    lineDiv.style.marginBlockStart = line.marginBlock + 'px';
    lineDiv.style.blockSize = line.blockSize + 'px';
    lineDiv.style.lineHeight = line.blockSize + 'px';
}

function placeChar(span, c, line, vertical) {
    span.style.marginInlineStart = c.marginInline + 'px';
    span.style.inlineSize = c.inlineSize + 'px';
    span.style.fontSize = fontSizeFor(
        c.inlineSize, line.blockSize, vertical ? 1 : advanceOf(c.ch), vertical) + 'px';
}

function render(blocks) {
    const layouts = (blocks || []).map(layoutBlock).filter(l => l !== null);
    const signature = signatureOf(layouts) + fontFamily;

    /* Same text that only moved (controls showing, zoom, pan): move the
     * existing nodes so Yomitan keeps its selection and popup */
    if (signature === shownSignature && textRoot.children.length === layouts.length) {
        layouts.forEach((layout, b) => {
            const div = textRoot.children[b];
            placeBlock(div, layout);
            layout.lines.forEach((line, i) => {
                const lineDiv = div.children[i];
                placeLine(lineDiv, line);
                line.chars.forEach((c, k) => placeChar(lineDiv.children[k], c, line, layout.vertical));
            });
        });
        updateState();
        return;
    }

    const fragment = document.createDocumentFragment();
    for (const layout of layouts) {
        const div = document.createElement('div');
        placeBlock(div, layout);
        for (const line of layout.lines) {
            const lineDiv = document.createElement('div');
            lineDiv.className = 'ov-line';
            placeLine(lineDiv, line);
            for (const c of line.chars) {
                const span = document.createElement('span');
                span.className = 'ov-char';
                span.textContent = c.ch;
                placeChar(span, c, line, layout.vertical);
                lineDiv.appendChild(span);
            }
            div.appendChild(lineDiv);
        }
        fragment.appendChild(div);
    }
    textRoot.replaceChildren(fragment);
    shownSignature = signature;
    bridge.log(`text: ${layouts.length} block(s) "${layouts.map(l => l.lines.map(x => x.chars.map(c => c.ch).join('')).join('/')).join(' | ').slice(0, 80)}"`);
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
        bridge.log(`cursor: interactive=${interactive} overText=${overText}`);
        bridge.state({ interactive, overText });
    }
}

/* Yomitan's popup is an iframe it adds to this page */
/* Yomitan's popup frames: in the page, or inside the (open) shadow root of
 * a container element when Yomitan's "shadow DOM" option is on */
function popupFrames() {
    const frames = [...document.querySelectorAll('iframe.yomitan-popup')];
    for (const host of document.querySelectorAll('body > *, html > *')) {
        if (host.shadowRoot) {
            frames.push(...host.shadowRoot.querySelectorAll('iframe.yomitan-popup'));
        }
    }
    return frames;
}

function popupVisible() {
    for (const frame of popupFrames()) {
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
        bridge.log(`popup: ${open ? 'open' : 'closed'}`);
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

/*
 * Memento Yomitan overlay (fork).
 *
 * A see-through, always-on-top window over Memento's player. Memento sends
 * the text it shows (subtitles or manga bubbles) with the exact screen box of
 * every character; the page lays invisible text on those boxes so the real,
 * unmodified Yomitan extension can scan it. The window lets clicks through
 * everywhere except over that text and Yomitan's popup.
 *
 * Talks to Memento over a local TCP connection (port given as --port=N),
 * one JSON object per line:
 *   Memento -> overlay: window {x,y,w,h,visible}, text {blocks}, debug {on},
 *                       openSettings, quit
 *   overlay -> Memento: ready {extension}, hover {on}, popup {open},
 *                       noteAdded {time, fields}, log {message}
 *
 * Yomitan runs as a separate program (GPL-3); nothing of it is copied here.
 */
'use strict';

const { app, BrowserWindow, session, screen, ipcMain } = require('electron');
const net = require('net');
const path = require('path');
const fs = require('fs');

/* Own profile folder next to Memento's config, so Yomitan's dictionaries and
 * settings survive updates and don't mix with any other Electron app. */
const configRoot = path.join(process.env.LOCALAPPDATA || app.getPath('appData'), 'memento');
app.setPath('userData', process.env.MEMENTO_OVERLAY_PROFILE ||
    path.join(configRoot, 'yomitan-overlay'));

if (!app.requestSingleInstanceLock()) {
    app.quit();
}

/* Transparent windows need the GPU compositor; keep it on but don't let a
 * hidden window throttle timers (the cursor poll must keep running). */
app.commandLine.appendSwitch('disable-renderer-backgrounding');

const portArg = process.argv.find(a => a.startsWith('--port='));
const port = portArg ? Number(portArg.slice(7)) : 0;

let overlay = null;
let settingsWindow = null;
let extension = null;
let socket = null;
let inbuf = '';

let windowRect = null;          /* {x,y,w,h} in screen DIPs */
let wantVisible = false;
let ignoring = true;            /* click-through state */
let popupOpen = false;
let lastCursor = '';
let lastHiddenWhy = '';

function send(obj) {
    if (socket && !socket.destroyed) {
        socket.write(JSON.stringify(obj) + '\n');
    }
}

/* %LOCALAPPDATA%\memento\yomitan-overlay\overlay.log, restarted each run */
const logPath = path.join(app.getPath('userData'), 'overlay.log');
try {
    fs.mkdirSync(path.dirname(logPath), { recursive: true });
    fs.writeFileSync(logPath, '');
} catch (e) { /* no log then */ }

function writeLog(message) {
    try {
        fs.appendFileSync(logPath, `${new Date().toISOString()} ${message}\n`);
    } catch (e) { /* ignore */ }
}

function log(message) {
    writeLog(message);
    send({ type: 'log', message: String(message) });
}

/* Every page and worker's console (overlay page, Yomitan's background,
 * its settings page and popups) goes to the log */
app.on('web-contents-created', (_event, wc) => {
    wc.on('console-message', (details) => {
        const d = details && details.message !== undefined ? details : {};
        const level = d.level !== undefined ? d.level : '';
        writeLog(`[console ${level}] ${d.message || ''} (${d.sourceId || ''}:${d.lineNumber || ''}) ${wc.getURL()}`);
    });
    wc.on('did-fail-load', (_e, code, desc, url) => writeLog(`[load failed] ${code} ${desc} ${url}`));
    wc.on('render-process-gone', (_e, details) => writeLog(`[renderer gone] ${details.reason} ${wc.getURL()}`));
    wc.on('preload-error', (_e, preloadPath, error) => writeLog(`[preload error] ${preloadPath} ${error}`));
});

process.on('uncaughtException', e => writeLog(`[main error] ${e && e.stack || e}`));

function yomitanDir() {
    const packaged = path.join(process.resourcesPath || '', 'yomitan');
    if (fs.existsSync(path.join(packaged, 'manifest.json'))) {
        return packaged;
    }
    return path.join(__dirname, '..', 'yomitan');
}

/* Yomitan's ID is fixed (manifest key, see windows/patch-yomitan.py). Before
 * that it came from the install folder, so each folder had its own data.
 * Settings (chrome.storage) can be carried over by copying their folder: do
 * that once, from the most used old ID. Dictionaries can't (Chromium records
 * the ID inside the database), so they are imported once more. */
const YOMITAN_ID = 'ijackakicchpihljanchkfbindleipce';

function folderSize(dir) {
    let total = 0;
    try {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
            const full = path.join(dir, entry.name);
            total += entry.isDirectory() ? folderSize(full) : fs.statSync(full).size;
        }
    } catch (e) { /* missing */ }
    return total;
}

function adoptOldYomitanSettings() {
    const profile = app.getPath('userData');
    const idb = path.join(profile, 'IndexedDB');
    const settings = path.join(profile, 'Local Extension Settings');
    try {
        if (fs.existsSync(path.join(settings, YOMITAN_ID)) || !fs.existsSync(idb)) {
            return;
        }
        const old = fs.readdirSync(idb)
            .map(name => /^chrome-extension_([a-p]{32})_0\.indexeddb\.leveldb$/.exec(name))
            .filter(m => m && m[1] !== YOMITAN_ID && fs.existsSync(path.join(settings, m[1])))
            .map(m => ({ id: m[1], dir: path.join(idb, m[0]) }))
            .filter(o => folderSize(o.dir) > 1024 * 1024)
            .sort((a, b) => fs.statSync(b.dir).mtimeMs - fs.statSync(a.dir).mtimeMs)[0];
        if (!old) {
            return;
        }
        fs.cpSync(path.join(settings, old.id), path.join(settings, YOMITAN_ID), { recursive: true });
        writeLog(`Copied Yomitan's settings from ${old.id}`);
    } catch (e) {
        writeLog('Could not copy the old Yomitan settings: ' + e.message);
    }
}

async function loadYomitan() {
    const dir = yomitanDir();
    if (!fs.existsSync(path.join(dir, 'manifest.json'))) {
        log('Yomitan not found at ' + dir);
        return null;
    }
    const api = session.defaultSession.extensions || session.defaultSession;
    try {
        const ext = await api.loadExtension(dir, { allowFileAccess: true });
        writeLog(`Yomitan ${ext.version} loaded from ${dir}, id ${ext.id}`);
        return ext;
    } catch (e) {
        log('Could not load Yomitan: ' + e.message);
        return null;
    }
}

/* Back on top of Memento: after a hide/show (card builder, app switch)
 * Windows can leave the overlay behind Memento's window, so the popup is
 * hidden and clicks go to Memento */
function raiseOverlay() {
    if (!overlay) {
        return;
    }
    overlay.setAlwaysOnTop(false);
    overlay.setAlwaysOnTop(true, 'screen-saver');
    overlay.moveTop();
}

function setIgnore(ignore) {
    if (!overlay || ignoring === ignore) {
        return;
    }
    ignoring = ignore;
    overlay.setIgnoreMouseEvents(ignore, { forward: true });
}

function applyWindow() {
    if (!overlay) {
        return;
    }
    if (windowRect && windowRect.w > 0 && windowRect.h > 0) {
        const b = overlay.getBounds();
        const r = {
            x: Math.round(windowRect.x), y: Math.round(windowRect.y),
            width: Math.round(windowRect.w), height: Math.round(windowRect.h)
        };
        if (b.x !== r.x || b.y !== r.y || b.width !== r.width || b.height !== r.height) {
            overlay.setBounds(r);
        }
    }
    if (wantVisible && windowRect) {
        if (!overlay.isVisible()) {
            overlay.showInactive();
            raiseOverlay();
            lastCursor = null;
            /* Re-apply the page's mouse state after being hidden */
            ignoring = null;
            if (popupOpen) {
                /* Left open when Memento hid us (e.g. the card builder) */
                closePopup();
            }
        }
    } else if (overlay.isVisible()) {
        writeLog('Hidden by Memento');
        overlay.hide();
        setIgnore(true);
        /* No reload here: reloading while Yomitan is still finishing an add
         * (the card builder opens right after +) broke later adds. A popup
         * left open is closed when the overlay shows again. */
    }
}

function handleMessage(msg) {
    switch (msg.type) {
    case 'window':
        windowRect = { x: msg.x, y: msg.y, w: msg.w, h: msg.h };
        wantVisible = !!msg.visible;
        applyWindow();
        break;
    case 'text':
        if (typeof msg.font === 'string' && msg.font.startsWith('hidden: ') && msg.font !== lastHiddenWhy) {
            writeLog('Memento: ' + msg.font);
        }
        lastHiddenWhy = msg.font;
        // falls through
    case 'debug':
        if (overlay) {
            overlay.webContents.send('memento', msg);
        }
        break;
    case 'openSettings':
        openSettings();
        break;
    case 'closePopup':
        closePopup();
        break;
    case 'quit':
        app.quit();
        break;
    }
}

function connect() {
    if (!port) {
        return;
    }
    socket = net.createConnection({ host: '127.0.0.1', port }, () => {
        send({ type: 'ready', extension: !!extension, version: extension ? extension.version : '' });
    });
    socket.setEncoding('utf8');
    socket.on('data', chunk => {
        inbuf += chunk;
        let nl;
        while ((nl = inbuf.indexOf('\n')) >= 0) {
            const line = inbuf.slice(0, nl);
            inbuf = inbuf.slice(nl + 1);
            if (!line.trim()) {
                continue;
            }
            try {
                handleMessage(JSON.parse(line));
            } catch (e) {
                /* ignore malformed lines */
            }
        }
    });
    /* Memento closed or crashed: nothing left to overlay */
    socket.on('close', () => app.quit());
    socket.on('error', () => app.quit());
}

function openSettings() {
    if (!extension) {
        return;
    }
    if (settingsWindow && !settingsWindow.isDestroyed()) {
        settingsWindow.show();
        settingsWindow.focus();
        return;
    }
    settingsWindow = new BrowserWindow({
        width: 1100,
        height: 850,
        title: 'Yomitan Settings',
        autoHideMenuBar: true,
        backgroundColor: '#1e1e1e',
        webPreferences: { contextIsolation: true }
    });
    settingsWindow.removeMenu();
    settingsWindow.loadURL(`chrome-extension://${extension.id}/settings.html`);
    settingsWindow.on('closed', () => { settingsWindow = null; });
    /* Electron sometimes leaves this window blank until it is resized
     * (GSM's overlay does the same nudge): force a repaint */
    const repaint = () => {
        if (!settingsWindow || settingsWindow.isDestroyed()) {
            return;
        }
        const [w, h] = settingsWindow.getSize();
        settingsWindow.setSize(w + 1, h);
        settingsWindow.setSize(w, h);
        settingsWindow.webContents.invalidate();
    };
    settingsWindow.webContents.on('did-finish-load', () => setTimeout(repaint, 300));
    setTimeout(repaint, 800);
    setTimeout(repaint, 2000);
}

/* Notes Yomitan adds go to AnkiConnect over HTTP. Watching the request lets
 * Memento add the audio and picture to exactly that note afterwards. */
const pendingNotes = new Map();

function readBody(details) {
    if (!details.uploadData) {
        return null;
    }
    try {
        const text = details.uploadData
            .map(part => part.bytes ? Buffer.from(part.bytes).toString('utf8') : '')
            .join('');
        return JSON.parse(text);
    } catch (e) {
        return null;
    }
}

function addedNotes(body) {
    if (!body || typeof body !== 'object') {
        return [];
    }
    const params = body.params || {};
    if (body.action === 'addNote' && params.note) {
        return [params.note];
    }
    if (body.action === 'addNotes' && Array.isArray(params.notes)) {
        return params.notes;
    }
    if (body.action === 'multi' && Array.isArray(params.actions)) {
        return params.actions.flatMap(addedNotes);
    }
    return [];
}

function watchAnki() {
    const filter = { urls: ['http://*/*', 'https://*/*'] };
    session.defaultSession.webRequest.onBeforeRequest(filter, (details, callback) => {
        if (!/127\.0\.0\.1:8765|localhost:8765/.test(details.url)) {
            writeLog('Request ' + details.method + ' ' + details.url.slice(0, 120));
        }
        if (details.method === 'POST') {
            const body = readBody(details);
            if (body && body.action && body.action !== 'version') {
                writeLog('AnkiConnect ' + body.action);
            }
            const notes = addedNotes(body);
            if (notes.length > 0) {
                pendingNotes.set(details.id, { time: Date.now(), notes });
            }
        }
        callback({});
    });
    session.defaultSession.webRequest.onCompleted(filter, details => {
        const pending = pendingNotes.get(details.id);
        if (!pending) {
            return;
        }
        pendingNotes.delete(details.id);
        writeLog('AnkiConnect addNote finished, HTTP ' + details.statusCode);
        if (details.statusCode !== 200) {
            return;
        }
        const note = pending.notes[pending.notes.length - 1];
        writeLog('Yomitan added a note');
        send({
            type: 'noteAdded',
            time: pending.time,
            deck: note.deckName || '',
            model: note.modelName || '',
            fields: note.fields || {}
        });
    });
    session.defaultSession.webRequest.onErrorOccurred(filter, details => {
        writeLog('Request failed: ' + details.error + ' ' + details.url.slice(0, 120));
        if (pendingNotes.has(details.id)) {
            writeLog('AnkiConnect addNote failed: ' + details.error);
        }
        pendingNotes.delete(details.id);
    });
}

/* Click-through except over the text and the popup. The page decides what
 * is under the cursor; the cursor position comes from here so it also
 * works while the window ignores the mouse. */
function pollCursor() {
    if (!overlay || !overlay.isVisible() || !windowRect) {
        return;
    }
    const p = screen.getCursorScreenPoint();
    const b = overlay.getBounds();
    const x = p.x - b.x;
    const y = p.y - b.y;
    const inside = x >= 0 && y >= 0 && x < b.width && y < b.height;
    const key = inside ? x + ',' + y : 'out';
    if (key === lastCursor) {
        return;
    }
    lastCursor = key;
    overlay.webContents.send('cursor', inside ? { x, y } : null);
}

function createOverlay() {
    overlay = new BrowserWindow({
        width: 800,
        height: 600,
        show: false,
        frame: false,
        transparent: true,
        backgroundColor: '#00000000',
        hasShadow: false,
        resizable: false,
        movable: false,
        minimizable: false,
        maximizable: false,
        fullscreenable: false,
        skipTaskbar: true,
        focusable: false,
        alwaysOnTop: true,
        title: 'Memento Yomitan Overlay',
        webPreferences: {
            preload: path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration: false,
            backgroundThrottling: false
        }
    });
    overlay.setIgnoreMouseEvents(true, { forward: true });
    overlay.setAlwaysOnTop(true, 'screen-saver');
    overlay.loadFile(path.join(__dirname, 'index.html'));
    overlay.webContents.on('input-event', (event, input) => {
        if (input.type === 'mouseDown' || input.type === 'mouseUp') {
            writeLog('Overlay got ' + input.type);
        }
    });
    overlay.webContents.on('did-finish-load', () => {
        lastCursor = '';
        if (popupOpen) {
            send({ type: 'popup', open: false });
        }
        popupOpen = false;
        ignoring = true;
        overlay.setIgnoreMouseEvents(true, { forward: true });
    });
    overlay.on('closed', () => { overlay = null; });
}

ipcMain.on('state', (_event, state) => {
    setIgnore(!state.interactive);
    /* on: over the text; popup: over something else of ours (the popup) */
    send({ type: 'hover', on: !!state.overText, popup: !!state.interactive && !state.overText });
});

ipcMain.on('log', (_event, message) => writeLog(`[page] ${message}`));

/* A fresh page (first load or after a reload) needs the text again */
ipcMain.on('loaded', () => send({ type: 'resend' }));

/* Close Yomitan's popup: a click on an empty spot of the page closes it the
 * way clicking elsewhere does; if it is still open, reload the page. */
function closePopup() {
    if (!overlay || !popupOpen) {
        return;
    }
    writeLog('Memento asked to close the popup');
    const wc = overlay.webContents;
    wc.sendInputEvent({ type: 'mouseDown', x: 0, y: 0, button: 'left', clickCount: 1 });
    wc.sendInputEvent({ type: 'mouseUp', x: 0, y: 0, button: 'left', clickCount: 1 });
    setTimeout(() => {
        if (overlay && popupOpen) {
            writeLog('Popup still open: reloading the page');
            overlay.webContents.reload();
        }
    }, 350);
}

ipcMain.on('popup', (_event, open) => {
    if (open && !popupOpen) {
        raiseOverlay();
    }
    popupOpen = !!open;
    send({ type: 'popup', open: popupOpen });
});

app.whenReady().then(async () => {
    writeLog(`Overlay start, Electron ${process.versions.electron}, port ${port}`);
    /* Yomitan's background (service worker) console */
    try {
        session.defaultSession.serviceWorkers.on('console-message', (_e, d) => {
            writeLog(`[worker] ${d.message} (${d.sourceUrl || ''}:${d.lineNumber || ''})`);
        });
    } catch (e) { /* older API */ }
    watchAnki();
    /* Chromium keeps the extension's background script cached across runs
     * (same version number = same cache), so a patched Yomitan file would
     * be ignored. Drop that cache before loading; Yomitan's own data
     * (dictionaries, settings) is in other storage and stays. */
    try {
        await session.defaultSession.clearStorageData({ storages: ['serviceworkers', 'cachestorage'] });
        await session.defaultSession.clearCodeCaches({});
    } catch (e) {
        writeLog('Could not clear the script cache: ' + e.message);
    }
    adoptOldYomitanSettings();
    extension = await loadYomitan();
    if (extension && extension.id !== YOMITAN_ID) {
        writeLog(`Yomitan ID is ${extension.id}, not the fixed one: its data depends on the install folder`);
    }
    createOverlay();
    connect();
    setInterval(pollCursor, 30);
    /* For testing without Memento */
    if (process.argv.includes('--open-settings')) {
        setTimeout(openSettings, 1500);
    }
});

/* Only Memento decides when this ends */
app.on('window-all-closed', () => {});

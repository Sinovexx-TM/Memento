'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('overlayBridge', {
    onMemento: callback => ipcRenderer.on('memento', (_e, msg) => callback(msg)),
    onCursor: callback => ipcRenderer.on('cursor', (_e, point) => callback(point)),
    state: state => ipcRenderer.send('state', state),
    popup: open => ipcRenderer.send('popup', open),
    loaded: () => ipcRenderer.send('loaded')
});

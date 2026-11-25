import QtQuick
import Ripose.Memento

import "../util/Library.js" as Library

/* Records the position of local videos in the watch history (every few
 * seconds, on leaving a file and on quitting). An episode counts as watched
 * from where the Toggl logger finds its end: the ending chapter, the last
 * dialogue line of an external subtitle, else a percentage. */
Item {
    id: root

    required property var player

    /* Seconds of wall time between saves while playing */
    readonly property int saveInterval: 10

    property string path: ""
    property real pos: 0
    property real duration: 0
    property bool done: false
    property double lastSave: 0
    /* End of the episode content; computed while playing, because after
     * a file change the player already describes the next file */
    property real endPoint: -1
    property double lastEndCheck: 0
    property bool resumePending: false

    function isLocal(path) {
        return path.length > 0 && !/^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(path.replace(/^file:/i, ""));
    }

    function checkEnd() {
        if (root.done || !(root.duration > 0) || root.pos < root.duration * 0.5) {
            return;
        }
        if (Date.now() - root.lastEndCheck >= 5000 || root.endPoint < 0) {
            root.endPoint = root.player.toggl.computeEnd();
            root.lastEndCheck = Date.now();
        }
        if (root.endPoint > 0 && root.pos >= root.endPoint - 1) {
            root.done = true;
            root.flush();
        }
    }

    function flush() {
        if (!root.isLocal(root.path)) {
            return;
        }
        /* A file opened and closed straight away is not "started" */
        if (!root.done && root.pos < Library.STARTED_SECONDS) {
            return;
        }
        WatchHistory.record(Library.key(root.path), root.done ? 0 : root.pos, root.duration, root.done);
        root.lastSave = Date.now();
    }

    /* Leaving the video for the Library, Anime list or manga: save where it
     * is, then unload it (Continue resumes from the saved position) */
    function leave() {
        if ((root.player.state.path ?? "").length === 0) {
            return;
        }
        root.flush();
        root.player.controller.stop();
    }

    function reset() {
        root.path = root.player.state.path ?? "";
        root.pos = 0;
        root.duration = 0;
        root.done = false;
        root.lastSave = Date.now();
        root.endPoint = -1;
        root.lastEndCheck = 0;
        root.resumePending = root.path.length > 0;
    }

    Component.onCompleted: root.reset()

    Connections {
        target: root.player.state

        function onPathChanged() {
            root.flush();
            root.reset();
        }

        function onTimePositionChanged() {
            const pos = root.player.state.timePosition;
            if (!(pos >= 0)) {
                return;
            }
            /* Opened outside the Library (Explorer, drag and drop): resume
             * from the watch history once, unless it already started later
             * (the Library passes its own start) */
            if (root.resumePending && root.player.state.duration > 0) {
                root.resumePending = false;
                const entry = root.isLocal(root.path) ? WatchHistory.entries()[Library.key(root.path)] : null;
                if (entry && !entry.done && entry.pos >= Library.STARTED_SECONDS &&
                        entry.pos < root.player.state.duration - 10 && pos < 5) {
                    root.player.controller.seek(Math.max(0, entry.pos - 3));
                    return;
                }
            }
            root.pos = pos;
            if (root.player.state.duration > 0) {
                root.duration = root.player.state.duration;
            }
            root.checkEnd();
            /* While paused the position only moves by seeking: save it at
             * once, or rewinding and then leaving would resume from the
             * position saved when pausing */
            if (root.player.state.pause || Date.now() - root.lastSave >= root.saveInterval * 1000) {
                root.flush();
            }
        }

        function onPauseChanged() {
            if (root.player.state.pause) {
                root.flush();
            }
        }
    }
}

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
        WatchHistory.record(Library.key(root.path), root.pos, root.duration, root.done);
        root.lastSave = Date.now();
    }

    function reset() {
        root.path = root.player.state.path ?? "";
        root.pos = 0;
        root.duration = 0;
        root.done = false;
        root.lastSave = Date.now();
        root.endPoint = -1;
        root.lastEndCheck = 0;
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
            root.pos = pos;
            if (root.player.state.duration > 0) {
                root.duration = root.player.state.duration;
            }
            root.checkEnd();
            if (Date.now() - root.lastSave >= root.saveInterval * 1000) {
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

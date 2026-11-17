import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ripose.Memento

/* Asks once per viewing whether to log the episode to Toggl when it ends.
 * End of episode: start of an "Ending"/"ED" chapter, else the end of the last
 * dialogue line of an external subtitle file, else a percentage of the length.
 * Switching file or quitting past the "late" percentage asks too. */
Item {
    id: root

    required property var player

    /* Called after the prompt closes when it was opened by quitting */
    property bool quitAfterPrompt: false

    /* Per-viewing state */
    property string path: ""
    property bool asked: false
    property real played: 0
    property real lastPos: -1
    property real maxPos: 0
    property real endPoint: -1
    property bool endDirty: true

    /* The file being watched; kept when the player has already moved on */
    property string viewTitle: ""
    property real viewDuration: 0

    function isActive() {
        return TogglClient.enabled && TogglClient.hasToken();
    }

    function resetViewing() {
        root.path = root.player.state.path ?? "";
        root.asked = false;
        root.played = 0;
        root.lastPos = -1;
        root.maxPos = 0;
        root.endDirty = true;
        root.viewTitle = root.player.state.title ?? "";
        root.viewDuration = root.player.state.duration > 0 ? root.player.state.duration : 0;
    }

    function isSongLine(text) {
        return /[♪♫♬]/.test(text);
    }

    function selectedTrackIsExternal() {
        const tracks = root.player.state.subtitleTracks;
        const sid = root.player.state.sid;
        for (let i = 0; i < tracks.length; ++i) {
            if (tracks[i].id === sid) {
                return tracks[i].external;
            }
        }
        return false;
    }

    function computeEnd() {
        const duration = root.player.state.duration;
        if (!(duration > 0)) {
            return -1;
        }

        /* 1. Ending chapter */
        const times = root.player.state.chapters;
        const titles = root.player.state.chapterTitles;
        for (let i = 0; i < times.length; ++i) {
            const title = (titles[i] ?? "").trim();
            if (times[i] > duration * 0.4 &&
                    (/^(ed|ending|credits?)\b/i.test(title) ||
                     /\b(ED|Ending)\b/.test(title) ||
                     title.includes("エンディング"))) {
                return times[i];
            }
        }

        /* 2. Last dialogue line; only an external file is complete in advance */
        const model = SubtitleLists.primary;
        if (model && root.selectedTrackIsExternal()) {
            let last = -1;
            const rows = model.rowCount();
            for (let r = 0; r < rows; ++r) {
                const index = model.index(r, 0);
                const text = model.data(index, SubtitleListModel.TextRole) ?? "";
                if (text.trim().length === 0 || root.isSongLine(text)) {
                    continue;
                }
                last = Math.max(last, model.data(index, SubtitleListModel.EndRole));
            }
            if (last > duration * 0.5 && last <= duration) {
                return last;
            }
        }

        /* 3. Fallback percentage */
        return duration * TogglClient.endFallbackPercent / 100;
    }

    function secondsToLog() {
        return Math.round(TogglClient.usePlayedTime ?
            root.played : root.viewDuration);
    }

    function label() {
        const info = Utils.parseMediaInfo(root.path, root.viewTitle);
        const show = info.title && info.title.length > 0 ? info.title : qsTr("this episode");
        return info.episode && info.episode.length > 0 ? `${show} E${info.episode}` : show;
    }

    function ask() {
        if (root.asked || !root.isActive()) {
            return false;
        }
        const seconds = root.secondsToLog();
        if (seconds <= 0) {
            return false;
        }
        root.asked = true;
        prompt.openFor(root.label(), seconds);
        return true;
    }

    /* Ask for the current file if it is far enough along. true = prompt shown. */
    function askIfLate() {
        const duration = root.viewDuration;
        if (root.asked || !root.isActive() || !(duration > 0)) {
            return false;
        }
        if (root.maxPos / duration * 100 >= TogglClient.lateAskPercent) {
            return root.ask();
        }
        return false;
    }

    /* For the main window: true when quitting must wait for the prompt */
    function askBeforeQuit() {
        if (root.askIfLate()) {
            root.quitAfterPrompt = true;
            return true;
        }
        return false;
    }

    Connections {
        target: root.player.state

        function onPathChanged() {
            /* Leaving an episode: the old file's numbers are still in place
             * until resetViewing(), so the prompt describes the old file. */
            if (prompt.visible) {
                root.resetViewing();
                return;
            }
            const leaving = root.path.length > 0 && root.askIfLate();
            if (leaving) {
                prompt.pendingReset = true;
            } else {
                root.resetViewing();
            }
        }

        function onTimePositionChanged() {
            if (prompt.pendingReset) {
                return;
            }
            const pos = root.player.state.timePosition;
            if (root.lastPos >= 0 && !root.player.state.pause) {
                const delta = pos - root.lastPos;
                if (delta > 0 && delta < 2) {
                    root.played += delta;
                }
            }
            root.lastPos = pos;
            root.maxPos = Math.max(root.maxPos, pos);
            if (root.player.state.duration > 0) {
                root.viewDuration = root.player.state.duration;
            }
            if ((root.player.state.title ?? "").length > 0) {
                root.viewTitle = root.player.state.title;
            }

            if (root.asked || !root.isActive()) {
                return;
            }
            if (root.endDirty) {
                root.endPoint = root.computeEnd();
                root.endDirty = false;
            }
            if (root.endPoint > 0 && pos >= root.endPoint) {
                root.ask();
            }
        }

        function onDurationChanged() { root.endDirty = true; }
        function onChaptersChanged() { root.endDirty = true; }
        function onSidChanged() { root.endDirty = true; }
    }

    Connections {
        target: SubtitleLists
        function onPrimaryChanged() { root.endDirty = true; }
    }

    Connections {
        target: SubtitleLists.primary
        ignoreUnknownSignals: true
        function onModelReset() { root.endDirty = true; }
        function onRowsInserted() { root.endDirty = true; }
    }

    Dialog {
        id: prompt

        property string episode: ""
        property int seconds: 0
        property bool editing: false
        property string error: ""
        property bool pendingReset: false

        function openFor(episode, seconds) {
            prompt.episode = episode;
            prompt.seconds = seconds;
            prompt.editing = false;
            prompt.error = "";
            prompt.open();
        }

        function send(seconds) {
            prompt.error = "";
            TogglClient.logEntry(seconds);
        }

        function finish() {
            prompt.close();
        }

        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.NoAutoClose
        title: qsTr("Toggl")
        onAboutToShow: Utils.modalDialogs += 1
        onClosed: {
            Utils.modalDialogs -= 1;
            if (prompt.pendingReset) {
                prompt.pendingReset = false;
                root.resetViewing();
            }
            if (root.quitAfterPrompt) {
                root.quitAfterPrompt = false;
                Qt.quit();
            }
        }

        Connections {
            target: TogglClient
            function onFinished(success, error) {
                if (!prompt.visible) {
                    return;
                }
                if (success) {
                    prompt.finish();
                } else {
                    prompt.error = error;
                }
            }
        }

        ColumnLayout {
            spacing: 10

            Label {
                text: qsTr("Log %1 (%2) to Toggl?")
                    .arg(prompt.episode)
                    .arg(Utils.toTimeString(prompt.seconds))
                font.bold: true
            }

            RowLayout {
                visible: prompt.editing
                Label { text: qsTr("Minutes") }
                SpinBox {
                    id: minutesBox
                    from: 1
                    to: 600
                    editable: true
                }
            }

            Label {
                visible: TogglClient.busy
                text: qsTr("Sending…")
            }

            Label {
                visible: prompt.error.length > 0
                Layout.maximumWidth: 420
                wrapMode: Label.WordWrap
                color: "#e06c6c"
                text: prompt.error + "\n" +
                      qsTr("The entry is kept and will be sent with the next one.")
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                enabled: !TogglClient.busy

                /* Normal state */
                Button {
                    visible: prompt.error.length === 0 && !prompt.editing
                    text: qsTr("Yes")
                    highlighted: true
                    onClicked: prompt.send(prompt.seconds)
                }
                Button {
                    visible: prompt.error.length === 0 && !prompt.editing
                    text: qsTr("Edit time")
                    onClicked: {
                        minutesBox.value = Math.max(1, Math.round(prompt.seconds / 60));
                        prompt.editing = true;
                    }
                }
                Button {
                    visible: prompt.error.length === 0 && prompt.editing
                    text: qsTr("Log")
                    highlighted: true
                    onClicked: prompt.send(minutesBox.value * 60)
                }
                Button {
                    visible: prompt.error.length === 0
                    text: qsTr("No")
                    onClicked: prompt.finish()
                }

                /* After a failed call */
                Button {
                    visible: prompt.error.length > 0
                    text: qsTr("Retry")
                    highlighted: true
                    onClicked: {
                        prompt.error = "";
                        TogglClient.retryPending();
                    }
                }
                Button {
                    visible: prompt.error.length > 0
                    text: qsTr("Later")
                    onClicked: prompt.finish()
                }
            }
        }
    }
}

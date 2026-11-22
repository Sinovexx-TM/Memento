import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ripose.Memento

import "../util/Mal.js" as Mal

/* Asks once per viewing whether to log the episode to Toggl and/or update
 * MyAnimeList when it ends.
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

    /* Opening chapter [start, end] and where the episode content ends
     * (start of the ending chapter or end of the last dialogue line);
     * -1 when not known. Kept from the last computeEnd() of this file. */
    property real opStart: -1
    property real opEnd: -1
    property real contentEnd: -1

    function isOpTitle(title) {
        return /^(op|opening)\b/i.test(title) || /\b(OP|Opening)\b/.test(title) ||
               title.includes("オープニング");
    }

    function isEdTitle(title) {
        return /^(ed|ending|credits?)\b/i.test(title) || /\b(ED|Ending)\b/.test(title) ||
               title.includes("エンディング");
    }

    function togglActive() {
        return TogglClient.enabled && TogglClient.hasToken();
    }

    function malActive() {
        return MalClient.enabled && MalClient.loggedIn;
    }

    /* The prompt is shown when Toggl or MyAnimeList is set up */
    function isActive() {
        return root.togglActive() || root.malActive();
    }

    function resetViewing() {
        root.path = root.player.state.path ?? "";
        root.asked = false;
        root.played = 0;
        root.lastPos = -1;
        root.maxPos = 0;
        root.endDirty = true;
        root.opStart = -1;
        root.opEnd = -1;
        root.contentEnd = -1;
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

        /* Chapters. Named OP/ED chapters win; otherwise an opening or ending
         * song is a chapter of 80-100 s (releases often name them "Chapter 02"
         * or "A90Sec"): the first one in the first 40 % is the OP, the last
         * one after the halfway point is the ED. */
        const times = root.player.state.chapters;
        const titles = root.player.state.chapterTitles;
        const chapterEnd = i => i + 1 < times.length ? times[i + 1] : duration;
        const songLength = i => {
            const length = chapterEnd(i) - times[i];
            return length >= 80 && length <= 100;
        };
        root.opStart = -1;
        root.opEnd = -1;
        root.contentEnd = -1;

        let op = -1;
        let ed = -1;
        for (let i = 0; i < times.length; ++i) {
            const title = (titles[i] ?? "").trim();
            if (op < 0 && times[i] < duration * 0.4 && root.isOpTitle(title)) {
                op = i;
            }
            if (ed < 0 && times[i] > duration * 0.4 && root.isEdTitle(title)) {
                ed = i;
            }
        }
        if (op < 0) {
            for (let i = 0; i < times.length; ++i) {
                if (times[i] < duration * 0.4 && songLength(i)) {
                    op = i;
                    break;
                }
            }
        }
        if (ed < 0) {
            for (let i = times.length - 1; i >= 0; --i) {
                if (times[i] > duration * 0.5 && i !== op && songLength(i)) {
                    ed = i;
                    break;
                }
            }
        }
        if (op >= 0) {
            root.opStart = times[op];
            root.opEnd = chapterEnd(op);
        }

        /* 1. Ending chapter */
        if (ed >= 0) {
            root.contentEnd = times[ed];
            return times[ed];
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
                root.contentEnd = last;
                return last;
            }
        }

        /* 3. Fallback percentage */
        return duration * TogglClient.endFallbackPercent / 100;
    }

    /* Full mode: the episode without the opening and without everything
     * from the ending on (when chapters or a subtitle file show where they
     * are). Played mode: time played outside those parts. */
    function secondsToLog() {
        if (TogglClient.usePlayedTime) {
            return Math.round(root.played);
        }
        let seconds = root.contentEnd > 0 ? root.contentEnd : root.viewDuration;
        if (root.opStart >= 0 && root.opEnd > root.opStart && root.opEnd <= seconds) {
            seconds -= root.opEnd - root.opStart;
        }
        return Math.round(seconds);
    }

    function countsAsWatched(pos) {
        if (root.opStart >= 0 && pos >= root.opStart && pos < root.opEnd) {
            return false;
        }
        return !(root.contentEnd > 0 && pos >= root.contentEnd);
    }

    /* Show and episode for the Toggl description: "Show", "9" (or "SP1") */
    function labelParts() {
        const info = Utils.parseMediaInfo(root.path, root.viewTitle);
        const show = info.title && info.title.length > 0 ? info.title : "";
        const episode = (info.episode ?? "").trim();
        const number = episode.match(/^(?:episode\s*)?(\d+(?:\.\d+)?)$/i);
        return { show: show, episode: number ? number[1] : episode };
    }

    function label() {
        const info = Utils.parseMediaInfo(root.path, root.viewTitle);
        const show = info.title && info.title.length > 0 ? info.title : qsTr("this episode");
        const episode = (info.episode ?? "").trim();
        if (episode.length === 0) {
            return show;
        }
        /* parseMediaInfo gives "Episode 9" (or a bare "9"): show it as E9 */
        const number = episode.match(/^(?:episode\s*)?(\d+(?:\.\d+)?)$/i);
        return number ? `${show} E${number[1]}` : `${show} ${episode}`;
    }

    function ask() {
        if (root.asked || !root.isActive()) {
            return false;
        }
        const seconds = root.secondsToLog();
        if (seconds <= 0 && !root.malActive()) {
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

    /* Controller buttons while the prompt is open: A = Log (Retry after a
     * failure), B = Skip (Later), X / Y = tick or untick Toggl / MAL.
     * Returns true when the prompt is open, so the player ignores the press. */
    function handleGamepad(name) {
        if (!prompt.opened)
            return false;
        if (prompt.sending)
            return true;
        if (name === "a") {
            if (prompt.failed)
                prompt.retry();
            else if ((prompt.togglShown && togglCheck.checked) ||
                     (prompt.malShown && malCheck.checked && malCheck.enabled))
                prompt.send();
        } else if (name === "b") {
            prompt.finish();
        } else if (name === "x" && prompt.togglShown && !prompt.failed) {
            togglCheck.checked = !togglCheck.checked;
        } else if (name === "y" && prompt.malShown && malCheck.enabled && !prompt.failed) {
            malCheck.checked = !malCheck.checked;
        }
        return true;
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
                if (delta > 0 && delta < 2 && root.countsAsWatched(pos)) {
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

    MalPicker {
        id: malPicker
        onPicked: prompt.computeMal()
    }

    /* End-of-episode prompt: a Toggl row and a MyAnimeList row, each with a
     * tick box. Log sends what is ticked, Skip sends nothing. */
    Dialog {
        id: prompt

        property string episode: ""
        property int seconds: 0
        property bool editing: false
        property bool pendingReset: false

        /* Toggl */
        property bool togglShown: false
        property bool waitToggl: false
        property string togglError: ""

        /* MyAnimeList */
        property bool malShown: false
        property var malList: []
        property var mal: null
        property bool waitMal: false
        property string malError: ""
        property bool malLoading: false

        readonly property bool sending: prompt.waitToggl || prompt.waitMal
        readonly property bool failed: prompt.togglError.length > 0 || prompt.malError.length > 0

        function openFor(episode, seconds) {
            prompt.episode = episode;
            prompt.seconds = seconds;
            prompt.editing = false;
            prompt.togglError = "";
            prompt.malError = "";
            prompt.waitToggl = false;
            prompt.waitMal = false;
            prompt.togglShown = root.togglActive() && seconds > 0;
            prompt.malShown = root.malActive();
            togglCheck.checked = prompt.togglShown;
            prompt.mal = null;
            if (prompt.malShown) {
                prompt.malList = MalClient.cachedList();
                prompt.computeMal();
                prompt.malLoading = true;
                MalClient.fetchList();
            }
            prompt.open();
        }

        /* Which MAL entry this file is and what would be sent */
        function computeMal() {
            const info = Utils.parseMediaInfo(root.path, root.viewTitle);
            const show = (info.title ?? "").trim();
            const season = Mal.seasonOf(root.path);
            const fileEp = Mal.episodeOf(root.path);
            const key = Mal.matchKey(show, season);
            const saved = MalClient.matches()[key];

            let entry = null;
            let offset = 0;
            if (saved) {
                offset = saved.offset ?? 0;
                entry = Mal.findEntry(prompt.malList, saved.id) ??
                    { id: saved.id, title: saved.title, status: "", watched: 0, episodes: saved.episodes ?? 0 };
            } else {
                entry = Mal.autoMatch(show, season, prompt.malList);
            }
            const ep = fileEp === null || fileEp - offset < 1 ? null : fileEp - offset;
            const plan = entry ? Mal.planUpdate(entry, ep, Mal.today()) : null;
            prompt.mal = {
                show: show,
                season: season,
                key: key,
                entry: entry,
                saved: !!saved,
                offset: offset,
                plan: plan
            };
            malCheck.checked = plan !== null && plan.change;
        }

        function malText() {
            const m = prompt.mal;
            if (!m) {
                return "";
            }
            if (m.show.length === 0) {
                return qsTr("can't tell the show from the file name");
            }
            if (!m.entry) {
                const what = m.season > 1 ? qsTr("%1 (season %2)").arg(m.show).arg(m.season) : m.show;
                return prompt.malLoading ? qsTr("looking for %1 on your list…").arg(what) :
                                           qsTr("no match for %1, pick the show").arg(what);
            }
            if (!m.plan.change) {
                return `${m.entry.title} · ${m.plan.note}`;
            }
            let text = qsTr("%1 · Episodes %2 → %3").arg(m.entry.title).arg(m.plan.from).arg(m.plan.to);
            if (m.plan.statusChanged) {
                text += " · " + (Mal.STATUS_LABELS[m.plan.status] ?? m.plan.status);
            }
            return text;
        }

        function send() {
            prompt.togglError = "";
            prompt.malError = "";
            const doToggl = prompt.togglShown && togglCheck.checked;
            const doMal = prompt.malShown && malCheck.checked && prompt.mal && prompt.mal.plan &&
                          prompt.mal.plan.change;
            if (!doToggl && !doMal) {
                prompt.finish();
                return;
            }
            if (doMal) {
                const m = prompt.mal;
                /* Remember the show -> entry pairing once it has been used */
                if (!m.saved) {
                    MalClient.setMatch(m.key, {
                        id: m.entry.id, title: m.entry.title, offset: 0,
                        episodes: m.entry.episodes ?? 0, show: m.show, season: m.season
                    });
                }
                prompt.waitMal = true;
                MalClient.updateEntry(m.entry.id, m.entry.title, m.plan.fields);
            }
            if (doToggl) {
                prompt.waitToggl = true;
                const parts = root.labelParts();
                TogglClient.logEntry(prompt.editing ? minutesBox.value * 60 : prompt.seconds,
                                     parts.show, parts.episode);
            }
        }

        function retry() {
            if (prompt.togglError.length > 0) {
                prompt.togglError = "";
                prompt.waitToggl = true;
                TogglClient.retryPending();
            }
            if (prompt.malError.length > 0) {
                prompt.malError = "";
                prompt.waitMal = true;
                MalClient.retryPending();
            }
        }

        function checkDone() {
            if (!prompt.sending && !prompt.failed) {
                prompt.finish();
            }
        }

        function finish() {
            prompt.close();
        }

        parent: Overlay.overlay
        anchors.centerIn: parent
        modal: true
        closePolicy: Popup.NoAutoClose
        title: qsTr("Finished %1").arg(prompt.episode)
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
                if (!prompt.visible || !prompt.waitToggl) {
                    return;
                }
                prompt.waitToggl = false;
                if (!success) {
                    prompt.togglError = error;
                }
                prompt.checkDone();
            }
        }

        Connections {
            target: MalClient
            function onUpdateFinished(success, error) {
                if (!prompt.visible || !prompt.waitMal) {
                    return;
                }
                prompt.waitMal = false;
                if (!success) {
                    prompt.malError = error;
                }
                prompt.checkDone();
            }
            function onListReady(success, entries, error) {
                if (!prompt.visible || !prompt.malShown) {
                    return;
                }
                prompt.malLoading = false;
                if (success) {
                    prompt.malList = entries;
                }
                if (!prompt.sending && !prompt.failed) {
                    prompt.computeMal();
                }
            }
        }

        ColumnLayout {
            spacing: 10

            /* Toggl row */
            RowLayout {
                visible: prompt.togglShown
                spacing: 8

                CheckBox {
                    id: togglCheck
                    enabled: !prompt.sending
                    text: qsTr("Toggl: log %1").arg(Utils.toTimeString(
                        prompt.editing ? minutesBox.value * 60 : prompt.seconds))
                }
                SpinBox {
                    id: minutesBox
                    visible: prompt.editing
                    from: 1
                    to: 600
                    editable: true
                }
                Label {
                    visible: prompt.editing
                    text: qsTr("min")
                }
                Button {
                    visible: !prompt.editing
                    enabled: !prompt.sending
                    text: qsTr("Edit time")
                    onClicked: {
                        minutesBox.value = Math.max(1, Math.round(prompt.seconds / 60));
                        prompt.editing = true;
                    }
                }
            }

            /* MyAnimeList row */
            RowLayout {
                visible: prompt.malShown
                spacing: 8

                CheckBox {
                    id: malCheck
                    Layout.maximumWidth: 520
                    enabled: !prompt.sending && prompt.mal !== null && prompt.mal.plan !== null &&
                             prompt.mal.plan.change
                    text: qsTr("MyAnimeList: %1").arg(prompt.malText())
                }
                Button {
                    enabled: !prompt.sending && prompt.mal !== null && prompt.mal.show.length > 0
                    text: prompt.mal && prompt.mal.entry ? qsTr("Change match") : qsTr("Pick show")
                    onClicked: malPicker.openFor(prompt.mal.key, prompt.mal.show, prompt.mal.season,
                                                 prompt.malList, MalClient.matches()[prompt.mal.key])
                }
            }

            Label {
                visible: prompt.sending
                text: qsTr("Sending…")
            }

            Label {
                visible: prompt.togglError.length > 0
                Layout.maximumWidth: 520
                wrapMode: Label.WordWrap
                color: "#e06c6c"
                text: qsTr("Toggl: %1").arg(prompt.togglError) + "\n" +
                      qsTr("The entry is kept and will be sent with the next one.")
            }

            Label {
                visible: prompt.malError.length > 0
                Layout.maximumWidth: 520
                wrapMode: Label.WordWrap
                color: "#e06c6c"
                text: qsTr("MyAnimeList: %1").arg(prompt.malError) + "\n" +
                      qsTr("The update is kept and will be sent with the next one.")
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                enabled: !prompt.sending

                /* Normal state */
                Button {
                    visible: !prompt.failed
                    text: qsTr("Log")
                    highlighted: true
                    enabled: (prompt.togglShown && togglCheck.checked) ||
                             (prompt.malShown && malCheck.checked && malCheck.enabled)
                    onClicked: prompt.send()
                }
                Button {
                    visible: !prompt.failed
                    text: qsTr("Skip")
                    onClicked: prompt.finish()
                }

                /* After a failed call */
                Button {
                    visible: prompt.failed
                    text: qsTr("Retry")
                    highlighted: true
                    onClicked: prompt.retry()
                }
                Button {
                    visible: prompt.failed
                    text: qsTr("Later")
                    onClicked: prompt.finish()
                }
            }
        }
    }
}

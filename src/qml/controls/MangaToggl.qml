import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ripose.Memento

import "../util/Manga.js" as Manga

/* Offers to log a finished manga reading session to Toggl. Also picks up a
 * session that was never closed (app closed or crashed while reading) the
 * next time Memento starts. */
Dialog {
    id: root

    property var session: null
    property string error: ""
    /* Sent once; a failed entry stays queued in Toggl's pending file */
    property bool sent: false
    property var waiting: []

    readonly property string template: String(WatchHistory.option("manga-toggl-description", "{show} {volume}"))
    readonly property string project: String(WatchHistory.option("manga-toggl-project", ""))

    function togglReady() {
        return TogglClient.enabled && TogglClient.hasToken();
    }

    function ask(session) {
        if (!root.togglReady() || !session) {
            return;
        }
        if (root.visible) {
            root.waiting.push(session);
            return;
        }
        root.session = session;
        root.error = "";
        root.sent = false;
        minutes.value = Math.max(1, Math.round(session.seconds / 60));
        root.open();
    }

    function next() {
        if (root.waiting.length > 0) {
            const s = root.waiting.shift();
            Qt.callLater(root.ask, s);
        }
    }

    /* A session left open by closing the app while reading */
    Timer {
        interval: 2500
        running: true
        onTriggered: {
            const open = MangaLibrary.openSession();
            if (open && open.start) {
                const s = {
                    start: open.start, end: open.end, seconds: open.seconds, chars: open.chars,
                    pages: open.pages, series: open.series, volume: open.volume
                };
                if (MangaLibrary.finishSession(s)) {
                    root.ask(s);
                }
            }
        }
    }

    Connections {
        target: TogglClient
        enabled: root.visible
        function onFinished(success, error) {
            if (success) {
                root.close();
                root.next();
            } else {
                root.error = error;
            }
        }
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent.width - 40, 460)
    modal: true
    closePolicy: Popup.NoAutoClose
    title: qsTr("Log manga reading to Toggl?")

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Label {
            Layout.fillWidth: true
            wrapMode: Label.WordWrap
            text: root.session ?
                Manga.describe(root.template, root.session.series, root.session.volume) + "\n" +
                qsTr("%1 pages · %2 chars · %3 (%4)")
                    .arg(root.session.pages).arg(root.session.chars)
                    .arg(Manga.formatMinutes(root.session.seconds))
                    .arg(new Date(root.session.end).toLocaleString(Qt.locale(), Locale.ShortFormat)) : ""
        }
        RowLayout {
            Label {
                text: qsTr("Minutes")
            }
            SpinBox {
                id: minutes
                from: 1
                to: 1440
                editable: true
            }
        }
        Label {
            Layout.fillWidth: true
            visible: root.error.length > 0
            wrapMode: Label.WordWrap
            color: "#e06c6c"
            text: root.error
        }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            Button {
                text: root.sent ? qsTr("Later") : qsTr("Skip")
                enabled: !TogglClient.busy
                onClicked: {
                    root.close();
                    root.next();
                }
            }
            Button {
                text: root.error.length > 0 ? qsTr("Retry") : qsTr("Log")
                highlighted: true
                enabled: !TogglClient.busy
                onClicked: {
                    root.error = "";
                    if (root.sent) {
                        TogglClient.retryPending();
                        return;
                    }
                    root.sent = true;
                    TogglClient.logCustom(
                        minutes.value * 60,
                        Manga.describe(root.template, root.session.series, root.session.volume),
                        root.project,
                        root.session.end);
                }
            }
        }
    }
}

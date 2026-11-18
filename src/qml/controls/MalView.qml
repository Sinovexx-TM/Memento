import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ripose.Memento

import "../util/Mal.js" as Mal

/* Your MyAnimeList list inside Memento: episode −/+1 and status changes go
 * straight to MAL. Covers the player while open. */
Rectangle {
    id: root

    required property var player

    property var list: []
    property string filter: "watching"
    property string error: ""
    property bool loading: false
    /* Opened from the Library: closing goes back there */
    property bool fromLibrary: false

    readonly property bool hasFile: (root.player.state.path ?? "").length > 0
    readonly property var shown: root.list
        .filter(e => e.onList !== false && (root.filter === "all" || e.status === root.filter))
        .sort((a, b) => a.title.localeCompare(b.title, undefined, { sensitivity: "base" }))

    visible: false
    color: "#141414"

    function open(fromLibrary) {
        root.fromLibrary = !!fromLibrary;
        root.list = MalClient.cachedList();
        root.visible = true;
        root.forceActiveFocus();
        if (root.hasFile && !root.player.state.pause) {
            root.player.controller.pause();
        }
        root.reload();
    }

    function close() {
        root.visible = false;
        if (root.fromLibrary || !root.hasFile) {
            root.fromLibrary = false;
            root.player.library.open();
        } else {
            root.player.forceActiveFocus();
        }
    }

    function toLibrary() {
        root.fromLibrary = false;
        root.visible = false;
        root.player.library.open();
    }

    function reload() {
        if (!MalClient.loggedIn) {
            root.error = qsTr("Not logged in. Settings > Behavior > MyAnimeList.");
            return;
        }
        root.loading = true;
        root.error = "";
        MalClient.fetchList();
    }

    function send(entry, fields) {
        root.error = "";
        MalClient.updateEntry(entry.id, entry.title, fields);
    }

    Connections {
        target: MalClient
        function onListReady(success, entries, error) {
            root.loading = false;
            if (success || root.list.length === 0) {
                root.list = entries;
            }
            if (!success && root.visible) {
                root.error = error;
            }
        }
        function onEntryUpdated(animeId) {
            if (root.visible) {
                root.list = MalClient.cachedList();
            }
        }
        function onUpdateFinished(success, error) {
            if (root.visible && !success) {
                root.error = error + " " + qsTr("(kept, press Retry)");
            }
        }
    }

    Keys.onEscapePressed: root.close()

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.ArrowCursor
        onWheel: wheel => wheel.accepted = true
    }

    ColumnLayout {
        anchors {
            fill: parent
            leftMargin: 40
            rightMargin: 40
            topMargin: 18
            bottomMargin: 12
        }
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            BackArrow {
                tip: root.fromLibrary || !root.hasFile ? qsTr("Back to Library") : qsTr("Back to video")
                onClicked: root.close()
            }
            Text {
                text: qsTr("Anime list")
                color: "#f2f2f2"
                font.pixelSize: 26
                font.bold: true
            }
            Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                bottomPadding: 4
                text: MalClient.userName + (root.loading ? "  ·  " + qsTr("loading…") : "") +
                      (MalClient.busy ? "  ·  " + qsTr("sending…") : "") +
                      (MalClient.pendingCount > 0 && !MalClient.busy ?
                           "  ·  " + qsTr("%1 waiting").arg(MalClient.pendingCount) : "")
                color: "#6e6e6e"
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            PageButton {
                visible: MalClient.pendingCount > 0 && !MalClient.busy
                text: qsTr("Retry")
                onClicked: { root.error = ""; MalClient.retryPending(); }
            }
            PageButton {
                text: qsTr("Refresh")
                onClicked: root.reload()
            }
            PageButton {
                text: qsTr("Open MAL")
                onClicked: MalClient.openUrl("https://myanimelist.net/animelist/" + MalClient.userName)
            }
            PageButton {
                visible: !root.fromLibrary
                text: qsTr("Library")
                onClicked: root.toLibrary()
            }
            PageButton {
                text: qsTr("Settings")
                onClicked: root.player.openOptions()
            }
        }

        Row {
            spacing: 8
            Repeater {
                model: [
                    { key: "watching", label: qsTr("Watching") },
                    { key: "plan_to_watch", label: qsTr("Plan to Watch") },
                    { key: "on_hold", label: qsTr("On Hold") },
                    { key: "completed", label: qsTr("Completed") },
                    { key: "dropped", label: qsTr("Dropped") },
                    { key: "all", label: qsTr("All") }
                ]
                delegate: PageButton {
                    required property var modelData
                    active: root.filter === modelData.key
                    text: modelData.label + " " +
                          (modelData.key === "all" ? root.list.filter(e => e.onList !== false).length :
                           root.list.filter(e => e.status === modelData.key).length)
                    onClicked: root.filter = modelData.key
                }
            }
        }

        Text {
            visible: root.error.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: "#e06c6c"
            text: root.error
        }

        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.shown
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property var entry: modelData

                width: listView.width - 12
                height: 70
                radius: 6
                color: rowHover.hovered ? "#2b2b2b" : "#1f1f1f"

                HoverHandler {
                    id: rowHover
                }

                MalCover {
                    id: rowCover
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 6
                    }
                    kind: "anime"
                    entryId: row.entry.id
                    picture: row.entry.picture ?? ""
                }

                ColumnLayout {
                    anchors {
                        left: rowCover.right
                        right: controlsRow.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                        rightMargin: 16
                    }
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: row.entry.title
                        color: "#f2f2f2"
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: [row.entry.ja, Mal.STATUS_LABELS[row.entry.status] ?? ""]
                            .filter(x => x && x.length > 0).join("  ·  ")
                        color: "#a3a3a3"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: controlsRow
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 12
                    }
                    spacing: 8

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 80
                        horizontalAlignment: Text.AlignRight
                        text: row.entry.watched + " / " + (row.entry.episodes > 0 ? row.entry.episodes : "?")
                        color: "#f2f2f2"
                        font.pixelSize: 15
                    }
                    PageButton {
                        text: "−"
                        enabled: row.entry.watched > 0 && !MalClient.busy
                        onClicked: root.send(row.entry, Mal.manualCount(row.entry, row.entry.watched - 1, Mal.today()))
                    }
                    PageButton {
                        text: "+1"
                        active: true
                        enabled: !MalClient.busy &&
                                 (row.entry.episodes === 0 || row.entry.watched < row.entry.episodes)
                        onClicked: root.send(row.entry, Mal.manualCount(row.entry, row.entry.watched + 1, Mal.today()))
                    }
                    PageButton {
                        text: qsTr("Status ▾")
                        enabled: !MalClient.busy
                        onClicked: statusMenu.openFor(row.entry)
                    }
                    PageButton {
                        text: "↗"
                        onClicked: MalClient.openUrl("https://myanimelist.net/anime/" + row.entry.id)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.shown.length === 0 && !root.loading
                text: qsTr("Nothing here.")
                color: "#6e6e6e"
                font.pixelSize: 15
            }
        }
    }

    DarkMenu {
        id: statusMenu
        property var entry: null

        function openFor(entry) {
            statusMenu.entry = entry;
            statusMenu.popup();
        }

        function set(status) {
            const e = statusMenu.entry;
            const fields = { status: status };
            if (status === "completed" && e.episodes > 0) {
                fields.num_watched_episodes = e.episodes;
            }
            if (status === "completed" && !e.finishDate) {
                fields.finish_date = Mal.today();
            }
            if (status === "watching" && !e.startDate) {
                fields.start_date = Mal.today();
            }
            root.send(e, fields);
        }

        Action { text: qsTr("Watching"); onTriggered: statusMenu.set("watching") }
        Action { text: qsTr("Completed"); onTriggered: statusMenu.set("completed") }
        Action { text: qsTr("On Hold"); onTriggered: statusMenu.set("on_hold") }
        Action { text: qsTr("Dropped"); onTriggered: statusMenu.set("dropped") }
        Action { text: qsTr("Plan to Watch"); onTriggered: statusMenu.set("plan_to_watch") }
    }
}

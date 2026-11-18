import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ripose.Memento

import "../util/Mal.js" as Mal

/* Your MyAnimeList manga list: chapter and volume −/+1 and status changes go
 * straight to MAL (same login and retry queue as the anime list). Nothing is
 * logged automatically while reading. Opened from the Manga page. */
Rectangle {
    id: root

    required property var player

    property var list: []
    property string filter: "reading"
    property string error: ""
    property bool loading: false

    readonly property var shown: root.list
        .filter(e => e.onList !== false && (root.filter === "all" || e.status === root.filter))
        .sort((a, b) => a.title.localeCompare(b.title, undefined, { sensitivity: "base" }))

    visible: false
    color: "#141414"

    function open() {
        root.list = MalClient.cachedMangaList();
        root.visible = true;
        root.forceActiveFocus();
        root.reload();
    }

    function close() {
        root.visible = false;
        root.player.mangaView.show();
    }

    function reload() {
        if (!MalClient.loggedIn) {
            root.error = qsTr("Not logged in. Settings > Behavior > MyAnimeList.");
            return;
        }
        root.loading = true;
        root.error = "";
        MalClient.fetchMangaList();
    }

    function send(entry, fields) {
        root.error = "";
        MalClient.updateMangaEntry(entry.id, entry.title, fields);
    }

    Connections {
        target: MalClient
        function onMangaListReady(success, entries, error) {
            root.loading = false;
            if (success || root.list.length === 0) {
                root.list = entries;
            }
            if (!success && root.visible) {
                root.error = error;
            }
        }
        function onMangaEntryUpdated(mangaId) {
            if (root.visible) {
                root.list = MalClient.cachedMangaList();
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

    /* "Ch 12 / 83  −  +1" */
    component Counter: Row {
        id: counter
        property string label: ""
        property int value: 0
        property int total: 0
        signal step(int count)
        spacing: 8

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 92
            horizontalAlignment: Text.AlignRight
            textFormat: Text.StyledText
            text: "<font color='#6e6e6e'>" + counter.label + "</font>  " +
                  counter.value + " / " + (counter.total > 0 ? counter.total : "?")
            color: "#f2f2f2"
            font.pixelSize: 15
        }
        PageButton {
            text: "−"
            enabled: counter.value > 0 && !MalClient.busy
            onClicked: counter.step(counter.value - 1)
        }
        PageButton {
            text: "+1"
            active: true
            enabled: !MalClient.busy && (counter.total === 0 || counter.value < counter.total)
            onClicked: counter.step(counter.value + 1)
        }
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
                tip: qsTr("Back to Manga")
                onClicked: root.close()
            }
            Text {
                text: qsTr("Manga list")
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
                onClicked: MalClient.openUrl("https://myanimelist.net/mangalist/" + MalClient.userName)
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
                    { key: "reading", label: qsTr("Reading") },
                    { key: "plan_to_read", label: qsTr("Plan to Read") },
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
                height: 58
                radius: 6
                color: rowHover.hovered ? "#2b2b2b" : "#1f1f1f"

                HoverHandler {
                    id: rowHover
                }

                ColumnLayout {
                    anchors {
                        left: parent.left
                        right: controlsRow.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 16
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
                        text: [row.entry.ja, Mal.MANGA_STATUS_LABELS[row.entry.status] ?? ""]
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
                    spacing: 16

                    Counter {
                        label: qsTr("Ch")
                        value: row.entry.chaptersRead
                        total: row.entry.chapters
                        onStep: count => root.send(row.entry, Mal.mangaCount(row.entry, "chapters", count, Mal.today()))
                    }
                    Counter {
                        label: qsTr("Vol")
                        value: row.entry.volumesRead
                        total: row.entry.volumes
                        onStep: count => root.send(row.entry, Mal.mangaCount(row.entry, "volumes", count, Mal.today()))
                    }
                    Row {
                        spacing: 8
                        PageButton {
                            text: qsTr("Status ▾")
                            enabled: !MalClient.busy
                            onClicked: statusMenu.openFor(row.entry)
                        }
                        PageButton {
                            text: "↗"
                            onClicked: MalClient.openUrl("https://myanimelist.net/manga/" + row.entry.id)
                        }
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
            if (status === "completed") {
                if (e.chapters > 0) {
                    fields.num_chapters_read = e.chapters;
                }
                if (e.volumes > 0) {
                    fields.num_volumes_read = e.volumes;
                }
                if (!e.finishDate) {
                    fields.finish_date = Mal.today();
                }
            }
            if (status === "reading" && !e.startDate) {
                fields.start_date = Mal.today();
            }
            root.send(e, fields);
        }

        Action { text: qsTr("Reading"); onTriggered: statusMenu.set("reading") }
        Action { text: qsTr("Completed"); onTriggered: statusMenu.set("completed") }
        Action { text: qsTr("On Hold"); onTriggered: statusMenu.set("on_hold") }
        Action { text: qsTr("Dropped"); onTriggered: statusMenu.set("dropped") }
        Action { text: qsTr("Plan to Read"); onTriggered: statusMenu.set("plan_to_read") }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Ripose.Memento

import "../util/Manga.js" as Manga

/* The manga half of the Library: series, volumes, continue reading, and
 * running mokuro on volumes that have no text yet. Covers the player. */
Rectangle {
    id: root

    required property var player

    property var volumes: []
    property var series: []
    property var history: ({})
    property string currentKey: ""
    readonly property var current: root.series.find(s => s.key === root.currentKey) ?? null
    property string mokuroStatus: ""
    property bool mokuroInstalled: true
    /* Opened from the Library (or with no video): the arrow goes back there */
    property bool fromLibrary: false
    readonly property bool hasFile: (root.player.state.path ?? "").length > 0

    readonly property var undone: root.volumes.filter(v => !v.mokuro)
    readonly property var continueList: root.volumes
        .filter(v => {
            const h = root.history[v.path];
            return h && !h.done && (h.page ?? 0) > 0;
        })
        .sort((a, b) => (root.history[b.path].lastDate ?? 0) - (root.history[a.path].lastDate ?? 0))
        .slice(0, 8)

    visible: false

    /* The reader, for the controller */
    property alias reader: reader
    color: "#141414"

    function open(fromLibrary) {
        root.fromLibrary = !!fromLibrary;
        root.show();
    }

    /* Show again without changing where the arrow goes (back from the Manga list) */
    function show() {
        root.refresh();
        root.visible = true;
        root.forceActiveFocus();
        root.player.watchTracker.leave();
    }

    function close() {
        root.visible = false;
        if (root.fromLibrary || !root.hasFile) {
            root.player.library.open();
        } else {
            root.player.forceActiveFocus();
        }
    }

    function back() {
        if (root.currentKey.length > 0) {
            root.currentKey = "";
        } else {
            root.close();
        }
    }

    function refresh() {
        root.volumes = MangaLibrary.volumes();
        root.series = Manga.groupSeries(root.volumes);
        root.history = MangaLibrary.history();
    }

    function read(volume) {
        reader.open(volume);
    }

    /* "Avg 4,935 chars/hr  ·  1 volume finished" */
    function seriesStats(series, history) {
        if (!series) {
            return "";
        }
        let chars = 0;
        let seconds = 0;
        let finished = 0;
        for (const v of series.volumes) {
            const h = history[v.path];
            if (!h) {
                continue;
            }
            chars += h.rateChars ?? 0;
            seconds += h.rateSeconds ?? 0;
            if (h.done) {
                finished += 1;
            }
        }
        const parts = [];
        const r = Manga.rate(chars, seconds);
        if (r.length > 0) {
            parts.push(qsTr("Avg %1 chars/hr").arg(r));
        }
        if (finished > 0) {
            parts.push(finished === 1 ? qsTr("1 volume finished") : qsTr("%1 volumes finished").arg(finished));
        }
        return parts.join("  ·  ");
    }

    function progressText(volume) {
        const h = root.history[volume.path];
        if (!h) {
            return volume.pages + " " + qsTr("pages");
        }
        if (h.done) {
            return qsTr("Finished");
        }
        return qsTr("Page %1 / %2").arg((h.page ?? 0) + 1).arg(volume.pages);
    }

    function progressValue(volume) {
        const h = root.history[volume.path];
        if (!h) {
            return 0;
        }
        return h.done ? 1 : ((h.page ?? 0) + 1) / Math.max(1, volume.pages);
    }

    function jobText(volume) {
        if (MangaLibrary.jobVolume === volume.path) {
            return MangaLibrary.jobTotal > 0 ?
                qsTr("mokuro %1 / %2").arg(MangaLibrary.jobDone).arg(MangaLibrary.jobTotal) :
                qsTr("mokuro starting…");
        }
        if (MangaLibrary.queue.indexOf(volume.path) >= 0) {
            return qsTr("Queued");
        }
        return "";
    }

    Connections {
        target: MangaLibrary
        function onVolumeFinished(path, success, error) {
            root.refresh();
        }
        function onInstallFinished(success, error) {
            root.mokuroStatus = success ? qsTr("mokuro installed.") : error;
            if (success) {
                root.mokuroInstalled = true;
            }
        }
        function onMokuroChecked(installed, detail) {
            root.mokuroInstalled = installed;
            root.mokuroStatus = installed ? detail : qsTr("mokuro isn't installed for this Python. %1").arg(detail);
        }
        function onHistoryChanged() {
            root.history = MangaLibrary.history();
        }
    }

    Keys.onEscapePressed: root.back()

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    /* A cover with a progress strip */
    component Cover: Item {
        id: cover
        property string source: ""
        property real progress: 0
        /* Corner label: "no text", "3 vols without text", or empty */
        property string badge: ""
        signal clicked()
        implicitWidth: 150
        implicitHeight: 225

        Rectangle {
            anchors.fill: parent
            color: "#262626"
            radius: 4
            border.width: coverArea.containsMouse ? 2 : 0
            border.color: "white"
            clip: true

            Image {
                anchors.fill: parent
                anchors.margins: parent.border.width
                source: cover.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 300
            }
            Rectangle {
                visible: cover.progress > 0
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                height: 4
                color: "#66000000"
                Rectangle {
                    width: parent.width * cover.progress
                    height: parent.height
                    color: "#e50914"
                }
            }
            Rectangle {
                visible: cover.badge.length > 0
                anchors {
                    top: parent.top
                    right: parent.right
                    margins: 6
                }
                radius: 3
                color: "#cc000000"
                width: noText.implicitWidth + 10
                height: noText.implicitHeight + 6
                Text {
                    id: noText
                    anchors.centerIn: parent
                    text: cover.badge
                    color: "#f2f2f2"
                    font.pixelSize: 11
                }
            }
        }
        MouseArea {
            id: coverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cover.clicked()
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

        /* Header */
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            BackArrow {
                tip: root.currentKey.length > 0 ? qsTr("All series") :
                     root.fromLibrary || !root.hasFile ? qsTr("Back to Library") : qsTr("Back to video")
                onClicked: root.back()
            }
            Text {
                Layout.maximumWidth: implicitWidth
                Layout.fillWidth: true
                text: root.current ? root.current.title : qsTr("Manga")
                color: "#f2f2f2"
                font.pixelSize: 26
                font.bold: true
                elide: Text.ElideRight
            }
            /* Series page: average speed over all its saved sessions */
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                text: root.seriesStats(root.current, root.history)
                color: "#a3a3a3"
                font.pixelSize: 14
                elide: Text.ElideRight
            }
            PageButton {
                visible: MalClient.loggedIn
                text: qsTr("Manga list")
                onClicked: {
                    root.visible = false;
                    root.player.mangaListView.open();
                }
            }
            PageButton {
                text: qsTr("Folder…")
                onClicked: folderDialog.open()
            }
            PageButton {
                text: qsTr("Settings")
                onClicked: settingsDialog.open()
            }
            PageButton {
                text: qsTr("Refresh")
                onClicked: root.refresh()
            }
        }

        /* mokuro strip: volumes without text, progress, errors. Kept out of
         * the header so the big red button is never under the cursor. */
        Rectangle {
            Layout.fillWidth: true
            visible: MangaLibrary.running || MangaLibrary.lastError.length > 0 ||
                     root.mokuroStatus.length > 0 || root.undone.length > 0
            implicitHeight: jobColumn.implicitHeight + 20
            radius: 6
            color: "#1f1f1f"

            ColumnLayout {
                id: jobColumn
                anchors {
                    fill: parent
                    margins: 10
                }
                spacing: 6

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        Layout.fillWidth: true
                        color: "#f2f2f2"
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        text: {
                            if (MangaLibrary.jobKind === "install") {
                                return qsTr("Installing mokuro (this downloads a few GB the first time)…");
                            }
                            if (MangaLibrary.running) {
                                const v = root.volumes.find(x => x.path === MangaLibrary.jobVolume);
                                const name = v ? Manga.seriesTitle(v.series) + " · " + Manga.volumeLabel(v.name) : MangaLibrary.jobVolume;
                                const left = MangaLibrary.queue.length;
                                return qsTr("mokuro: %1").arg(name) +
                                    (MangaLibrary.jobTotal > 0 ? "  ·  " + MangaLibrary.jobDone + " / " + MangaLibrary.jobTotal : "") +
                                    (left > 0 ? "  ·  " + qsTr("%1 more queued").arg(left) : "");
                            }
                            if (MangaLibrary.lastError.length > 0) {
                                return MangaLibrary.lastError;
                            }
                            if (root.mokuroStatus.length > 0) {
                                return root.mokuroStatus;
                            }
                            return root.undone.length === 1 ? qsTr("1 volume has no text yet.") :
                                (root.undone.length === 1 ? qsTr("1 volume has no text yet.") :
                                 qsTr("%1 volumes have no text yet.").arg(root.undone.length));
                        }
                    }
                    PageButton {
                        visible: !MangaLibrary.running && root.undone.length > 0
                        accent: true
                        text: qsTr("Run mokuro on all (%1)").arg(root.undone.length)
                        onClicked: runAllDialog.open()
                    }
                    PageButton {
                        visible: MangaLibrary.running
                        text: qsTr("Cancel")
                        onClicked: MangaLibrary.cancelMokuro()
                    }
                    PageButton {
                        visible: !MangaLibrary.running && (MangaLibrary.lastError.indexOf("install") >= 0 || !root.mokuroInstalled)
                        text: qsTr("Install mokuro")
                        onClicked: MangaLibrary.installMokuro()
                    }
                }
                ProgressBar {
                    Layout.fillWidth: true
                    visible: MangaLibrary.running
                    indeterminate: MangaLibrary.jobTotal === 0
                    from: 0
                    to: Math.max(1, MangaLibrary.jobTotal)
                    value: MangaLibrary.jobDone
                }
                Text {
                    Layout.fillWidth: true
                    visible: MangaLibrary.running
                    text: MangaLibrary.jobLine
                    color: "#6e6e6e"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        Text {
            visible: MangaLibrary.root.length === 0 || root.volumes.length === 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: "#a3a3a3"
            font.pixelSize: 15
            text: MangaLibrary.root.length === 0 ?
                qsTr("Choose your manga folder with Folder… (one folder per series; each volume is a folder of page images).") :
                qsTr("No volumes found in %1.").arg(MangaLibrary.root)
        }

        /* Home: continue reading + series grid */
        Flickable {
            id: homeFlick
            visible: root.currentKey.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentHeight: homeColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }

            Column {
                id: homeColumn
                width: homeFlick.width - 12
                spacing: 14

                Text {
                    visible: root.continueList.length > 0
                    text: qsTr("Continue reading")
                    color: "#f2f2f2"
                    font.pixelSize: 18
                    font.bold: true
                }
                Flow {
                    visible: root.continueList.length > 0
                    width: parent.width
                    spacing: 14
                    Repeater {
                        model: root.continueList
                        delegate: Column {
                            required property var modelData
                            spacing: 4
                            Cover {
                                source: modelData.cover
                                progress: root.progressValue(modelData)
                                badge: modelData.mokuro.length > 0 ? "" : qsTr("no text")
                                onClicked: root.read(modelData)
                            }
                            Text {
                                width: 150
                                text: Manga.seriesTitle(modelData.series) + " · " + Manga.volumeLabel(modelData.name)
                                color: "#f2f2f2"
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: 150
                                text: root.progressText(modelData)
                                color: "#a3a3a3"
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Text {
                    visible: root.series.length > 0
                    text: qsTr("Series")
                    color: "#f2f2f2"
                    font.pixelSize: 18
                    font.bold: true
                }
                Flow {
                    width: parent.width
                    spacing: 14
                    Repeater {
                        model: root.series
                        delegate: Column {
                            required property var modelData
                            spacing: 4
                            Cover {
                                source: modelData.cover
                                progress: {
                                    const done = modelData.volumes.filter(v => (root.history[v.path] ?? {}).done).length;
                                    return done / Math.max(1, modelData.volumes.length);
                                }
                                badge: {
                                    const missing = modelData.volumes.filter(v => v.mokuro.length === 0).length;
                                    if (missing === 0) {
                                        return "";
                                    }
                                    if (missing === modelData.volumes.length) {
                                        return qsTr("no text");
                                    }
                                    return missing === 1 ? qsTr("1 vol without text") :
                                                           qsTr("%1 vols without text").arg(missing);
                                }
                                onClicked: root.currentKey = modelData.key
                            }
                            Text {
                                width: 150
                                text: modelData.title
                                color: "#f2f2f2"
                                font.pixelSize: 12
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                width: 150
                                text: modelData.volumes.length === 1 ? qsTr("1 volume") :
                                      qsTr("%1 volumes").arg(modelData.volumes.length)
                                color: "#a3a3a3"
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }

        /* Series page: volumes */
        ListView {
            id: volumeList
            visible: root.currentKey.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 6
            model: root.current ? root.current.volumes : []
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { }

            delegate: Rectangle {
                id: row
                required property var modelData
                width: volumeList.width - 12
                height: 96
                radius: 6
                color: rowHover.hovered ? "#2b2b2b" : "#1f1f1f"

                HoverHandler {
                    id: rowHover
                }

                Image {
                    id: thumb
                    anchors {
                        left: parent.left
                        top: parent.top
                        bottom: parent.bottom
                        margins: 8
                    }
                    width: 54
                    source: row.modelData.cover
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 120
                }

                ColumnLayout {
                    anchors {
                        left: thumb.right
                        right: buttons.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 14
                        rightMargin: 14
                    }
                    spacing: 3
                    Text {
                        Layout.fillWidth: true
                        text: Manga.volumeLabel(row.modelData.name)
                        color: "#f2f2f2"
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        color: "#6e6e6e"
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            const h = root.history[row.modelData.path];
                            const parts = [root.progressText(row.modelData)];
                            /* Saved sessions only, so chars, time and speed agree */
                            if (h && (h.rateChars ?? 0) > 0) {
                                parts.push(h.rateChars.toLocaleString() + " " + qsTr("chars"));
                            }
                            if (h && (h.rateSeconds ?? 0) > 0) {
                                parts.push(Manga.formatMinutes(h.rateSeconds));
                            }
                            const r = h ? Manga.rate(h.rateChars ?? 0, h.rateSeconds ?? 0) : "";
                            if (r.length > 0) {
                                parts.push(r + " " + qsTr("chars/hr"));
                            }
                            parts.push(row.modelData.mokuro.length > 0 ? qsTr("text ✓") : qsTr("no text yet"));
                            const job = root.jobText(row.modelData);
                            if (job.length > 0) {
                                parts.push(job);
                            }
                            return parts.join("  ·  ");
                        }
                        color: "#a3a3a3"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    ProgressBar {
                        Layout.fillWidth: true
                        visible: MangaLibrary.jobVolume === row.modelData.path && MangaLibrary.jobTotal > 0
                        from: 0
                        to: Math.max(1, MangaLibrary.jobTotal)
                        value: MangaLibrary.jobDone
                    }
                }

                Row {
                    id: buttons
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 12
                    }
                    spacing: 8
                    PageButton {
                        visible: row.modelData.mokuro.length === 0
                        enabled: root.jobText(row.modelData).length === 0
                        text: qsTr("Run mokuro")
                        onClicked: MangaLibrary.runMokuro([row.modelData.path])
                    }
                    PageButton {
                        text: (root.history[row.modelData.path] ?? {}).page > 0 ? qsTr("Continue") : qsTr("Read")
                        active: true
                        onClicked: root.read(row.modelData)
                    }
                }
            }
        }
    }

    MangaReader {
        id: reader
        anchors.fill: parent
        player: root.player
        onClosed: finished => {
            root.refresh();
            root.forceActiveFocus();
            if (finished) {
                root.player.mangaToggl.ask(finished);
            }
        }
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Manga folder (one folder per series)")
        currentFolder: MangaLibrary.root.length > 0 ? "file:///" + MangaLibrary.root : ""
        onAccepted: {
            MangaLibrary.root = MangaLibrary.localPath(folderDialog.selectedFolder);
            root.refresh();
        }
    }

    /* "Run on all" can mean hours of work: ask first */
    Dialog {
        id: runAllDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 480)
        modal: true
        title: root.undone.length === 1 ? qsTr("Run mokuro on 1 volume?") :
                                          qsTr("Run mokuro on %1 volumes?").arg(root.undone.length)
        standardButtons: Dialog.Yes | Dialog.Cancel
        onAccepted: MangaLibrary.runMokuro(root.undone.map(v => v.path))

        Label {
            width: parent.width
            wrapMode: Label.WordWrap
            text: {
                const counts = {};
                for (const v of root.undone) {
                    const t = Manga.seriesTitle(v.series);
                    counts[t] = (counts[t] ?? 0) + 1;
                }
                const lines = Object.keys(counts).map(t => "• " + t + " (" + counts[t] + ")");
                return lines.join("
") + "

" +
                    qsTr("This can take hours and keeps the graphics card busy. You can cancel at any time; finished volumes keep their text.");
            }
        }
    }

    Dialog {
        id: settingsDialog
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 560)
        modal: true
        title: qsTr("Manga settings")
        standardButtons: Dialog.Close

        onOpened: pythonField.text = MangaLibrary.python

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            Label {
                Layout.fillWidth: true
                wrapMode: Label.WordWrap
                text: qsTr("mokuro reads the text in the pages (OCR). It runs with Python; Memento starts it for you. " +
                           "Each volume takes a few minutes (much longer without a graphics card).")
            }
            RowLayout {
                Layout.fillWidth: true
                Label {
                    text: qsTr("Python")
                }
                TextField {
                    id: pythonField
                    Layout.fillWidth: true
                    placeholderText: "python"
                    onEditingFinished: MangaLibrary.python = text
                }
            }
            RowLayout {
                Button {
                    text: qsTr("Check mokuro")
                    onClicked: {
                        MangaLibrary.python = pythonField.text;
                        MangaLibrary.checkMokuro();
                    }
                }
                Button {
                    text: qsTr("Install mokuro")
                    enabled: !MangaLibrary.running
                    onClicked: {
                        MangaLibrary.python = pythonField.text;
                        MangaLibrary.installMokuro();
                        settingsDialog.close();
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Label.WordWrap
                visible: root.mokuroStatus.length > 0
                text: root.mokuroStatus
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Label.WordWrap
                color: "#8a8a8a"
                text: qsTr("Reader: click the black edge on the left or ← = next page, right edge or → = back. " +
                           "Click the page or use the wheel to zoom, drag to move. D = one/two pages, Esc = back. " +
                           "Reading sessions are saved to %1.").arg(MangaLibrary.sessionsPath)
            }
        }
    }
}

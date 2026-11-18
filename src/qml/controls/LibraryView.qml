import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Ripose.Memento

import "../util/Library.js" as Library

/* Anime library: series in the library folder with clean episode names,
 * what's watched, and "Continue watching" (logic in util/Library.js,
 * history in WatchHistory). Covers the player while open. */
Rectangle {
    id: root

    required property var player

    readonly property color textColor: "#f2f2f2"
    readonly property color dimColor: "#a3a3a3"
    readonly property color faintColor: "#6e6e6e"
    readonly property color cardColor: "#1f1f1f"
    readonly property color cardHover: "#2b2b2b"
    readonly property color accent: "#e5383b"
    readonly property color doneColor: "#46d369"

    readonly property bool hasFile: (root.player.state.path ?? "").length > 0

    property var seriesList: []
    property var continueItems: []
    /* Series page shown; null = home */
    property var current: null
    property string currentKey: ""
    property bool dirty: true

    visible: false
    color: "#141414"

    function open() {
        root.refresh();
        root.visible = true;
        root.forceActiveFocus();
        if (root.hasFile && !root.player.state.pause) {
            root.player.controller.pause();
        }
    }

    function close() {
        root.visible = false;
        root.player.forceActiveFocus();
    }

    function refresh() {
        const history = WatchHistory.entries();
        const names = WatchHistory.names();
        const list = [];
        for (const folder of WatchHistory.seriesFolders()) {
            const s = Library.buildSeries(folder, WatchHistory.videosIn(folder.path), history, names);
            if (s.sections.length > 0) {
                list.push(s);
            }
        }
        /* Videos lying directly in the library folder, grouped by show */
        for (const group of Library.groupLoose(WatchHistory.libraryRoot, WatchHistory.looseVideos())) {
            list.push(Library.buildSeries(group.folder, group.files, history, names));
        }
        list.sort((a, b) => a.title.localeCompare(b.title, undefined, { sensitivity: "base" }));
        root.seriesList = list;
        root.continueItems = Library.continueList(list);
        root.current = root.currentKey.length > 0 ?
            (list.find(s => s.key === root.currentKey) ?? null) : null;
        if (root.current === null) {
            root.currentKey = "";
        }
        root.dirty = false;
    }

    function showSeries(series) {
        root.currentKey = series ? series.key : "";
        root.current = series;
        seriesFlick.contentY = 0;
    }

    function play(episode, fromStart) {
        const resume = !fromStart && !episode.done && episode.progress > 0 &&
            (episode.dur <= 0 || episode.pos < episode.dur - 10);
        const options = resume ? [`start=${Math.max(0, Math.floor(episode.pos - 3))}`] : [];
        root.player.controller.loadFile(episode.path, false, options);
        root.close();
    }

    function statusText(series) {
        if (series.total === 0) {
            return qsTr("Extras only");
        }
        const count = qsTr("%1 of %2 watched").arg(series.watched).arg(series.total);
        if (series.finished) {
            return qsTr("Finished") + " · " + count;
        }
        if (!series.started) {
            return qsTr("Not started") + " · " + qsTr("%1 episodes").arg(series.total);
        }
        const last = Library.formatDate(series.lastDate);
        return last.length > 0 ? count + " · " + qsTr("last watched %1").arg(last) : count;
    }

    function nextText(series) {
        const e = series.next;
        if (!e) {
            return "";
        }
        if (series.resume) {
            return qsTr("%1 · resume at %2").arg(e.label).arg(Library.formatTime(e.pos));
        }
        return qsTr("%1 · up next").arg(e.label);
    }

    Connections {
        target: WatchHistory
        function onChanged() {
            if (root.visible) {
                root.refresh();
            } else {
                root.dirty = true;
            }
        }
        function onLibraryRootChanged() {
            root.currentKey = "";
            root.refresh();
        }
    }

    /* A file opened some other way (drag and drop, Recent) */
    Connections {
        target: root.player.state
        function onPathChanged() {
            if (root.visible && root.hasFile) {
                root.close();
            }
        }
    }

    Keys.onEscapePressed: {
        if (root.current !== null) {
            root.showSeries(null);
        } else {
            root.close();
        }
    }

    /* Keep the mouse (and the cursor) away from the player underneath */
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.ArrowCursor
        onWheel: wheel => wheel.accepted = true
    }

    /* Small flat button (inline components cannot see ids of this file) */
    component FlatButton: Rectangle {
        id: button

        property string text: ""
        property bool primary: false
        property int fontSize: 14
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 28
        implicitHeight: 36
        radius: 4
        color: primary ? (buttonArea.containsMouse ? "#ffffff" : "#e6e6e6")
                       : (buttonArea.containsMouse ? "#4d4d4d" : "#333333")

        Text {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.text
            color: button.primary ? "#141414" : "#f2f2f2"
            font.pixelSize: button.fontSize
            font.bold: button.primary
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    /* Thin progress bar */
    component Bar: Rectangle {
        property real value: 0
        property color fill: "#e5383b"
        implicitHeight: 3
        radius: 1.5
        color: "#4d4d4d"
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.value))
            height: parent.height
            radius: parent.radius
            color: parent.fill
        }
    }

    /* Header */
    RowLayout {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 40
            rightMargin: 24
            topMargin: 18
        }
        spacing: 12

        Text {
            text: qsTr("Library")
            color: root.textColor
            font.pixelSize: 26
            font.bold: true
        }

        Text {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignBottom
            bottomPadding: 4
            text: WatchHistory.libraryRoot
            color: root.faintColor
            font.pixelSize: 12
            elide: Text.ElideMiddle
        }

        FlatButton {
            text: qsTr("Folder…")
            onClicked: folderDialog.open()
        }

        FlatButton {
            text: qsTr("Refresh")
            onClicked: root.refresh()
        }

        FlatButton {
            text: root.hasFile ? qsTr("✕  Back to video") : qsTr("✕  Close")
            onClicked: root.close()
        }
    }

    /* Home: continue watching + all series */
    Flickable {
        id: homeFlick
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            bottom: parent.bottom
            topMargin: 16
        }
        visible: root.current === null
        clip: true
        contentWidth: width
        contentHeight: homeColumn.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }

        Column {
            id: homeColumn
            x: 40
            width: homeFlick.width - 80
            spacing: 14

            /* No folder */
            Column {
                visible: root.seriesList.length === 0
                spacing: 12
                topPadding: 40

                Text {
                    text: WatchHistory.libraryRoot.length === 0 ?
                              qsTr("Pick the folder that holds your anime (one folder per series).") :
                              qsTr("No videos found in this folder.")
                    color: root.dimColor
                    font.pixelSize: 16
                }

                FlatButton {
                    primary: true
                    text: qsTr("Choose folder…")
                    onClicked: folderDialog.open()
                }
            }

            Text {
                visible: root.continueItems.length > 0
                text: qsTr("Continue watching")
                color: root.textColor
                font.pixelSize: 19
                font.bold: true
            }

            Flow {
                visible: root.continueItems.length > 0
                width: parent.width
                spacing: 12

                Repeater {
                    model: root.continueItems

                    delegate: Rectangle {
                        id: card
                        required property var modelData

                        width: 300
                        height: 120
                        radius: 6
                        color: cardArea.containsMouse ? root.cardHover : root.cardColor
                        border.color: cardArea.containsMouse ? "#5a5a5a" : "transparent"

                        MouseArea {
                            id: cardArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.play(card.modelData.next, false)
                        }

                        Column {
                            anchors {
                                fill: parent
                                margins: 14
                            }
                            spacing: 6

                            Text {
                                width: parent.width
                                text: card.modelData.title
                                color: root.textColor
                                font.pixelSize: 16
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: "▶  " + root.nextText(card.modelData)
                                color: root.dimColor
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: qsTr("%1 of %2 watched").arg(card.modelData.watched).arg(card.modelData.total)
                                color: root.faintColor
                                font.pixelSize: 12
                            }
                        }

                        Bar {
                            anchors {
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                                margins: 14
                            }
                            value: card.modelData.resume ? card.modelData.next.progress :
                                   card.modelData.watched / Math.max(1, card.modelData.total)
                        }

                        /* Open the episode list instead of playing */
                        Text {
                            anchors {
                                right: parent.right
                                top: parent.top
                                margins: 10
                            }
                            text: qsTr("Episodes")
                            color: listArea.containsMouse ? root.textColor : root.faintColor
                            font.pixelSize: 12
                            font.underline: listArea.containsMouse

                            MouseArea {
                                id: listArea
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showSeries(card.modelData)
                            }
                        }
                    }
                }
            }

            Item {
                visible: root.continueItems.length > 0
                width: 1
                height: 10
            }

            Text {
                visible: root.seriesList.length > 0
                text: qsTr("All series")
                color: root.textColor
                font.pixelSize: 19
                font.bold: true
            }

            Repeater {
                model: root.seriesList

                delegate: Rectangle {
                    id: row
                    required property var modelData

                    width: homeColumn.width
                    height: 66
                    radius: 6
                    color: rowArea.containsMouse ? root.cardHover : root.cardColor

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showSeries(row.modelData)
                    }

                    Column {
                        anchors {
                            left: parent.left
                            right: nextLabel.left
                            verticalCenter: parent.verticalCenter
                            leftMargin: 16
                            rightMargin: 16
                        }
                        spacing: 4

                        Text {
                            width: parent.width
                            text: row.modelData.title
                            color: root.textColor
                            font.pixelSize: 16
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.statusText(row.modelData)
                            color: row.modelData.finished ? root.doneColor : root.dimColor
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        id: nextLabel
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            rightMargin: 16
                        }
                        text: row.modelData.started && row.modelData.next ?
                                  root.nextText(row.modelData) : ""
                        color: root.dimColor
                        font.pixelSize: 13
                    }

                    Bar {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        visible: row.modelData.started
                        value: row.modelData.watched / Math.max(1, row.modelData.total)
                        fill: row.modelData.finished ? root.doneColor : root.accent
                        radius: 0
                    }
                }
            }
        }
    }

    /* Series page */
    Flickable {
        id: seriesFlick
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            bottom: parent.bottom
            topMargin: 8
        }
        visible: root.current !== null
        clip: true
        contentWidth: width
        contentHeight: seriesColumn.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }

        Column {
            id: seriesColumn
            x: 40
            width: seriesFlick.width - 80
            spacing: 10

            Text {
                text: "‹  " + qsTr("All series")
                color: backArea.containsMouse ? root.textColor : root.dimColor
                font.pixelSize: 14

                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showSeries(null)
                }
            }

            RowLayout {
                width: parent.width
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: root.current ? root.current.title : ""
                    color: root.textColor
                    font.pixelSize: 30
                    font.bold: true
                    elide: Text.ElideRight
                }

                FlatButton {
                    text: qsTr("Rename")
                    onClicked: renameDialog.openFor(root.current)
                }
            }

            Text {
                width: parent.width
                text: root.current ? (root.current.loose ?
                                          qsTr("Loose files in the library folder") :
                                          root.current.folderName) : ""
                color: root.faintColor
                font.pixelSize: 12
                elide: Text.ElideMiddle
            }

            Row {
                spacing: 16
                topPadding: 4
                bottomPadding: 8

                FlatButton {
                    visible: root.current !== null && root.current.next !== null
                    primary: true
                    fontSize: 15
                    implicitHeight: 40
                    text: root.current && root.current.next ?
                              (root.current.resume ?
                                   qsTr("▶  Resume %1 at %2").arg(root.current.next.short).arg(Library.formatTime(root.current.next.pos)) :
                                   qsTr("▶  Play %1").arg(root.current.next.short)) : ""
                    onClicked: root.play(root.current.next, false)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.current ? root.statusText(root.current) : ""
                    color: root.current && root.current.finished ? root.doneColor : root.dimColor
                    font.pixelSize: 14
                }
            }

            Repeater {
                model: root.current ? root.current.sections : []

                delegate: Column {
                    id: section
                    required property var modelData

                    /* Deleted (watched) episodes count but aren't listed */
                    readonly property var shown: modelData.episodes.filter(e => !e.ghost)

                    visible: shown.length > 0
                    width: seriesColumn.width
                    spacing: 4

                    Text {
                        visible: section.modelData.title.length > 0
                        topPadding: 14
                        bottomPadding: 4
                        text: section.modelData.title
                        color: section.modelData.extra ? root.dimColor : root.textColor
                        font.pixelSize: 18
                        font.bold: true
                    }

                    Repeater {
                        model: section.shown

                        delegate: Rectangle {
                            id: episodeRow
                            required property var modelData

                            readonly property var episode: modelData
                            readonly property bool isNext: !!(root.current && root.current.next &&
                                                              root.current.next.key === episode.key)

                            width: section.width
                            height: 50
                            radius: 4
                            color: episodeArea.containsMouse ? root.cardHover :
                                   episodeRow.isNext ? "#2a1f1f" : root.cardColor
                            border.color: episodeRow.isNext ? "#7a2a2b" : "transparent"

                            MouseArea {
                                id: episodeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        episodeMenu.openFor(episodeRow.episode);
                                    } else {
                                        root.play(episodeRow.episode, false);
                                    }
                                }
                            }

                            /* Watched tick: click to toggle */
                            Rectangle {
                                id: tick
                                anchors {
                                    left: parent.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 14
                                }
                                width: 22
                                height: 22
                                radius: 11
                                color: episodeRow.episode.done ? root.doneColor : "transparent"
                                border.color: episodeRow.episode.done ? root.doneColor :
                                              tickArea.containsMouse ? root.textColor : "#5a5a5a"
                                border.width: 2

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    visible: episodeRow.episode.done || tickArea.containsMouse
                                    color: episodeRow.episode.done ? "#141414" : root.dimColor
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                MouseArea {
                                    id: tickArea
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: WatchHistory.setWatched([episodeRow.episode.key], !episodeRow.episode.done)
                                }

                                ToolTip.visible: tickArea.containsMouse
                                ToolTip.delay: 600
                                ToolTip.text: episodeRow.episode.done ? qsTr("Mark unwatched") : qsTr("Mark watched")
                            }

                            Text {
                                id: episodeLabel
                                anchors {
                                    left: tick.right
                                    right: statusRow.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: 14
                                    rightMargin: 14
                                }
                                text: episodeRow.episode.label
                                color: episodeRow.episode.done ? root.dimColor : root.textColor
                                font.pixelSize: 15
                                font.bold: episodeRow.isNext
                                elide: Text.ElideRight
                            }

                            Row {
                                id: statusRow
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: 16
                                }
                                spacing: 10

                                Rectangle {
                                    visible: episodeRow.isNext
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: nextPill.implicitWidth + 14
                                    height: 20
                                    radius: 3
                                    color: root.accent

                                    Text {
                                        id: nextPill
                                        anchors.centerIn: parent
                                        text: root.current && root.current.resume ? qsTr("CONTINUE") : qsTr("UP NEXT")
                                        color: "white"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                Bar {
                                    visible: episodeRow.episode.progress > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 110
                                    implicitHeight: 4
                                    value: episodeRow.episode.progress
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: episodeRow.episode.done ?
                                              qsTr("Watched %1").arg(Library.formatDate(episodeRow.episode.watchedDate)) :
                                          episodeRow.episode.progress > 0 ?
                                              qsTr("%1 left").arg(Library.formatTime(episodeRow.episode.dur - episodeRow.episode.pos)) : ""
                                    color: episodeRow.episode.done ? root.doneColor : root.dimColor
                                    font.pixelSize: 13
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "⋯"
                                    color: moreArea.containsMouse ? root.textColor : root.faintColor
                                    font.pixelSize: 18

                                    MouseArea {
                                        id: moreArea
                                        anchors.fill: parent
                                        anchors.margins: -8
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: episodeMenu.openFor(episodeRow.episode)
                                    }
                                }
                            }

                            ToolTip.visible: episodeArea.containsMouse && !tickArea.containsMouse && !moreArea.containsMouse
                            ToolTip.delay: 1200
                            ToolTip.text: episodeRow.episode.rel
                        }
                    }
                }
            }
        }
    }

    DarkMenu {
        id: episodeMenu

        property var episode: null

        function openFor(episode) {
            episodeMenu.episode = episode;
            episodeMenu.popup();
        }

        Action {
            text: qsTr("Play from the start")
            onTriggered: root.play(episodeMenu.episode, true)
        }

        Action {
            text: episodeMenu.episode && episodeMenu.episode.done ? qsTr("Mark unwatched") : qsTr("Mark watched")
            onTriggered: WatchHistory.setWatched([episodeMenu.episode.key], !episodeMenu.episode.done)
        }

        Action {
            enabled: episodeMenu.episode !== null && !episodeMenu.episode.extra
            text: qsTr("Mark watched up to here")
            onTriggered: WatchHistory.setWatched(Library.keysUpTo(root.current, episodeMenu.episode), true)
        }
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Anime folder (one folder per series)")
        currentFolder: WatchHistory.libraryRoot.length > 0 ? "file:///" + WatchHistory.libraryRoot : ""
        onAccepted: WatchHistory.libraryRoot = WatchHistory.localPath(folderDialog.selectedFolder)
    }

    Dialog {
        id: renameDialog

        property string key: ""

        function openFor(series) {
            renameDialog.key = series.key;
            nameField.text = series.title;
            renameDialog.open();
            nameField.selectAll();
            nameField.forceActiveFocus();
        }

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 480)
        modal: true
        title: qsTr("Series name")
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAboutToShow: Utils.modalDialogs += 1
        onClosed: {
            Utils.modalDialogs -= 1;
            root.forceActiveFocus();
        }
        onAccepted: WatchHistory.setName(renameDialog.key, nameField.text)

        ColumnLayout {
            anchors.fill: parent

            TextField {
                id: nameField
                Layout.fillWidth: true
                onAccepted: renameDialog.accept()
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Label.WordWrap
                text: qsTr("Leave it empty to go back to the name from the folder.")
                color: MementoPalette.placeholderText
            }
        }
    }
}

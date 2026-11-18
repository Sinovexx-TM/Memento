import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Ripose.Memento

import "../util/Library.js" as Library

/* Anime library: series in the library folder with AniList posters, clean
 * episode names, what's watched, and "Continue watching" (logic in
 * util/Library.js, history in WatchHistory). Covers the player while open. */
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

    /* Sizes follow the window: designed at 1280 px wide */
    readonly property real scale: Math.min(1.5, Math.max(0.8, root.width / 1280))
    readonly property real margin: Math.round(54 * root.scale)
    readonly property real posterWidth: Math.round(175 * root.scale)

    property var seriesList: []
    property var continueItems: []
    /* Series page shown; null = home */
    property var current: null
    property string currentKey: ""
    property bool dirty: true

    /* Series keys waiting for an automatic AniList lookup */
    property var posterQueue: []
    property string posterBusy: ""
    property var posterTried: ({})

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
        const media = WatchHistory.media();
        const list = [];
        for (const folder of WatchHistory.seriesFolders()) {
            const s = Library.buildSeries(folder, WatchHistory.videosIn(folder.path), history, names, media);
            if (s.sections.length > 0) {
                list.push(s);
            }
        }
        /* Videos lying directly in the library folder, grouped by show */
        for (const group of Library.groupLoose(WatchHistory.libraryRoot, WatchHistory.looseVideos())) {
            list.push(Library.buildSeries(group.folder, group.files, history, names, media));
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
        root.queuePosters();
    }

    /* Look up posters for series that have none yet (once per session) */
    function queuePosters() {
        const queue = root.posterQueue.slice();
        for (const s of root.seriesList) {
            if (!s.media && !root.posterTried[s.key] && queue.indexOf(s.key) < 0 && s.key !== root.posterBusy) {
                queue.push(s.key);
            }
        }
        root.posterQueue = queue;
        root.nextPoster();
    }

    function nextPoster() {
        if (root.posterBusy.length > 0 || root.posterQueue.length === 0) {
            return;
        }
        const key = root.posterQueue[0];
        root.posterQueue = root.posterQueue.slice(1);
        const series = root.seriesList.find(s => s.key === key);
        if (!series) {
            root.nextPoster();
            return;
        }
        const tried = root.posterTried;
        tried[key] = true;
        root.posterTried = tried;
        root.posterBusy = key;
        WatchHistory.searchAniList(series.guess, "auto:" + key);
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
        if (series.finished) {
            return qsTr("✓ Finished · %1 of %2").arg(series.watched).arg(series.total);
        }
        if (!series.started) {
            return series.total === 1 ? qsTr("Not started · 1 episode") :
                                        qsTr("Not started · %1 episodes").arg(series.total);
        }
        const next = series.next ? " · " + series.next.short + (series.resume ? "" : " " + qsTr("next")) : "";
        return qsTr("%1 of %2").arg(series.watched).arg(series.total) + next;
    }

    function nextText(series) {
        const e = series.next;
        if (!e) {
            return "";
        }
        if (series.resume) {
            return qsTr("%1 · resume at %2").arg(e.short).arg(Library.formatTime(e.pos));
        }
        return qsTr("%1 · up next").arg(e.short);
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
        function onAniListResults(tag, success, results, error) {
            if (!tag.startsWith("auto:")) {
                return;
            }
            const key = tag.substring(5);
            root.posterBusy = "";
            if (success) {
                /* First result; nothing found = fallback tile */
                WatchHistory.setMedia(key, results.length > 0 ? results[0] : { none: true });
            }
            root.nextPoster();
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

    /* Inline components cannot see ids of this file: colours are literal */

    /* Outlined button; primary = white with dark text */
    component FlatButton: Rectangle {
        id: button

        property string text: ""
        property bool primary: false
        property int fontSize: 14
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 32
        implicitHeight: 40
        radius: 6
        color: primary ? (buttonArea.containsMouse ? "#ffffff" : "#e6e6e6")
                       : (buttonArea.containsMouse ? "#2b2b2b" : "transparent")
        border.color: primary ? "transparent" : (buttonArea.containsMouse ? "#9a9a9a" : "#5a5a5a")

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
        implicitHeight: 4
        radius: 2
        color: "#3d3d3d"
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, parent.value))
            height: parent.height
            radius: parent.radius
            color: parent.fill
        }
    }

    /* Poster, or a coloured tile with the title when there is none */
    component Poster: Rectangle {
        id: poster

        property var series: null
        property bool showTitle: true

        color: series && series.poster.length > 0 && image.status === Image.Ready ?
                   "#262a33" : Qt.hsla(Library.tileHue(series ? series.title : ""), 0.45, 0.28, 1)
        radius: 6
        clip: true

        Image {
            id: image
            anchors.fill: parent
            source: poster.series ? poster.series.poster : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 400
            visible: status === Image.Ready
        }

        Text {
            visible: image.status !== Image.Ready && poster.showTitle
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: 14
            }
            text: poster.series ? poster.series.title : ""
            color: "white"
            font.pixelSize: Math.max(13, Math.round(poster.width / 9))
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }
    }

    /* Header */
    RowLayout {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: root.margin
            rightMargin: root.margin
            topMargin: 26
        }
        spacing: 12

        Text {
            text: qsTr("Library")
            color: root.textColor
            font.pixelSize: 32
            font.bold: true
        }

        Item {
            Layout.fillWidth: true
        }

        FlatButton {
            visible: MalClient.loggedIn
            text: qsTr("MyAnimeList")
            onClicked: {
                root.close();
                root.player.malView.open();
            }
        }

        FlatButton {
            text: qsTr("Folder…")
            onClicked: folderDialog.open()
        }

        FlatButton {
            text: qsTr("Refresh")
            onClicked: {
                root.posterTried = ({});
                root.refresh();
            }
        }

        /* Close: back to the video */
        Rectangle {
            implicitWidth: 48
            implicitHeight: 48
            radius: 24
            color: closeArea.containsMouse ? "#4d4d4d" : "#2e2e2e"

            Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.textColor
                font.pixelSize: 18
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.close()
            }

            ToolTip.visible: closeArea.containsMouse
            ToolTip.delay: 500
            ToolTip.text: root.hasFile ? qsTr("Back to video") : qsTr("Close")
        }
    }

    /* Home: continue watching + poster grid */
    Flickable {
        id: homeFlick
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            bottom: parent.bottom
            topMargin: 22
        }
        visible: root.current === null
        clip: true
        contentWidth: width
        contentHeight: homeColumn.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }

        Column {
            id: homeColumn
            x: root.margin
            width: homeFlick.width - 2 * root.margin
            spacing: 16

            /* No folder / nothing found */
            Column {
                visible: root.seriesList.length === 0
                spacing: 14
                topPadding: 40

                Text {
                    text: WatchHistory.libraryRoot.length === 0 ?
                              qsTr("Pick the folder that holds your anime (one folder per series).") :
                              qsTr("No videos found in %1.").arg(WatchHistory.libraryRoot)
                    color: root.dimColor
                    font.pixelSize: 17
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
                font.pixelSize: 21
                font.bold: true
            }

            Flow {
                id: continueFlow
                visible: root.continueItems.length > 0
                width: parent.width
                spacing: 18

                readonly property int columns: Math.max(1, Math.floor((width + spacing) / (380 + spacing)))
                readonly property real cardWidth: (width - (columns - 1) * spacing) / columns

                Repeater {
                    model: root.continueItems

                    delegate: Rectangle {
                        id: card
                        required property var modelData

                        width: continueFlow.cardWidth
                        height: Math.round(146 * root.scale)
                        radius: 8
                        color: cardArea.containsMouse ? root.cardHover : root.cardColor
                        border.color: cardArea.containsMouse ? "#5a5a5a" : "transparent"

                        MouseArea {
                            id: cardArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showSeries(card.modelData)
                        }

                        Poster {
                            id: cardPoster
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                                margins: 12
                            }
                            width: height * 2 / 3
                            series: card.modelData
                            showTitle: false
                        }

                        Column {
                            anchors {
                                left: cardPoster.right
                                right: playButton.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 16
                                rightMargin: 16
                            }
                            spacing: 8

                            Text {
                                width: parent.width
                                text: card.modelData.title
                                color: root.textColor
                                font.pixelSize: 17
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: root.nextText(card.modelData)
                                color: root.dimColor
                                font.pixelSize: 14
                                elide: Text.ElideRight
                            }

                            Bar {
                                width: parent.width
                                value: card.modelData.watched / Math.max(1, card.modelData.total)
                            }

                            Text {
                                width: parent.width
                                text: qsTr("%1 of %2 watched").arg(card.modelData.watched).arg(card.modelData.total)
                                color: root.faintColor
                                font.pixelSize: 13
                            }
                        }

                        /* Play / resume straight away */
                        Rectangle {
                            id: playButton
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                rightMargin: 12
                            }
                            width: 52
                            height: 52
                            radius: 26
                            color: playArea.containsMouse ? "#ff5052" : root.accent

                            Text {
                                anchors.centerIn: parent
                                anchors.horizontalCenterOffset: 2
                                text: "▶"
                                color: "white"
                                font.pixelSize: 18
                            }

                            MouseArea {
                                id: playArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.play(card.modelData.next, false)
                            }

                            ToolTip.visible: playArea.containsMouse
                            ToolTip.delay: 500
                            ToolTip.text: card.modelData.resume ? qsTr("Resume") : qsTr("Play")
                        }
                    }
                }
            }

            Item {
                visible: root.continueItems.length > 0
                width: 1
                height: 6
            }

            Text {
                visible: root.seriesList.length > 0
                text: qsTr("All series")
                color: root.textColor
                font.pixelSize: 21
                font.bold: true
            }

            Flow {
                width: parent.width
                spacing: 20

                Repeater {
                    model: root.seriesList

                    delegate: Column {
                        id: tile
                        required property var modelData

                        width: root.posterWidth
                        spacing: 8

                        Item {
                            width: root.posterWidth
                            height: Math.round(root.posterWidth * 1.5)

                            Poster {
                                anchors.fill: parent
                                series: tile.modelData
                            }

                            /* Watched part of the series */
                            Bar {
                                visible: tile.modelData.started && !tile.modelData.finished
                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    bottom: parent.bottom
                                }
                                radius: 0
                                value: tile.modelData.watched / Math.max(1, tile.modelData.total)
                                color: "#80000000"
                            }

                            /* Finished */
                            Rectangle {
                                visible: tile.modelData.finished
                                anchors {
                                    right: parent.right
                                    top: parent.top
                                    margins: 10
                                }
                                width: 28
                                height: 28
                                radius: 14
                                color: root.doneColor

                                Text {
                                    anchors.centerIn: parent
                                    text: "✓"
                                    color: "#141414"
                                    font.pixelSize: 15
                                    font.bold: true
                                }
                            }

                            /* Hover: white outline */
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -3
                                radius: 8
                                color: "transparent"
                                border.color: "white"
                                border.width: 2
                                visible: tileArea.containsMouse
                            }

                            MouseArea {
                                id: tileArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showSeries(tile.modelData)
                            }
                        }

                        Text {
                            width: parent.width
                            text: tile.modelData.title
                            color: root.textColor
                            font.pixelSize: 14
                            font.bold: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.statusText(tile.modelData)
                            color: tile.modelData.finished ? root.doneColor : root.dimColor
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
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
            topMargin: 14
        }
        visible: root.current !== null
        clip: true
        contentWidth: width
        contentHeight: seriesColumn.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }

        Column {
            id: seriesColumn
            x: root.margin
            width: seriesFlick.width - 2 * root.margin
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

            /* Poster + title + actions */
            RowLayout {
                width: parent.width
                spacing: 26

                Poster {
                    Layout.preferredWidth: Math.round(150 * root.scale)
                    Layout.preferredHeight: Math.round(225 * root.scale)
                    Layout.alignment: Qt.AlignTop
                    series: root.current
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 8

                    Text {
                        Layout.fillWidth: true
                        text: root.current ? root.current.title : ""
                        color: root.textColor
                        font.pixelSize: 32
                        font.bold: true
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: root.current && root.current.native !== root.current.title ? root.current.native : ""
                        color: root.dimColor
                        font.pixelSize: 17
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.current ? (root.current.loose ?
                                                  qsTr("Loose files in the library folder") :
                                                  root.current.folderName) : ""
                        color: root.faintColor
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }

                    Text {
                        Layout.topMargin: 4
                        text: root.current ? (root.current.total === 0 ? qsTr("Extras only") :
                                              qsTr("%1 of %2 watched").arg(root.current.watched).arg(root.current.total) +
                                              (root.current.lastDate > 0 ?
                                                   " · " + qsTr("last watched %1").arg(Library.formatDate(root.current.lastDate)) : "")) : ""
                        color: root.current && root.current.finished ? root.doneColor : root.dimColor
                        font.pixelSize: 14
                    }

                    Bar {
                        Layout.preferredWidth: 320
                        visible: root.current !== null && root.current.total > 0
                        value: root.current ? root.current.watched / Math.max(1, root.current.total) : 0
                        fill: root.current && root.current.finished ? "#46d369" : "#e5383b"
                    }

                    Row {
                        Layout.topMargin: 8
                        spacing: 12

                        FlatButton {
                            visible: root.current !== null && root.current.next !== null
                            primary: true
                            fontSize: 15
                            implicitHeight: 44
                            text: root.current && root.current.next ?
                                      (root.current.resume ?
                                           qsTr("▶  Resume %1 at %2").arg(root.current.next.short).arg(Library.formatTime(root.current.next.pos)) :
                                           qsTr("▶  Play %1").arg(root.current.next.short)) : ""
                            onClicked: root.play(root.current.next, false)
                        }

                        FlatButton {
                            implicitHeight: 44
                            text: qsTr("Rename")
                            onClicked: renameDialog.openFor(root.current)
                        }

                        FlatButton {
                            implicitHeight: 44
                            text: qsTr("Change poster…")
                            onClicked: posterDialog.openFor(root.current)
                        }
                    }
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
                        topPadding: 16
                        bottomPadding: 4
                        text: section.modelData.title
                        color: section.modelData.extra ? root.dimColor : root.textColor
                        font.pixelSize: 19
                        font.bold: true
                    }

                    Item {
                        visible: section.modelData.title.length === 0
                        width: 1
                        height: 12
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
                            radius: 6
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

    /* Pick the AniList entry (poster + Japanese title) for a series */
    Dialog {
        id: posterDialog

        property string key: ""
        property var results: []
        property string error: ""
        property bool searching: false
        property var selected: null

        function openFor(series) {
            posterDialog.key = series.key;
            posterDialog.results = [];
            posterDialog.error = "";
            posterDialog.selected = null;
            posterField.text = series.guess;
            posterDialog.open();
            posterDialog.search();
        }

        function search() {
            posterDialog.searching = true;
            posterDialog.error = "";
            WatchHistory.searchAniList(posterField.text, "pick");
        }

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 820)
        height: Math.min(parent.height - 40, 640)
        modal: true
        title: qsTr("Poster from AniList")
        onAboutToShow: Utils.modalDialogs += 1
        onClosed: {
            Utils.modalDialogs -= 1;
            root.forceActiveFocus();
        }

        Connections {
            target: WatchHistory
            function onAniListResults(tag, success, results, error) {
                if (tag !== "pick") {
                    return;
                }
                posterDialog.searching = false;
                posterDialog.results = results;
                posterDialog.error = success ? (results.length === 0 ? qsTr("Nothing found.") : "") : error;
            }
        }

        footer: DialogButtonBox {
            Button {
                text: qsTr("Use this")
                highlighted: true
                enabled: posterDialog.selected !== null
                DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                onClicked: {
                    WatchHistory.setMedia(posterDialog.key, posterDialog.selected);
                    posterDialog.close();
                }
            }
            Button {
                text: qsTr("No poster")
                DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                onClicked: {
                    WatchHistory.setMedia(posterDialog.key, { none: true });
                    posterDialog.close();
                }
            }
            Button {
                text: qsTr("Cancel")
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: posterDialog.close()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: posterField
                    Layout.fillWidth: true
                    onAccepted: posterDialog.search()
                }
                Button {
                    text: posterDialog.searching ? qsTr("Searching…") : qsTr("Search")
                    enabled: !posterDialog.searching
                    onClicked: posterDialog.search()
                }
            }

            Label {
                visible: posterDialog.error.length > 0
                color: "#e06c6c"
                text: posterDialog.error
            }

            GridView {
                id: posterGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                cellWidth: 150
                cellHeight: 290
                model: posterDialog.results
                ScrollBar.vertical: ScrollBar { }

                delegate: Item {
                    id: result
                    required property var modelData
                    width: posterGrid.cellWidth
                    height: posterGrid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 6
                        color: posterDialog.selected && posterDialog.selected.id === result.modelData.id ?
                                   "#3a2a2a" : (resultArea.containsMouse ? "#2b2b2b" : "transparent")
                        border.color: posterDialog.selected && posterDialog.selected.id === result.modelData.id ?
                                          root.accent : "transparent"
                        border.width: 2
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 4

                        Image {
                            width: parent.width
                            height: width * 1.45
                            source: result.modelData.posterUrl
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 260
                        }
                        Label {
                            width: parent.width
                            text: result.modelData.title
                            font.bold: true
                            font.pixelSize: 12
                            wrapMode: Label.WordWrap
                            maximumLineCount: 2
                            elide: Label.ElideRight
                        }
                        Label {
                            width: parent.width
                            opacity: 0.7
                            font.pixelSize: 11
                            elide: Label.ElideRight
                            text: [result.modelData.format, result.modelData.year > 0 ? result.modelData.year : "",
                                   result.modelData.episodes > 0 ? qsTr("%1 eps").arg(result.modelData.episodes) : ""]
                                  .filter(x => String(x).length > 0).join(" · ")
                        }
                    }

                    MouseArea {
                        id: resultArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: posterDialog.selected = result.modelData
                        onDoubleClicked: {
                            WatchHistory.setMedia(posterDialog.key, result.modelData);
                            posterDialog.close();
                        }
                    }
                }
            }
        }
    }
}

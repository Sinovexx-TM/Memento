import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ripose.Memento

import "../definition"
import "../util/Manga.js" as Manga

/* Reads a manga volume (folder of pages) with mokuro's text: hovering a
 * bubble looks the word up in Memento's dictionary popup, and cards use the
 * page as their picture. Covers the player while open. */
Rectangle {
    id: root

    required property var player

    property var volume: null          /* from MangaLibrary.volumes() */
    property var pages: []
    property int page: 0
    property bool doublePage: WatchHistory.option("manga-double", false) === true ||
                              WatchHistory.option("manga-double", false) === "true"
    property bool showBoxes: false

    /* Reading session and progress */
    property var session: null
    property var entry: ({})
    property var readSet: ({})
    property real lastActivity: Date.now()
    property real lastTick: Date.now()
    /* Bumped when the session's numbers change, for the top bar */
    property int tick: 0

    /* Zoom: the canvas is scaled by zoom and moved by panX/panY */
    property real zoom: 1
    property real panX: 0
    property real panY: 0
    readonly property real maxZoom: 5
    /* Pan to the new page's top-right corner once its image has loaded */
    property bool alignPending: false

    readonly property int idleMs: 5 * 60 * 1000
    readonly property int newSessionMs: 30 * 60 * 1000

    signal closed(var finishedSession)

    visible: false
    color: "#0e0e0e"
    focus: visible

    /* Pages shown now: [index] or [right, left] in two-page mode */
    readonly property var shownPages: {
        if (root.pages.length === 0) {
            return [];
        }
        if (!root.doublePage || root.page === 0 || root.page + 1 >= root.pages.length) {
            return [root.page];
        }
        return [root.page, root.page + 1];
    }

    function seriesTitle() {
        return root.volume ? Manga.seriesTitle(root.volume.series) : "";
    }

    function volumeTitle() {
        return root.volume ? Manga.volumeLabel(root.volume.name) : "";
    }

    function tagName() {
        return "Manga::" + root.seriesTitle().replace(/\s+/g, "_");
    }

    function open(volume) {
        root.volume = volume;
        root.pages = MangaLibrary.loadVolume(volume.path);
        const history = MangaLibrary.history();
        root.entry = history[volume.path] ?? {};
        root.readSet = {};
        for (const p of (root.entry.read ?? [])) {
            root.readSet[p] = true;
        }
        root.page = Math.min(Math.max(0, root.entry.page ?? 0), Math.max(0, root.pages.length - 1));
        root.resetZoom();
        root.visible = true;
        root.forceActiveFocus();
        if ((root.player.state.path ?? "").length > 0 && !root.player.state.pause) {
            root.player.controller.pause();
        }
        root.startSession();
        root.pageChanged_();
    }

    function close() {
        const finished = root.endSession();
        AnkiClient.setMangaPage("", []);
        definitionPopup.clearResults();
        root.visible = false;
        root.closed(finished);
    }

    /* --- Sessions --- */

    function startSession() {
        const now = Date.now();
        root.session = {
            start: now, end: now, seconds: 0, chars: 0, pages: 0, read: {},
            series: root.seriesTitle(), volume: root.volumeTitle(), path: root.volume.path
        };
        root.lastActivity = now;
        root.lastTick = now;
    }

    /* Returns the session if it was long enough to keep, else null */
    function endSession() {
        if (!root.session) {
            return null;
        }
        const s = root.session;
        root.session = null;
        const out = {
            start: s.start, end: s.end, seconds: Math.round(s.seconds), chars: s.chars,
            pages: s.pages, series: s.series, volume: s.volume
        };
        root.saveProgress();
        return MangaLibrary.finishSession(out) ? out : null;
    }

    function saveOpenSession() {
        if (!root.session) {
            return;
        }
        const s = root.session;
        MangaLibrary.saveOpenSession({
            start: s.start, end: s.end, seconds: Math.round(s.seconds), chars: s.chars,
            pages: s.pages, series: s.series, volume: s.volume
        });
    }

    function activity() {
        const now = Date.now();
        if (root.session && now - root.lastActivity > root.newSessionMs) {
            /* Came back after a long break: that was a separate session */
            const finished = root.endSession();
            if (finished) {
                root.player.mangaToggl.ask(finished);
            }
            root.startSession();
        }
        root.lastActivity = now;
    }

    function saveProgress() {
        if (!root.volume) {
            return;
        }
        const read = Object.keys(root.readSet).map(Number);
        let chars = 0;
        for (const p of read) {
            if (root.pages[p]) {
                chars += Manga.pageChars(root.pages[p]);
            }
        }
        const last = root.shownPages.length > 0 ? root.shownPages[root.shownPages.length - 1] : 0;
        root.entry = {
            page: root.page,
            pages: root.pages.length,
            read: read,
            chars: chars,
            seconds: Math.round((root.entry.seconds ?? 0) + (root.session ? root.session.seconds - (root.session.saved ?? 0) : 0)),
            lastDate: Date.now(),
            done: (root.entry.done ?? false) || last >= root.pages.length - 1
        };
        if (root.session) {
            root.session.saved = root.session.seconds;
        }
        MangaLibrary.saveProgress(root.volume.path, root.entry);
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible && root.session !== null
        onTriggered: {
            const now = Date.now();
            const elapsed = now - root.lastTick;
            root.lastTick = now;
            if (Qt.application.state !== Qt.ApplicationActive) {
                return;
            }
            root.session.seconds = Manga.addActive(root.session.seconds, now, root.lastActivity, elapsed, root.idleMs);
            if (now - root.lastActivity <= root.idleMs) {
                root.session.end = now;
            }
            root.tick += 1;
            if (Math.floor(root.session.seconds) % 30 === 0) {
                root.saveOpenSession();
            }
        }
    }

    /* --- Pages --- */

    function pageChanged_() {
        if (root.session) {
            for (const p of root.shownPages) {
                if (!root.session.read[p]) {
                    root.session.read[p] = true;
                    root.session.pages += 1;
                    root.session.chars += Manga.pageChars(root.pages[p]);
                }
                root.readSet[p] = true;
            }
            root.saveOpenSession();
            root.saveProgress();
            root.tick += 1;
        }
        definitionPopup.clearResults();
        if (root.shownPages.length > 0) {
            AnkiClient.setMangaPage(root.pages[root.shownPages[0]].file, [root.tagName()]);
        }
    }

    function go(index) {
        const target = Math.min(Math.max(0, index), Math.max(0, root.pages.length - 1));
        if (target === root.page) {
            return;
        }
        root.page = target;
        root.activity();
        root.pageChanged_();
        /* Keep the zoom level, start the new page at its top-right corner */
        if (root.zoom > 1) {
            root.alignPending = true;
            Qt.callLater(root.alignTopRight);
        }
    }

    /* --- Zoom --- */

    function clampPan() {
        root.panX = Math.min(0, Math.max(root.width - root.width * root.zoom, root.panX));
        root.panY = Math.min(0, Math.max(root.height - root.height * root.zoom, root.panY));
    }

    function resetZoom() {
        root.zoom = 1;
        root.panX = 0;
        root.panY = 0;
        root.alignPending = false;
    }

    /* Zoom to `z`, keeping the point (x, y) of the reader where it is */
    function zoomAt(z, x, y) {
        z = Math.min(root.maxZoom, Math.max(1, z));
        const cx = (x - root.panX) / root.zoom;
        const cy = (y - root.panY) / root.zoom;
        root.zoom = z;
        root.panX = x - cx * z;
        root.panY = y - cy * z;
        root.clampPan();
        if (z === 1) {
            root.panX = 0;
            root.panY = 0;
        }
    }

    function alignTopRight() {
        if (!root.alignPending || root.zoom <= 1) {
            return;
        }
        /* The right-hand page (first in the row) holds the page's start */
        const item = pageRepeater.itemAt(0);
        const rect = item ? item.paintedRect() : null;
        if (!rect || rect.width <= 0) {
            return;               /* not loaded yet; the image's onStatusChanged retries */
        }
        root.alignPending = false;
        root.panX = root.width - (rect.x + rect.width) * root.zoom;
        root.panY = -rect.y * root.zoom;
        root.clampPan();
    }

    /* True if the reader point (x, y) is on a page, not the black around it */
    function onPage(x, y) {
        for (let i = 0; i < pageRepeater.count; i++) {
            const item = pageRepeater.itemAt(i);
            if (item && item.containsReaderPoint(x, y)) {
                return true;
            }
        }
        return false;
    }

    /* Fork (Yomitan overlay): text of the pages shown, see overlayBlocks */
    function overlayBlocks(target) {
        let out = [];
        for (let i = 0; i < pageRepeater.count; i++) {
            const item = pageRepeater.itemAt(i);
            if (item) {
                out = out.concat(item.overlayBlocks(target));
            }
        }
        return out;
    }

    /* Looking words up in the overlay counts as reading */
    Connections {
        target: YomitanOverlay
        enabled: root.visible
        function onHoverChanged() { root.activity(); }
        function onPopupOpenChanged() { root.activity(); }
    }

    onWidthChanged: clampPan()
    onHeightChanged: clampPan()

    function next() {
        root.go(root.page + root.shownPages.length);
    }

    function previous() {
        if (root.doublePage && root.page > 1) {
            root.go(root.page - 2);
        } else {
            root.go(root.page - 1);
        }
    }

    function toggleDouble() {
        root.doublePage = !root.doublePage;
        WatchHistory.setOption("manga-double", root.doublePage);
        root.pageChanged_();
    }

    Keys.onPressed: event => {
        root.activity();
        switch (event.key) {
        case Qt.Key_Left:
            root.next();
            break;
        case Qt.Key_Right:
            root.previous();
            break;
        case Qt.Key_Home:
            root.go(0);
            break;
        case Qt.Key_End:
            root.go(root.pages.length - 1);
            break;
        case Qt.Key_D:
            root.toggleDouble();
            break;
        case Qt.Key_Escape:
            if (definitionPopup.visible) {
                definitionPopup.clearResults();
            } else {
                root.close();
            }
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    /* Click the page: zoom in there / back out. Click the black around it:
     * left = next page (right to left), right = back. Wheel zooms, drag pans. */
    MouseArea {
        id: readerMouse
        property real pressX: 0
        property real pressY: 0
        property real startPanX: 0
        property real startPanY: 0
        property bool dragged: false
        property bool overEdge: false

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        hoverEnabled: true
        cursorShape: dragged ? Qt.ClosedHandCursor :
                     overEdge ? Qt.PointingHandCursor :
                     root.zoom > 1 ? Qt.OpenHandCursor : Qt.ArrowCursor

        onPressed: mouse => {
            pressX = mouse.x;
            pressY = mouse.y;
            startPanX = root.panX;
            startPanY = root.panY;
            dragged = false;
        }
        onPositionChanged: mouse => {
            root.activity();
            if (pressed && root.zoom > 1) {
                if (!dragged && Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY) > 6) {
                    dragged = true;
                    definitionPopup.clearResults();
                }
                if (dragged) {
                    root.panX = startPanX + mouse.x - pressX;
                    root.panY = startPanY + mouse.y - pressY;
                    root.clampPan();
                }
            }
            overEdge = !pressed && !root.onPage(mouse.x, mouse.y);
        }
        onReleased: mouse => {
            if (dragged) {
                dragged = false;
                return;
            }
            root.activity();
            if (!root.onPage(mouse.x, mouse.y)) {
                if (mouse.x < root.width / 2) {
                    root.next();
                } else {
                    root.previous();
                }
            } else if (root.zoom > 1) {
                root.resetZoom();
            } else {
                root.zoomAt(2.5, mouse.x, mouse.y);
            }
            definitionPopup.clearResults();
            overEdge = !root.onPage(mouse.x, mouse.y);
        }
        onWheel: wheel => {
            root.activity();
            const steps = wheel.angleDelta.y / 120;
            if (steps !== 0) {
                definitionPopup.clearResults();
                root.alignPending = false;
                root.zoomAt(root.zoom * Math.pow(1.2, steps), wheel.x, wheel.y);
            }
        }
    }

    /* Everything that zooms */
    Item {
        id: canvas
        width: root.width
        height: root.height
        transform: [
            Scale { xScale: root.zoom; yScale: root.zoom },
            Translate { x: root.panX; y: root.panY }
        ]

    /* Pages, right to left */
    Row {
        id: spread
        anchors.centerIn: parent
        layoutDirection: Qt.RightToLeft
        spacing: 0

        Repeater {
            id: pageRepeater
            model: root.shownPages

            delegate: Item {
                id: pageItem
                required property int modelData
                readonly property var pageData: root.pages[modelData] ?? null

                width: (root.width - 20) / root.shownPages.length
                height: root.height - 20
                /* Two pages meet in the middle */
                readonly property int align: root.shownPages.length === 1 ? Image.AlignHCenter :
                    (index === 0 ? Image.AlignLeft : Image.AlignRight)
                required property int index

                /* The drawn page in canvas coordinates (before zoom) */
                function paintedRect() {
                    if (pageImage.paintedWidth <= 0) {
                        return null;
                    }
                    const p = pageImage.mapToItem(canvas, pageImage.offX, pageImage.offY);
                    return Qt.rect(p.x, p.y, pageImage.paintedWidth, pageImage.paintedHeight);
                }

                /* Fork (Yomitan overlay): this page's text with every
                 * character's box, relative to `target` (zoom and pan
                 * included). One overlay line per mokuro line. */
                function overlayBlocks(target) {
                    const out = [];
                    if (!pageItem.pageData || pageImage.paintedWidth <= 0) {
                        return out;
                    }
                    const s = pageImage.scale_;
                    for (const block of pageItem.pageData.blocks || []) {
                        const lines = [];
                        const blockLines = block.lines || [];
                        let offset = 0;
                        for (let i = 0; i < blockLines.length; ++i) {
                            const text = String(blockLines[i]);
                            const rects = [];
                            for (let k = 0; k < text.length; ++k) {
                                const r = Manga.charRect(block, offset + k);
                                if (!r) {
                                    rects.push(null);
                                    continue;
                                }
                                const p0 = pageItem.mapToItem(target, pageImage.offX + r.x * s, pageImage.offY + r.y * s);
                                const p1 = pageItem.mapToItem(target, pageImage.offX + (r.x + r.w) * s,
                                                              pageImage.offY + (r.y + r.h) * s);
                                rects.push([p0.x, p0.y, p1.x - p0.x, p1.y - p0.y]);
                            }
                            offset += text.length;
                            lines.push({ text: text, rects: rects });
                        }
                        out.push({ vertical: !!block.vertical, lines: lines });
                    }
                    return out;
                }

                function containsReaderPoint(x, y) {
                    const p = pageImage.mapFromItem(root, x, y);
                    return pageImage.paintedWidth > 0 &&
                           p.x >= pageImage.offX && p.x <= pageImage.offX + pageImage.paintedWidth &&
                           p.y >= pageImage.offY && p.y <= pageImage.offY + pageImage.paintedHeight;
                }

                Image {
                    id: pageImage
                    anchors.fill: parent
                    source: pageItem.pageData ? pageItem.pageData.image : ""
                    fillMode: Image.PreserveAspectFit
                    horizontalAlignment: pageItem.align
                    asynchronous: true
                    smooth: true
                    mipmap: true
                    cache: false
                    onStatusChanged: {
                        if (status === Image.Ready) {
                            Qt.callLater(root.alignTopRight);
                        }
                    }

                    readonly property real srcW: pageItem.pageData && pageItem.pageData.w > 0 ? pageItem.pageData.w : sourceSize.width
                    readonly property real srcH: pageItem.pageData && pageItem.pageData.h > 0 ? pageItem.pageData.h : sourceSize.height
                    readonly property real scale_: srcW > 0 ? paintedWidth / srcW : 1
                    readonly property real offX: horizontalAlignment === Image.AlignLeft ? 0 :
                        horizontalAlignment === Image.AlignRight ? width - paintedWidth : (width - paintedWidth) / 2
                    readonly property real offY: (height - paintedHeight) / 2
                }

                /* Text boxes */
                Repeater {
                    model: pageItem.pageData ? pageItem.pageData.blocks : []
                    delegate: Item {
                        id: blockItem
                        required property var modelData
                        readonly property string key: (pageItem.pageData ? pageItem.pageData.file : "") + "|" + modelData.box.join(",")
                        x: pageImage.offX + modelData.box[0] * pageImage.scale_
                        y: pageImage.offY + modelData.box[1] * pageImage.scale_
                        width: (modelData.box[2] - modelData.box[0]) * pageImage.scale_
                        height: (modelData.box[3] - modelData.box[1]) * pageImage.scale_

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.width: 1
                            border.color: "#80ff5050"
                            visible: root.showBoxes || blockHover.hovered
                            radius: 2
                        }

                        /* Selection highlight */
                        Rectangle {
                            readonly property bool active: definitionPopup.blockKey === blockItem.key &&
                                                           definitionPopup.selectionRect !== null
                            visible: active
                            color: "#4d6ea8fe"
                            x: active ? definitionPopup.selectionRect.x * pageImage.scale_ + pageImage.offX - blockItem.x : 0
                            y: active ? definitionPopup.selectionRect.y * pageImage.scale_ + pageImage.offY - blockItem.y : 0
                            width: active ? definitionPopup.selectionRect.w * pageImage.scale_ : 0
                            height: active ? definitionPopup.selectionRect.h * pageImage.scale_ : 0
                        }

                        HoverHandler {
                            id: blockHover
                            cursorShape: Qt.IBeamCursor
                            onPointChanged: {
                                if (!hovered) {
                                    return;
                                }
                                root.activity();
                                if (YomitanOverlay.active) {
                                    return;   /* Yomitan does the lookups */
                                }
                                const p = point.position;
                                const ix = (blockItem.x + p.x - pageImage.offX) / pageImage.scale_;
                                const iy = (blockItem.y + p.y - pageImage.offY) / pageImage.scale_;
                                const hit = Manga.hitTest(blockItem.modelData, ix, iy);
                                if (hit) {
                                    definitionPopup.hover(blockItem.modelData, hit, pageItem.pageData,
                                                          blockItem.mapToItem(root, p.x, p.y));
                                }
                            }
                            onHoveredChanged: {
                                if (!hovered) {
                                    popupLeaveTimer.restart();
                                } else {
                                    popupLeaveTimer.stop();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    }

    Text {
        anchors.centerIn: parent
        visible: root.pages.length === 0
        text: qsTr("No pages found.")
        color: "#8a8a8a"
        font.pixelSize: 16
    }

    /* Top bar, shown while the cursor is near the top */
    Rectangle {
        id: topBar
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: 52
        color: "#d0141414"
        opacity: topHover.hovered || root.pages.length === 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        HoverHandler {
            id: topHover
        }
        /* Clicks on the bar don't reach the page */
        MouseArea {
            anchors.fill: parent
            enabled: topBar.opacity > 0
        }

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 16
                rightMargin: 16
            }
            spacing: 10

            BackArrow {
                tip: qsTr("Back to Manga")
                onClicked: root.close()
            }
            Text {
                Layout.fillWidth: true
                text: root.seriesTitle() + "  ·  " + root.volumeTitle() +
                      (root.volume && !root.volume.mokuro ? "  ·  " + qsTr("no text (run mokuro)") : "")
                color: "#f2f2f2"
                font.pixelSize: 15
                font.bold: true
                elide: Text.ElideRight
            }
            Text {
                text: root.pages.length > 0 ?
                          qsTr("Page %1 / %2").arg(root.shownPages.map(p => p + 1).join("–")).arg(root.pages.length) : ""
                color: "#a3a3a3"
                font.pixelSize: 13
            }
            Text {
                text: root.tick >= 0 && root.session ? Manga.formatMinutes(root.session.seconds) + "  ·  " +
                                     root.session.chars + " " + qsTr("chars") : ""
                color: "#a3a3a3"
                font.pixelSize: 13
            }
            ReaderButton {
                visible: root.zoom > 1
                text: Math.round(root.zoom * 100) + "%  ·  " + qsTr("Fit")
                onClicked: root.resetZoom()
            }
            ReaderButton {
                text: root.doublePage ? qsTr("Two pages") : qsTr("One page")
                onClicked: root.toggleDouble()
            }
            ReaderButton {
                text: root.showBoxes ? qsTr("Hide boxes") : qsTr("Show boxes")
                onClicked: root.showBoxes = !root.showBoxes
            }
        }
    }

    /* Page slider at the bottom while hovered */
    Item {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 44
        opacity: bottomHover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        HoverHandler {
            id: bottomHover
        }
        MouseArea {
            anchors.fill: parent
            enabled: bottomHover.hovered
        }

        Slider {
            anchors {
                fill: parent
                leftMargin: 24
                rightMargin: 24
            }
            from: Math.max(0, root.pages.length - 1)
            to: 0                     /* right to left */
            stepSize: 1
            value: root.page
            onMoved: root.go(Math.round(value))
        }
    }

    component ReaderButton: Rectangle {
        id: button
        property string text: ""
        signal clicked()
        implicitWidth: label.implicitWidth + 24
        implicitHeight: 32
        radius: 4
        color: area.containsMouse ? "#4d4d4d" : "#2e2e2e"
        Text {
            id: label
            anchors.centerIn: parent
            text: button.text
            color: "#f2f2f2"
            font.pixelSize: 13
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    /* --- Dictionary popup --- */

    Timer {
        id: popupLeaveTimer
        interval: 400
        onTriggered: {
            if (!popupHover.hovered) {
                definitionPopup.clearResults();
            }
        }
    }

    Timer {
        id: searchTimer
        interval: MementoSettings.searchDelay
        onTriggered: definitionPopup.search()
    }

    Popup {
        id: definitionPopup

        property var block: null
        property string blockKey: ""
        property var pendingHit: null
        property var pendingPage: null
        property point cursor: Qt.point(0, 0)
        property string lastKey: ""
        property var selectionRect: null

        readonly property bool shouldOpen: dictionarySearch.terms.length > 0 || dictionarySearch.kanji

        parent: root
        width: MementoSettings.interfacePopupWidth
        height: MementoSettings.interfacePopupHeight
        closePolicy: Popup.NoAutoClose
        x: Math.min(Math.max(0, cursor.x + 24), root.width - width)
        y: {
            let ideal = cursor.y - height / 3;
            ideal = Math.max(0, ideal);
            return Math.min(ideal, root.height - height);
        }
        padding: 0
        topInset: 0
        bottomInset: 0
        leftInset: 0
        rightInset: 0
        background: Item {
            Repeater {
                model: [0.23, 0.19, 0.156, 0.12, 0.09, 0.071, 0.05, 0.036, 0.024, 0.018, 0.01, 0.006]
                Rectangle {
                    required property int index
                    required property real modelData
                    anchors.fill: parent
                    anchors.margins: -(index + 1)
                    radius: 8 + index + 1
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, modelData)
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: PopupPalette.window
            }
        }

        onShouldOpenChanged: shouldOpen ? open() : close()

        function hover(block, hit, pageData, cursorPoint) {
            const blockKey = pageData.file + "|" + block.box.join(",");
            const key = blockKey + "|" + hit.index;
            if (key === definitionPopup.lastKey) {
                return;
            }
            definitionPopup.lastKey = key;
            definitionPopup.pendingHit = { block: block, hit: hit, page: pageData, key: blockKey };
            definitionPopup.cursor = cursorPoint;
            searchTimer.restart();
        }

        function search() {
            const pending = definitionPopup.pendingHit;
            if (!pending) {
                return;
            }
            definitionPopup.block = pending.block;
            definitionPopup.blockKey = pending.key;
            definitionPopup.selectionRect = null;
            AnkiClient.setMangaPage(pending.page.file, [root.tagName()]);
            definitionPage.resetStack();
            const text = pending.hit.text;
            const index = pending.hit.index;
            dictionarySearch.searchTerms(text.substring(index), text, index);
            dictionarySearch.searchKanji(text.charAt(index), text, index);
        }

        function updateSelection() {
            const pending = definitionPopup.pendingHit;
            if (!pending || (dictionarySearch.terms.length === 0 && dictionarySearch.kanji === null)) {
                definitionPopup.selectionRect = null;
                return;
            }
            const length = dictionarySearch.terms.length > 0 ? dictionarySearch.terms[0].clozeBody.length : 1;
            const first = Manga.charRect(pending.block, pending.hit.index);
            const last = Manga.charRect(pending.block, pending.hit.index + Math.max(1, length) - 1);
            if (!first || !last) {
                definitionPopup.selectionRect = first;
                return;
            }
            const x0 = Math.min(first.x, last.x), y0 = Math.min(first.y, last.y);
            const x1 = Math.max(first.x + first.w, last.x + last.w), y1 = Math.max(first.y + first.h, last.y + last.h);
            /* A word that wraps to the next line: just highlight its start */
            definitionPopup.selectionRect = (first.x === last.x || first.y === last.y) ?
                { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : first;
        }

        function clearResults() {
            definitionPopup.lastKey = "";
            definitionPopup.pendingHit = null;
            definitionPopup.selectionRect = null;
            definitionPopup.block = null;
            definitionPopup.blockKey = "";
            searchTimer.stop();
            definitionPage.resetStack();
            dictionarySearch.clearResults();
        }

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: 8
            border.color: "#57575f"
            border.width: 1

            HoverHandler {
                id: popupHover
                onHoveredChanged: hovered ? popupLeaveTimer.stop() : popupLeaveTimer.restart()
            }

            DefinitionPage {
                id: definitionPage
                anchors.fill: parent
                anchors.margins: 3
                search: dictionarySearch
                onClosePressed: definitionPopup.clearResults()
            }
        }

        Connections {
            target: dictionarySearch
            function onTermsChanged() { definitionPopup.updateSelection(); }
            function onKanjiChanged() { definitionPopup.updateSelection(); }
        }
    }

    DictionarySearch {
        id: dictionarySearch
    }
}

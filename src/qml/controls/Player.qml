import QtQuick
import QtQuick.Controls
import Ripose.Memento

import "../definition"

MpvPlayer {
    id: root

    readonly property bool oscVisible:
        !root.ocrMode && (
            controls.visible ||
            (!Features.isMacos && menu.visible)
        )
    readonly property bool oscHovered:
        !root.ocrMode && (
            subtitleHover.hovered ||
            YomitanOverlay.hover ||
            YomitanOverlay.popupHover ||
            (!Features.isMacos && menu.anyHovered) ||
            controls.menuOpen ||
            controlsHover.hovered
        )

    readonly property bool pause: root.state.pause

    /* Toggl episode logging; Main.qml asks it before quitting */
    property alias toggl: togglLogger

    /* Subtitle matching; the Subtitle menu opens its folder rename */
    property alias subMatcher: subMatcher

    /* Anime library and watch history */
    property alias library: libraryView
    property alias watchTracker: watchTracker
    property alias malView: malView

    /* Manga reader (mokuro) and its Toggl prompt */
    property alias mangaView: mangaView
    property alias mangaListView: mangaListView
    property alias mangaToggl: mangaToggl

    property point cursorPosition: Qt.point(0, 0)

    property bool ocrMode: false

    /* True while the player is paused because the cursor hovered the subtitles
     * (searchPauseOnHover). Cleared as soon as playback resumes for any reason,
     * so a manual pause is never undone by resumeAfterHoverPause(). */
    property bool hoverPaused: false

    /* When the hover pause was started (ms since epoch) */
    property double hoverPauseTime: 0

    signal auxiliarySearchRequested(string text)

    enum OscVisibility
    {
        OscAuto,
        OscVisible,
        OscHidden
    }

    property int oscVisibility: Player.OscAuto

    /* Options window, for screens that cover the menu bar */
    /* Where the last line jump went, so quick repeated presses add up
     * before mpv reports the new position */
    property real lineJumpTarget: -1
    property real lineJumpAt: 0

    /**
     * Jump to the previous (-1) or next (1) dialogue line. Uses the subtitle
     * list's times when it has the line (external subtitle files are known
     * in full), so lines that haven't been played yet work too; otherwise
     * mpv's sub-seek, which only knows lines it has already read.
     */
    function jumpLine(direction) {
        const model = SubtitleLists.primary;
        let pos = root.state.timePosition;
        if (root.lineJumpTarget >= 0 && Date.now() - root.lineJumpAt < 1500) {
            pos = root.lineJumpTarget;
        }
        const eps = 0.05;
        let target = -1;
        if (model) {
            const starts = [];
            for (let r = 0; r < model.rowCount(); ++r) {
                const index = model.index(r, 0);
                const text = model.data(index, SubtitleListModel.TextRole) ?? "";
                if (text.trim().length > 0) {
                    starts.push(model.data(index, SubtitleListModel.StartRole));
                }
            }
            if (direction > 0) {
                for (const s of starts) {
                    if (s > pos + eps && (target < 0 || s < target)) {
                        target = s;
                    }
                }
            } else {
                /* Start of the current line, then the line before it */
                let current = -1;
                for (const s of starts) {
                    if (s <= pos + eps && s > current) {
                        current = s;
                    }
                }
                for (const s of starts) {
                    if (s < current - eps && s > target) {
                        target = s;
                    }
                }
            }
        }
        if (target >= 0) {
            root.lineJumpTarget = target;
            root.lineJumpAt = Date.now();
            root.controller.seek(target);
        } else {
            root.lineJumpTarget = -1;
            root.controller.subtitleSeek(direction, true);
        }
    }

    function openOptions() {
        menu.openOptions();
    }

    /**
     * Shows the OSC with fade in.
     */
    function showOsc() {
        if (root.ocrMode)
        {
            return;
        }

        if (root.oscVisibility === Player.OscHidden)
        {
            return;
        }

        if (!Features.isMacos)
        {
            menuFadeOut.stop();
            menuFadeIn.start();
        }
        controlsFadeOut.stop();
        controlsFadeIn.start();
    }

    /**
     * Hides the OSC with fade out.
     *
     * @param force Unconditionally hide the OSC if true.
     */
    function hideOsc(force) {
        if (!force && root.oscVisibility === Player.OscVisible)
        {
            return;
        }

        if (!Features.isMacos)
        {
            menuFadeIn.stop();
            menuFadeOut.start();
        }
        controlsFadeIn.stop();
        controlsFadeOut.start();
    }

    /**
     * Put the player into OCR mode.
     */
    function startOcrMode() {
        ocrOverlay.start();
    }

    /**
     * Get the player out of OCR mode.
     */
    function cancelOcrMode() {
        ocrOverlay.cancel();
    }

    /**
     * Handles mouse movement.
     */
    function mouseMoved(x, y) {
        root.controller.sendMouse(x, y);
        cursorTimer.restart();
    }

    /**
     * Resumes playback if it was paused by hovering the subtitles, the cursor
     * is no longer on them and no dictionary popup is open.
     */
    function resumeAfterHoverPause() {
        if (!root.hoverPaused)
        {
            return;
        }
        if (!MementoSettings.searchResumeOnHoverExit)
        {
            root.hoverPaused = false;
            return;
        }
        if (subtitleHover.hovered || definitionPopup.visible ||
                YomitanOverlay.hover || YomitanOverlay.popupHover ||
                YomitanOverlay.popupOpen || Utils.modalDialogs > 0)
        {
            return;
        }
        root.hoverPaused = false;
        if (root.state.pause)
        {
            root.controller.play();
        }
    }

    /* After a lookup the popup stays open on its own. When the video was
     * paused by hovering, close it once the cursor is on neither the
     * subtitles nor the popup, so playback can resume. The wait lets the
     * cursor cross the gap between the subtitles and the popup. */
    Timer {
        id: popupLeaveTimer
        interval: 400
        onTriggered: {
            if (root.hoverPaused &&
                    MementoSettings.searchResumeOnHoverExit &&
                    definitionPopup.visible &&
                    !subtitleHover.hovered &&
                    !popupHover.hovered &&
                    Utils.modalDialogs === 0)
            {
                definitionPopup.clearResults();
            }
        }
    }

    /* Fork (Yomitan overlay): the subtitles count as hovered while the
     * cursor is on the overlay's copy of them */
    readonly property bool textHovered: subtitleHover.hovered || YomitanOverlay.hover

    onTextHoveredChanged: {
        if (!root.textHovered)
        {
            hoverResumeTimer.restart();
            popupLeaveTimer.restart();
            overlayLeaveTimer.restart();
        }
        else if (MementoSettings.searchPauseOnHover)
        {
            hoverResumeTimer.stop();
            popupLeaveTimer.stop();
            overlayLeaveTimer.stop();
            /* Only a pause started here may be resumed automatically */
            if (!root.state.pause)
            {
                root.hoverPaused = true;
                root.hoverPauseTime = Date.now();
            }
            root.controller.pause();
        }
    }

    /* Like popupLeaveTimer, for Yomitan's popup: close it once the cursor
     * is on neither the subtitles nor the popup, so playback can resume */
    Timer {
        id: overlayLeaveTimer
        interval: 400
        onTriggered: {
            /* Any pause (hover or manual): leaving the word closes it */
            if (YomitanOverlay.popupOpen &&
                    !root.textHovered &&
                    !YomitanOverlay.popupHover &&
                    Utils.modalDialogs === 0)
            {
                YomitanOverlay.closePopup();
            }
        }
    }

    Connections {
        target: YomitanOverlay
        function onHoverChanged() {
            if (YomitanOverlay.hover || YomitanOverlay.popupHover)
            {
                overlayLeaveTimer.stop();
            }
            else
            {
                overlayLeaveTimer.restart();
            }
        }
        function onPopupHoverChanged() {
            onHoverChanged();
        }
        function onPopupOpenChanged() {
            if (!YomitanOverlay.popupOpen)
            {
                interactiveTimer.restart();
                hoverResumeTimer.restart();
            }
        }
        function onNoteAdded(info) {
            root.fillYomitanNote(info);
        }
    }

    /**
     * Fork: Yomitan added a card. Memento adds what it knows (sentence
     * audio, screenshot or manga page, title...) to its empty fields, after
     * the card builder when that is on (video only).
     * @param info {time, fields} from the overlay; time 0 = newest card.
     */
    function fillYomitanNote(info) {
        const reading = mangaView.visible && mangaView.reader.visible;
        const time = info.time ?? 0;
        if (!reading && MementoSettings.searchCardBuilder)
        {
            overlayCardBuilder.noteTime = time;
            if (overlayCardBuilder.openForHeadword(root.headwordOf(info.fields ?? {})))
            {
                return;
            }
        }
        root.fillNoteNow(time);
    }

    function headwordOf(fields) {
        for (const name in fields)
        {
            const value = String(fields[name]).replace(/<[^>]*>/g, "").trim();
            if (value.length > 0)
            {
                return value;
            }
        }
        return "";
    }

    function fillNoteNow(time) {
        AnkiClient.fillNewNote(time).then(function(result) {
            if (!result.success)
            {
                root.controller.showText(qsTr("Card not filled: %1").arg(result.error));
            }
            else if (result.filled.length > 0)
            {
                root.controller.showText(qsTr("Card filled: %1").arg(result.filled.join(", ")));
            }
            else
            {
                root.controller.showText(qsTr("Card added (no empty fields to fill)"));
            }
        });
    }

    CardBuilderDialog {
        id: overlayCardBuilder
        property double noteTime: 0
        onAccepted: {
            root.fillNoteNow(overlayCardBuilder.noteTime);
            AnkiClient.clearCardBuilderOverride();
        }
        /* Resume (if the hover paused it) only once the builder is closed */
        onClosed: hoverResumeTimer.restart()
    }

    YomitanOverlayFeeder {
        player: root
        subtitleItem: subtitleText
        mangaView: mangaView
        blocked: libraryView.visible || malView.visible || mangaListView.visible ||
                 (mangaView.visible && !mangaView.reader.visible) || root.ocrMode
    }

    /* Waits a moment before resuming so that a brief slip of the cursor off
     * the subtitles (which would pause/resume and clear the popup results)
     * does not interrupt lookups. */
    Timer {
        id: hoverResumeTimer
        interval: 350
        onTriggered: root.resumeAfterHoverPause()
    }

    onFileLoaded: {
        if (MementoSettings.searchHideMpvSubs)
        {
            root.controller.setSubtitleVisibility(false);
        }
    }

    Keys.onPressed: function(event) {
        if (root.ocrMode && event.key === Qt.Key_Escape)
        {
            root.cancelOcrMode();
            event.accepted = true;
            return;
        }
        /* ← →: seek by seconds or jump a subtitle line (Options > Behavior) */
        if ((event.key === Qt.Key_Left || event.key === Qt.Key_Right) &&
            event.modifiers === Qt.NoModifier)
        {
            const direction = event.key === Qt.Key_Left ? -1 : 1;
            if (WatchHistory.option("arrow-mode", "seconds") === "lines")
            {
                root.jumpLine(direction);
            }
            else
            {
                const seconds = Number(WatchHistory.option("arrow-seconds", 5));
                root.controller.command(["seek", String(direction * seconds), "exact"]);
            }
            event.accepted = true;
            return;
        }
        root.controller.sendKeyPress(event.key, event.modifiers);
    }

    onCursorPositionChanged: root.mouseMoved(root.cursorPosition.x, root.cursorPosition.y)

    onOscVisibilityChanged: {
        switch (root.oscVisibility)
        {
        case Player.OscAuto:
            interactiveTimer.restart();
            break;

        case Player.OscVisible:
            root.showOsc();
            break;

        case Player.OscHidden:
            root.hideOsc();
            break;
        }
    }

    Action {
        id: cycleOscVisibilityAction
        shortcut: MementoSettings.keybinds.profile?.oscVisibility
        onTriggered: {
            const oscVisibilityText = qsTr("OSC Visibility: %1");

            switch (root.oscVisibility)
            {
            case Player.OscAuto:
                root.oscVisibility = Player.OscVisible;
                root.controller.showText(oscVisibilityText.arg(qsTr("Visible")));
                break;

            case Player.OscVisible:
                root.oscVisibility = Player.OscHidden;
                root.controller.showText(oscVisibilityText.arg(qsTr("Hidden")));
                break;

            case Player.OscHidden:
                root.oscVisibility = Player.OscAuto;
                root.controller.showText(oscVisibilityText.arg(qsTr("Auto")));
                break;
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        propagateComposedEvents: true
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: root.oscHovered ? Qt.ArrowCursor : cursorTimer.cursorShape
        enabled: !root.ocrMode

        onPositionChanged: function(event) {
            root.cursorPosition = Qt.point(event.x, event.y);
            event.accepted = false;
        }

        onPressed: function(event) {
            root.controller.sendMouseButton(
                event.x,
                event.y,
                event.button,
                event.modifiers,
                true
            );
        }

        onReleased: function(event) {
            root.controller.sendMouseButton(
                event.x,
                event.y,
                event.button,
                event.modifiers,
                false
            );
        }

        onCanceled: root.controller.releaseMouseButtons()

        onClicked: function(event) {
            /* This hack makes it so keys are still handled and the player has focus */
            root.forceActiveFocus();
            root.focus = false;
            root.forceActiveFocus();

            definitionPopup.clearResults();
            event.accepted = false;
        }
    }

    /* This handler is needed because the itemCursor Items block
     * onPositionChanged in MouseArea */
    HoverHandler {
        id: hoverHandler

        readonly property point position: hoverHandler.point.position

        onPositionChanged: root.cursorPosition = Qt.point(position.x, position.y)
    }

    WheelHandler {
        enabled: !root.ocrMode
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            root.controller.sendWheel(event.x, event.y, event.angleDelta);
        }
    }

    Timer {
        id: interactiveTimer
        interval: MementoSettings.behaviorOscDuration
        repeat: false
        running: false
        onTriggered: {
            if (!root.oscHovered && !definitionPopup.visible && !YomitanOverlay.popupOpen)
            {
                root.hideOsc();
            }
        }
    }

    MoveTimer {
        id: minMouseMoveTimer
        running: !root.ocrMode
        minMovement: MementoSettings.behaviorOscMinMove
        cursorPosition: root.cursorPosition
        onMouseMoved: {
            interactiveTimer.restart();
            /* Moving over the subtitles (to look words up) must not bring
             * the controls or the title up */
            if (!root.oscVisible &&
                    !subtitleHover.hovered &&
                    subtitleText.hoverIndex === -1)
            {
                root.showOsc();
            }
        }
    }

    CursorTimer {
        id: cursorTimer
        player: root
    }

    onOscHoveredChanged: {
        interactiveTimer.restart();
        cursorTimer.restart();
    }

    /* Inhibit the screensaver during playback */
    Screensaver {
        id: screensaver
    }
    onPauseChanged: {
        if (!root.state.pause)
        {
            root.hoverPaused = false;
            /* Playback resumed: Yomitan's popup goes, unless it's in use */
            if (YomitanOverlay.popupOpen && !YomitanOverlay.popupHover &&
                    Utils.modalDialogs === 0)
            {
                YomitanOverlay.closePopup();
            }
        }
        if (root.state.pause)
        {
            screensaver.uninhibit();
        }
        else
        {
            screensaver.inhibit(qsTr("Playing media"));
        }
    }

    /* Implements subtitle cursor show */
    Item {
        id: itemCursorSubtitleShow

        readonly property bool show: hoverCursorSubtitleShow.hovered ||
                                     subtitleHover.hovered ||
                                     subtitleText.hoverIndex !== -1 || // This prevents flashing on edges
                                     controlsHover.hovered ||
                                     YomitanOverlay.hover ||
                                     YomitanOverlay.popupHover ||
                                     YomitanOverlay.popupOpen

        anchors {
            left: root.left
            right: root.right
            bottom: root.bottom
        }
        height: root.height * 0.25
        focusPolicy: Qt.NoFocus
        visible: MementoSettings.behaviorSubtitleCursorShow

        HoverHandler {
            id: hoverCursorSubtitleShow
        }
    }

    /* Implements secondary subtitle cursor show */
    Item {
        id: itemCursorSecondarySubtitleShow

        readonly property bool show:
            hoverCursorSecondarySubtitleShow.hovered ||
            (!Features.isMacos && menu.anyHovered)

        anchors {
            left: root.left
            right: root.right
            top: root.top
        }
        height: root.height * 0.25
        focusPolicy: Qt.NoFocus
        visible: MementoSettings.behaviorSecondarySubtitleCursorShow

        HoverHandler {
            id: hoverCursorSecondarySubtitleShow
        }

        /**
         * Toggles secondary subtitle visibility.
         */
        function updateSeconarySubtitleVisibility() {
            if (itemCursorSecondarySubtitleShow.visible)
            {
                root.controller.setSecondarySubtitleVisibility(show);
            }
        }

        onShowChanged: updateSeconarySubtitleVisibility()
        onVisibleChanged: updateSeconarySubtitleVisibility()
    }

    Popup {
        id: definitionPopup

        property point cursorAtSearch: Qt.point(0, 0)
        property int lastHoverIndex: -1

        readonly property int playerWidth: root.width
        readonly property int playerHeight: root.height
        readonly property bool paused: root.state.pause
        readonly property real position: controls.position

        readonly property bool shouldOpen: dictionarySearch.terms.length > 0 || dictionarySearch.kanji

        x: {
            let idealPosition = cursorAtSearch.x - (width / 2);
            idealPosition = Math.max(idealPosition, 0);
            idealPosition = Math.min(idealPosition, root.width - width);
            return idealPosition;
        }
        y: {
            let idealPosition = subtitleText.y - height;
            if (idealPosition < 0)
            {
                idealPosition = subtitleText.y + subtitleText.height;
            }
            return idealPosition;
        }
        width: MementoSettings.interfacePopupWidth
        height: MementoSettings.interfacePopupHeight
        closePolicy: Popup.NoAutoClose

        /* Yomitan-like frame: no thick style padding, a 1 px grey border
         * against the dark background, rounded corners, and a light glow
         * outside that fades over 12 px (values sampled from Yomitan). */
        padding: 0
        topInset: 0
        bottomInset: 0
        leftInset: 0
        rightInset: 0
        background: Item {
            Repeater {
                /* Glow strength 1 px outside the border, 2 px, ... 12 px */
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

        onShouldOpenChanged: definitionPopup.shouldOpen ? definitionPopup.open() : definitionPopup.close()
        onOpened: {
            const popupFits = x >= 0 &&
                            y >= 0 &&
                            x + width <= parent.width &&
                            y + height <= parent.height;
            if (!popupFits)
            {
                definitionPopup.close();
            }
        }
        onClosed: {
            definitionPopup.clearResults();
            interactiveTimer.restart();
            hoverResumeTimer.restart();
        }

        onPlayerWidthChanged: definitionPopup.clearResults()
        onPlayerHeightChanged: definitionPopup.clearResults()
        onPausedChanged: {
            /* The pause that hovering the subtitles started is expected: it
             * must not wipe the search that same hover just began. */
            if (root.state.pause && root.hoverPaused)
            {
                return;
            }
            definitionPopup.clearResults();
        }
        onPositionChanged: {
            /* The video was still moving when the hover pause was sent, so
             * the slider ticks once more right after it. Ignore that tick. */
            if (root.hoverPaused && Date.now() - root.hoverPauseTime < 600)
            {
                return;
            }
            definitionPopup.clearResults();
        }

        Rectangle {
            id: dictionaryBorderRectangle
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
                /* 3 px keeps the page's square corners inside the rounded border */
                anchors.margins: 3
                search: dictionarySearch

                /**
                 * Selects the longest cloze match or clears the selection on clear.
                 */
                function updateSelection() {
                    if (dictionarySearch.terms.length === 0 &&
                        dictionarySearch.kanji === null)
                    {
                        subtitleText.clearSelection();
                        return;
                    }
                    let selectionLength = 0;
                    if (dictionarySearch.terms.length > 0)
                    {
                        selectionLength =
                            dictionarySearch.terms[0].clozeBody.length;
                    }
                    else if (dictionarySearch.kanji !== null)
                    {
                        selectionLength = 1;
                    }
                    subtitleText.select(
                                subtitleText.hoverIndex,
                                subtitleText.hoverIndex + selectionLength);
                }

                onClosePressed: definitionPopup.clearResults()

                Connections {
                    target: dictionarySearch

                    function onKanjiChanged() {
                        definitionPage.updateSelection();
                    }

                    function onTermsChanged() {
                        definitionPage.updateSelection();
                    }
                }
            }
        }

        DictionarySearch {
            id: dictionarySearch
        }

        Timer {
            id: definitionPopupTimer
            interval: MementoSettings.searchDelay
            running: false
            repeat: false
            onTriggered: {
                if (subtitleText.hoverIndex !== definitionPopup.lastHoverIndex)
                {
                    return;
                }
                else if (!root.state.pause)
                {
                    return;
                }

                Qt.callLater(definitionPopup.search, subtitleText.hoverIndex);
            }
        }

        /**
         * Starts the search timer and sets start state.
         */
        function startSearchTimer() {
            if (subtitleText.hoverIndex === definitionPopup.lastHoverIndex)
            {
                return;
            }
            definitionPopup.lastHoverIndex = subtitleText.hoverIndex;
            if (subtitleText.hoverIndex < 0)
            {
                return;
            }
            else if (!root.state.pause &&
                     !root.hoverPaused &&
                     !MementoSettings.searchPauseOnHover)
            {
                /* Not paused and not about to be paused by the hover itself.
                 * (The hover pause may start just after this index change,
                 * so the setting is checked too, not only hoverPaused.) */
                return;
            }
            definitionPopupTimer.restart();
        }

        /**
         * Executes a search using the hover index of the subtitle text.
         * @param index The index into the subtitle text to search.
         */
        function search(index) {
            if (index < 0 || index >= subtitleText.text.length)
            {
                return;
            }

            definitionPopup.cursorAtSearch = root.cursorPosition;
            definitionPage.resetStack();

            const text = subtitleText.text;
            const query = text.substring(index);
            dictionarySearch.searchTerms(query, text, index);
            dictionarySearch.searchKanji(text.charAt(index), text, index);
        }

        /**
         * Clears search results.
         */
        function clearResults() {
            definitionPopup.lastHoverIndex = -1;
            definitionPage.resetStack();
            dictionarySearch.clearResults();
        }
    }

    TogglLogger {
        id: togglLogger
        player: root
    }

    PadNavigator {
        id: padNavigator
        player: root
        library: libraryView
        animeList: malView
        mangaViews: [mangaView, mangaListView]
    }

    /* Xbox-style controller: A play/pause, left/right seek, LB/RB previous/
     * next subtitle line, up/down volume, Start fullscreen, Back library.
     * In the library the D-pad moves, A opens, B goes back. The log prompt
     * gets the buttons first while it is open. */
    Connections {
        target: Gamepad
        function onButtonPressed(name) {
            if (togglLogger.handleGamepad(name))
                return;
            /* Library, Anime list and dialogs (manga is left out) */
            if (padNavigator.handle(name))
                return;
            if (Utils.modalDialogs > 0)
                return;
            switch (name) {
            case "back":
                libraryView.open();
                break;
            case "a":
                if (root.state.pause)
                    root.controller.play();
                else
                    root.controller.pause();
                break;
            case "left":
            case "right": {
                const seconds = Number(WatchHistory.option("arrow-seconds", 5));
                const direction = name === "left" ? -1 : 1;
                root.controller.command(["seek", String(direction * seconds), "exact"]);
                root.showOsc();
                break;
            }
            case "lb":
                root.jumpLine(-1);
                break;
            case "rb":
                root.jumpLine(1);
                break;
            case "up":
            case "down": {
                const step = name === "up" ? 5 : -5;
                const volume = Math.max(0, Math.min(100, Math.round(root.state.volume) + step));
                root.controller.setVolume(volume);
                root.showOsc();
                break;
            }
            case "start":
                root.controller.setFullscreen(!root.state.fullscreen);
                break;
            case "x":
            case "y":
                root.controller.command(["add", "sub-delay", name === "x" ? "-0.1" : "0.1"]);
                root.controller.command(["show-text", "Sub delay: ${sub-delay}"]);
                break;
            }
        }
    }

    SubMatcher {
        id: subMatcher
        player: root
    }

    WatchTracker {
        id: watchTracker
        player: root
    }

    PauseInfo {
        id: pauseInfo
        player: root
        subtitleItem: subtitleText
        blocked: subtitleHover.hovered ||
                 subtitleText.hoverIndex !== -1 ||
                 subtitleText.selectionStart !== -1 ||
                 definitionPopup.visible ||
                 YomitanOverlay.hover ||
                 YomitanOverlay.popupHover ||
                 YomitanOverlay.popupOpen
    }

    SubtitleText {
        id: subtitleText

        readonly property var regexFilter: Utils.safeRegex(MementoSettings.searchRemoveRegex, "g")

        /**
         * Toggles mpv subtitles if searchHideMpvSubs is enabled.
         */
        function toggleMpvSubs() {
            if (!MementoSettings.searchHideMpvSubs)
            {
                return;
            }
            root.controller.setSubtitleVisibility(!subtitleText.visible);
        }

        anchors {
            horizontalCenter: root.horizontalCenter
            bottom: root.bottom

            /* Makes sure UI elements don't obscure the subtitles or that they go offscreen */
            bottomMargin: {
                let minValue = controls.visible ? controls.height : 0;
                let maxValue = root.height - subtitleText.height;
                if (!Features.isMacos && menu.visible)
                {
                    maxValue -= menu.height;
                }
                let margin = root.height * MementoSettings.interfaceSubtitleOffset;
                margin = Math.max(margin, minValue);
                margin = Math.min(margin, maxValue);
                return margin;
            }
        }

        /* Prevents text from being wider than the window */
        transformOrigin: Item.Bottom
        scale: subtitleText.width > root.width ? (root.width / subtitleText.width) : 1.0

        font.family: MementoSettings.interfaceSubtitleFont.family
        font.bold: MementoSettings.interfaceSubtitleFont.bold
        font.italic: MementoSettings.interfaceSubtitleFont.italic
        font.underline: MementoSettings.interfaceSubtitleFont.underline
        font.pixelSize: root.height * MementoSettings.interfaceSubtitleScale
        font.weight: MementoSettings.interfaceSubtitleFont.weight
        font.overline: MementoSettings.interfaceSubtitleFont.overline
        font.strikeout: MementoSettings.interfaceSubtitleFont.strikeout
        font.letterSpacing: MementoSettings.interfaceSubtitleFont.letterSpacing
        font.wordSpacing: MementoSettings.interfaceSubtitleFont.wordSpacing
        font.kerning: MementoSettings.interfaceSubtitleFont.kerning
        font.preferShaping: MementoSettings.interfaceSubtitleFont.preferShaping
        font.hintingPreference: MementoSettings.interfaceSubtitleFont.hintingPreference
        font.styleName: MementoSettings.interfaceSubtitleFont.styleName

        color: MementoSettings.interfaceSubtitleColor
        background: MementoSettings.interfaceSubtitleBackground
        stroke: MementoSettings.interfaceSubtitleStrokeColor
        strokeSize: MementoSettings.interfaceSubtitleStroke
        lineSpacing: MementoSettings.interfaceSubtitleLineSpacing
        furiganaRatio: MementoSettings.interfaceSubtitleFuriganaRatio

        text: {
            /* Implements regex filtering */
            let text = root.state.subtitle.text.replace(subtitleText.regexFilter, "");
            /* Implements replace new lines */
            if (MementoSettings.searchReplaceNewlines)
            {
                text = text.replace(/\n/g, MementoSettings.searchReplaceNewlinesWith);
            }
            return text;
        }

        visible: {
            if (root.ocrMode)
            {
                return false;
            }

            /* Implement unconditional hiding of subtitles */
            if (!menu.showSubtitles)
            {
                return false;
            }

            /* Implement hide Memento subtitles while playing media */
            if (MementoSettings.searchHideSubs && !root.state.pause)
            {
                return false;
            }

            /* Implements subtitle cursor show */
            if (MementoSettings.behaviorSubtitleCursorShow)
            {
                return itemCursorSubtitleShow.show;
            }

            return true;
        }

        /* Implements hide mpv subtitles */
        onVisibleChanged: subtitleText.toggleMpvSubs()
        Connections {
            target: MementoSettings
            function onSearchHideMpvSubsChanged() {
                subtitleText.toggleMpvSubs();
            }
        }

        Clipboard {
            id: clipboard
        }
        onDoubleClicked: clipboard.setText(text)

        HoverHandler {
            id: subtitleHover

            /* Auto pause on hover (and resume on leaving): see
             * root.onTextHoveredChanged, which also covers the overlay */
        }

        /* Implement searching (Yomitan does it while the overlay runs) */
        onHoverIndexChanged: {
            if (YomitanOverlay.active)
            {
                return;
            }
            switch (MementoSettings.searchMethod)
            {
            case MementoSetting.SearchMethodHover:
                definitionPopup.startSearchTimer();
                break;

            case MementoSetting.SearchMethodModifier:
                if (KeyTracker.modifierHeld(MementoSettings.searchModifier))
                {
                    Qt.callLater(definitionPopup.search, subtitleText.hoverIndex);
                }
                break;
            }
        }
        onMiddleClicked: {
            if (MementoSettings.searchMiddleMouseScan && !YomitanOverlay.active)
            {
                Qt.callLater(definitionPopup.search, subtitleText.hoverIndex);
            }
        }

        Connections {
            target: KeyTracker
            function onModifiersChanged() {
                if (MementoSettings.searchMethod === MementoSetting.SearchMethodModifier &&
                        !YomitanOverlay.active &&
                        subtitleHover.hovered &&
                        KeyTracker.modifierHeld(MementoSettings.searchModifier))
                {
                    Qt.callLater(definitionPopup.search, subtitleText.hoverIndex);
                }
            }
        }
    }

    PlayerTitle {
        id: playerTitle
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        player: root
        controls: controls
        menu: menu
    }

    PlayerMenu {
        id: menu
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        visible: Features.isMacos
        player: root

        OpacityAnimator on opacity {
            id: menuFadeIn
            to: 1
            duration: Math.max(MementoSettings.behaviorOscFadeDuration, 1)
            running: false
            onStarted: menu.visible = true
        }

        OpacityAnimator on opacity {
            id: menuFadeOut
            to: 0
            duration: Math.max(MementoSettings.behaviorOscFadeDuration, 1)
            running: false
            onFinished: menu.visible = false
        }

        onOcrModeRequested: root.startOcrMode()
    }

    PlayerControls {
        id: controls
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        visible: false
        player: root

        OpacityAnimator on opacity {
            id: controlsFadeIn
            to: 1
            duration: Math.max(MementoSettings.behaviorOscFadeDuration, 1)
            running: false
            onStarted: controls.visible = true
        }

        OpacityAnimator on opacity {
            id: controlsFadeOut
            to: 0
            duration: Math.max(MementoSettings.behaviorOscFadeDuration, 1)
            running: false
            onFinished: controls.visible = false
        }

        HoverHandler {
            id: controlsHover
        }
    }

    PlayerOcrOverlay {
        id: ocrOverlay
        player: root
        onHideOscRequested: {
            definitionPopup.clearResults();
            interactiveTimer.stop();
            root.hideOsc(true);
        }
        onModeChanged: (enabled) => root.ocrMode = enabled
        onRestoreOscRequested: {
            if (root.oscVisibility === Player.OscVisible)
            {
                root.showOsc();
            }
            else
            {
                interactiveTimer.restart();
            }
        }
        onShowTextRequested: (text) => root.controller.showText(text)
        onTextRecognized: (text) => root.auxiliarySearchRequested(text)
    }

    /* Covers everything else while open */
    LibraryView {
        id: libraryView
        anchors.fill: parent
        player: root
    }

    /* Your MyAnimeList list */
    MalView {
        id: malView
        anchors.fill: parent
        player: root
    }

    MangaView {
        id: mangaView
        anchors.fill: parent
        player: root
    }

    MangaListView {
        id: mangaListView
        anchors.fill: parent
        player: root
    }

    MangaToggl {
        id: mangaToggl
    }
}

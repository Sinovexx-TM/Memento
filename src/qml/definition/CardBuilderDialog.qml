import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ripose.Memento

/**
 * Dialog shown before a term is added to Anki. Lets the user add the previous
 * or next subtitle line to the sentence and trim the audio on a waveform.
 *
 * On accept the chosen sentence and audio range are stored in AnkiClient, to be
 * used by the next AnkiClient.addNote(term). The caller does the adding.
 */
Dialog {
    id: root

    /* Waveform bars asked from the backend */
    readonly property int bins: 480

    /* Seconds of extra audio drawn on each side of the selected range */
    readonly property real margin: 3.0

    /* Smallest allowed length of the selected audio */
    readonly property real minLength: 0.2

    /* Size of the nudge buttons in seconds */
    readonly property real nudge: 0.05

    property Term term: null

    /* Rows of the first and last subtitle line in the sentence */
    property int firstRow: -1
    property int lastRow: -1
    property int rowCount: 0

    /* Profile padding, used for the starting range */
    property real padStart: 0
    property real padEnd: 0

    /* Selected audio range in seconds of the video */
    property real selStart: 0
    property real selEnd: 0

    /* The waveform window: video time of its left edge, its length, its bars */
    property real windowStart: 0
    property real windowLength: 1
    property var peaks: []
    property string clipUrl: ""
    property bool loading: false
    property string audioError: ""

    /* Bumped on every clip request so late answers can be ignored */
    property int clipRequest: 0

    readonly property bool canAddPrevious: root.firstRow > 0
    readonly property bool canAddNext: root.lastRow >= 0 && root.lastRow < root.rowCount - 1

    function timeToX(time) {
        return (time - root.windowStart) / root.windowLength * waveform.width;
    }

    function xToTime(x) {
        const clamped = Math.max(0, Math.min(waveform.width, x));
        return root.windowStart + clamped / waveform.width * root.windowLength;
    }

    function lineText(row) {
        const line = AnkiClient.cardBuilderLine(row);
        return line.text ?? "";
    }

    /**
     * Opens the dialog for the current term.
     *
     * @return true if the dialog was opened, false if there are no subtitle
     * lines to build from (the caller should add the card directly).
     */
    function openFor(term) {
        const info = AnkiClient.cardBuilderStart();
        if (!info.available) {
            return false;
        }

        root.term = term;
        root.padStart = info.padStart ?? 0;
        root.padEnd = info.padEnd ?? 0;
        root.rowCount = info.count ?? 0;
        root.firstRow = info.first;
        root.lastRow = info.last;

        const lines = [];
        for (let i = root.firstRow; i <= root.lastRow; ++i) {
            const text = root.lineText(i);
            if (text.length > 0) {
                lines.push(text);
            }
        }
        sentenceArea.text = lines.join("\n");

        root.resetTrim(true);
        root.open();
        return true;
    }

    /**
     * Sets the audio range to the lines currently in the sentence (plus the
     * profile padding) and loads the waveform around it.
     */
    function resetTrim(reload) {
        const first = AnkiClient.cardBuilderLine(root.firstRow);
        const last = AnkiClient.cardBuilderLine(root.lastRow);
        root.selStart = Math.max(0, first.start - root.padStart);
        root.selEnd = last.end + root.padEnd;
        if (reload) {
            root.loadClip();
        }
    }

    function loadClip() {
        const request = ++root.clipRequest;
        root.loading = true;
        root.audioError = "";
        const from = Math.max(0, root.selStart - root.margin);
        AnkiClient.cardBuilderClip(from, root.selEnd + root.margin, root.bins).then(function(result) {
            if (request !== root.clipRequest) {
                return;
            }
            root.loading = false;
            if (!result.success) {
                root.audioError = qsTr("Could not read the audio");
                root.peaks = [];
                root.clipUrl = "";
                return;
            }
            root.windowStart = result.start;
            root.windowLength = Math.max(0.1, result.duration);
            root.peaks = result.peaks;
            root.clipUrl = result.url;
            root.selStart = Math.max(root.windowStart, root.selStart);
            root.selEnd = Math.min(root.windowStart + root.windowLength, root.selEnd);
        });
    }

    function addPreviousLine() {
        if (!root.canAddPrevious) {
            return;
        }
        root.firstRow -= 1;
        const text = root.lineText(root.firstRow);
        if (text.length > 0) {
            sentenceArea.text = sentenceArea.text.length > 0 ? text + "\n" + sentenceArea.text : text;
        }
        const line = AnkiClient.cardBuilderLine(root.firstRow);
        root.selStart = Math.max(0, line.start - root.padStart);
        root.loadClip();
    }

    function addNextLine() {
        if (!root.canAddNext) {
            return;
        }
        root.lastRow += 1;
        const text = root.lineText(root.lastRow);
        if (text.length > 0) {
            sentenceArea.text = sentenceArea.text.length > 0 ? sentenceArea.text + "\n" + text : text;
        }
        const line = AnkiClient.cardBuilderLine(root.lastRow);
        root.selEnd = line.end + root.padEnd;
        root.loadClip();
    }

    function setStart(time) {
        root.selStart = Math.max(root.windowStart, Math.min(time, root.selEnd - root.minLength));
    }

    function setEnd(time) {
        root.selEnd = Math.min(root.windowStart + root.windowLength, Math.max(time, root.selStart + root.minLength));
    }

    function playRange() {
        AnkiClient.cardBuilderClip(root.selStart, root.selEnd, 1).then(function(result) {
            if (result.success) {
                AudioPlayer.play(result.url);
            }
        });
    }

    function playFull() {
        if (root.clipUrl.length > 0) {
            AudioPlayer.play(root.clipUrl);
        }
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    width: Math.min(720, parent.width - 40)
    title: qsTr("Card Builder")
    closePolicy: Popup.CloseOnEscape

    onAccepted: AnkiClient.setCardBuilderOverride(sentenceArea.text, root.selStart, root.selEnd)
    onRejected: AnkiClient.clearCardBuilderOverride()

    contentItem: ColumnLayout {
        spacing: 10

        Label {
            Layout.fillWidth: true
            font.bold: true
            font.pointSize: 14
            elide: Label.ElideRight
            text: root.term ? (root.term.expression + (root.term.reading && root.term.reading !== root.term.expression ? "  【" + root.term.reading + "】" : "")) : ""
        }

        Label {
            text: qsTr("Sentence")
            opacity: 0.7
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 110

            TextArea {
                id: sentenceArea
                wrapMode: TextArea.Wrap
                selectByMouse: true
                background: Rectangle {
                    color: "transparent"
                    border.color: sentenceArea.activeFocus ? root.palette.highlight : root.palette.mid
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                text: qsTr("Add Previous Line")
                enabled: root.canAddPrevious
                onClicked: root.addPreviousLine()
            }
            Button {
                text: qsTr("Add Next Line")
                enabled: root.canAddNext
                onClicked: root.addNextLine()
            }
            Item { Layout.fillWidth: true }
        }

        Label {
            text: qsTr("Audio")
            opacity: 0.7
        }

        Item {
            id: waveform
            Layout.fillWidth: true
            Layout.preferredHeight: 120

            property string dragging: ""

            Rectangle {
                anchors.fill: parent
                color: root.palette.base
                border.color: root.palette.mid
            }

            Canvas {
                id: canvas
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const peaks = root.peaks;
                    if (!peaks || peaks.length === 0) {
                        return;
                    }
                    ctx.fillStyle = String(root.palette.windowText);
                    const barWidth = width / peaks.length;
                    const mid = height / 2;
                    for (let i = 0; i < peaks.length; ++i) {
                        const h = Math.max(1, peaks[i] * (height - 8));
                        ctx.fillRect(i * barWidth, mid - h / 2, Math.max(1, barWidth - 0.5), h);
                    }
                }
                Connections {
                    target: root
                    function onPeaksChanged() { canvas.requestPaint(); }
                }
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }

            /* Dim everything outside the selection */
            Rectangle {
                x: 0
                width: Math.max(0, root.timeToX(root.selStart))
                height: parent.height
                color: root.palette.base
                opacity: 0.65
            }
            Rectangle {
                x: root.timeToX(root.selEnd)
                width: Math.max(0, parent.width - x)
                height: parent.height
                color: root.palette.base
                opacity: 0.65
            }

            Rectangle {
                id: startHandle
                x: root.timeToX(root.selStart) - width / 2
                width: 6
                height: parent.height
                color: root.palette.highlight
            }
            Rectangle {
                id: endHandle
                x: root.timeToX(root.selEnd) - width / 2
                width: 6
                height: parent.height
                color: root.palette.highlight
            }

            Label {
                anchors.centerIn: parent
                visible: root.loading || root.audioError.length > 0
                text: root.loading ? qsTr("Loading audio...") : root.audioError
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.SizeHorCursor
                onPressed: function(mouse) {
                    const toStart = Math.abs(mouse.x - root.timeToX(root.selStart));
                    const toEnd = Math.abs(mouse.x - root.timeToX(root.selEnd));
                    waveform.dragging = toStart <= toEnd ? "start" : "end";
                    if (waveform.dragging === "start") {
                        root.setStart(root.xToTime(mouse.x));
                    } else {
                        root.setEnd(root.xToTime(mouse.x));
                    }
                }
                onPositionChanged: function(mouse) {
                    if (waveform.dragging === "start") {
                        root.setStart(root.xToTime(mouse.x));
                    } else if (waveform.dragging === "end") {
                        root.setEnd(root.xToTime(mouse.x));
                    }
                }
                onReleased: waveform.dragging = ""
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Label { text: qsTr("Start") }
            Button {
                text: "−"
                onClicked: root.setStart(root.selStart - root.nudge)
            }
            Button {
                text: "+"
                onClicked: root.setStart(root.selStart + root.nudge)
            }

            Label {
                Layout.leftMargin: 12
                text: qsTr("End")
            }
            Button {
                text: "−"
                onClicked: root.setEnd(root.selEnd - root.nudge)
            }
            Button {
                text: "+"
                onClicked: root.setEnd(root.selEnd + root.nudge)
            }

            Item { Layout.fillWidth: true }

            Label {
                opacity: 0.7
                text: qsTr("%1 s").arg(Math.max(0, root.selEnd - root.selStart).toFixed(2))
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                text: qsTr("▶ Play Range")
                enabled: !root.loading && root.clipUrl.length > 0
                onClicked: root.playRange()
            }
            Button {
                text: qsTr("▶ Play Full")
                enabled: !root.loading && root.clipUrl.length > 0
                onClicked: root.playFull()
            }
            Button {
                text: qsTr("Reset Trim")
                onClicked: root.resetTrim(true)
            }
            Item { Layout.fillWidth: true }
        }
    }

    footer: DialogButtonBox {
        Button {
            text: qsTr("Add to Anki")
            highlighted: true
            enabled: !root.loading
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
        Button {
            text: qsTr("Cancel")
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
        }
    }
}

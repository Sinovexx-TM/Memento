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

    /* Video time of the moving playhead, or -1 when nothing is playing */
    property real playPos: -1

    function stopPlayhead() {
        playheadAnimation.stop();
        root.playPos = -1;
    }

    function startPlayhead(from, to) {
        playheadAnimation.stop();
        root.playPos = from;
        playheadAnimation.from = from;
        playheadAnimation.to = to;
        playheadAnimation.duration = Math.max(1, (to - from) * 1000);
        playheadAnimation.start();
    }

    function playRange() {
        const from = root.selStart;
        const to = root.selEnd;
        AnkiClient.cardBuilderClip(from, to, 1).then(function(result) {
            if (result.success) {
                AudioPlayer.play(result.url);
                root.startPlayhead(from, to);
            }
        });
    }

    function playFull() {
        if (root.clipUrl.length > 0) {
            AudioPlayer.play(root.clipUrl);
            root.startPlayhead(root.windowStart, root.windowStart + root.windowLength);
        }
    }

    NumberAnimation {
        id: playheadAnimation
        target: root
        property: "playPos"
        easing.type: Easing.Linear
        onFinished: root.playPos = -1
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    width: Math.min(820, parent.width - 40)
    padding: 16
    closePolicy: Popup.CloseOnEscape

    onAccepted: AnkiClient.setCardBuilderOverride(sentenceArea.text, root.selStart, root.selEnd)
    onRejected: AnkiClient.clearCardBuilderOverride()
    onClosed: root.stopPlayhead()

    /* GSM-like look: field names on the left, fields on the right */
    readonly property color accent: "#4a8fe0"
    readonly property color addColor: "#27ae4b"
    readonly property color cancelColor: "#d9363e"

    header: Label {
        text: qsTr("Confirm Anki Card Details")
        horizontalAlignment: Label.AlignHCenter
        font.bold: true
        padding: 10
    }

    component FieldLabel: Label {
        Layout.preferredWidth: 90
        Layout.alignment: Qt.AlignRight | Qt.AlignTop
        horizontalAlignment: Label.AlignRight
        font.bold: true
    }

    component FlatButton: Button {
        id: flat
        property color fill: flat.palette.button
        property color textColor: flat.palette.buttonText
        background: Rectangle {
            radius: 3
            color: !flat.enabled ? Qt.darker(flat.fill, 1.6) : (flat.down ? Qt.darker(flat.fill, 1.2) : (flat.hovered ? Qt.lighter(flat.fill, 1.15) : flat.fill))
            border.color: flat.palette.mid
            border.width: flat.fill === flat.palette.button ? 1 : 0
        }
        contentItem: Label {
            text: flat.text
            color: flat.enabled ? flat.textColor : Qt.darker(flat.textColor, 1.8)
            horizontalAlignment: Label.AlignHCenter
            verticalAlignment: Label.AlignVCenter
        }
    }

    contentItem: ColumnLayout {
        spacing: 12

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 12
            rowSpacing: 12

            FieldLabel { text: qsTr("Expression:") }
            Label {
                Layout.fillWidth: true
                elide: Label.ElideRight
                text: root.term ? (root.term.expression + (root.term.reading && root.term.reading !== root.term.expression ? "  【" + root.term.reading + "】" : "")) : ""
            }

            FieldLabel { text: qsTr("Sentence:") }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110

                    TextArea {
                        id: sentenceArea
                        wrapMode: TextArea.Wrap
                        selectByMouse: true
                        background: Rectangle {
                            color: root.palette.base
                            border.color: sentenceArea.activeFocus ? root.accent : root.palette.mid
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    FlatButton {
                        text: qsTr("Add Previous Line")
                        enabled: root.canAddPrevious
                        onClicked: root.addPreviousLine()
                    }
                    FlatButton {
                        text: qsTr("Add Next Line")
                        enabled: root.canAddNext
                        onClicked: root.addNextLine()
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            FieldLabel { text: qsTr("Audio:") }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Item {
                    id: waveform
                    Layout.fillWidth: true
                    Layout.preferredHeight: 120

                    property string dragging: ""

                    Rectangle {
                        anchors.fill: parent
                        color: Qt.darker(root.palette.window, 1.25)
                    }

                    /* Lit background for the selected range */
                    Rectangle {
                        x: root.timeToX(root.selStart)
                        width: Math.max(0, root.timeToX(root.selEnd) - x)
                        height: parent.height
                        color: Qt.lighter(root.palette.window, 1.25)
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
                            const barWidth = width / peaks.length;
                            const mid = height / 2;
                            for (let i = 0; i < peaks.length; ++i) {
                                const x = i * barWidth;
                                const inside = x + barWidth >= root.timeToX(root.selStart) &&
                                               x <= root.timeToX(root.selEnd);
                                ctx.fillStyle = inside ? String(root.accent) : "#6b6b6b";
                                const h = Math.max(1, peaks[i] * (height - 12));
                                ctx.fillRect(x, mid - h / 2, Math.max(1, barWidth - 0.5), h);
                            }
                        }
                        Connections {
                            target: root
                            function onPeaksChanged() { canvas.requestPaint(); }
                            function onSelStartChanged() { canvas.requestPaint(); }
                            function onSelEndChanged() { canvas.requestPaint(); }
                        }
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                    }

                    /* Handles: a thin line with small grips at both ends */
                    Repeater {
                        model: [
                            { time: root.selStart },
                            { time: root.selEnd }
                        ]
                        delegate: Item {
                            required property var modelData
                            x: root.timeToX(modelData.time) - 5
                            width: 10
                            height: waveform.height

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 2
                                height: parent.height
                                color: root.accent
                            }
                            Rectangle {
                                anchors.top: parent.top
                                width: parent.width
                                height: 10
                                color: root.accent
                            }
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 10
                                color: root.accent
                            }
                        }
                    }

                    /* Moving playhead while audio plays */
                    Rectangle {
                        visible: root.playPos >= 0
                        x: root.timeToX(root.playPos) - width / 2
                        width: 2
                        height: parent.height
                        color: "white"
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
                    spacing: 8

                    FlatButton {
                        text: qsTr("▶ Play Range")
                        enabled: !root.loading && root.clipUrl.length > 0
                        onClicked: root.playRange()
                    }
                    FlatButton {
                        text: qsTr("▶ Play Full")
                        enabled: !root.loading && root.clipUrl.length > 0
                        onClicked: root.playFull()
                    }
                    FlatButton {
                        text: qsTr("Reset Trim")
                        onClicked: root.resetTrim(true)
                    }

                    Item { Layout.fillWidth: true }

                    Label { text: qsTr("Start") }
                    FlatButton {
                        text: "−"
                        implicitWidth: 34
                        onClicked: root.setStart(root.selStart - root.nudge)
                    }
                    FlatButton {
                        text: "+"
                        implicitWidth: 34
                        onClicked: root.setStart(root.selStart + root.nudge)
                    }
                    Label {
                        Layout.leftMargin: 6
                        text: qsTr("End")
                    }
                    FlatButton {
                        text: "−"
                        implicitWidth: 34
                        onClicked: root.setEnd(root.selEnd - root.nudge)
                    }
                    FlatButton {
                        text: "+"
                        implicitWidth: 34
                        onClicked: root.setEnd(root.selEnd + root.nudge)
                    }
                    Label {
                        Layout.leftMargin: 6
                        opacity: 0.7
                        text: qsTr("%1 s").arg(Math.max(0, root.selEnd - root.selStart).toFixed(2))
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 12

            FlatButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                text: qsTr("Add to Anki")
                fill: root.addColor
                textColor: "white"
                enabled: !root.loading
                onClicked: root.accept()
            }
            FlatButton {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                text: qsTr("Cancel")
                fill: root.cancelColor
                textColor: "white"
                onClicked: root.reject()
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import Ripose.Memento

/**
 * Dims the video and shows the show name and episode on the left when the
 * user paused by hand and has left it paused for a few seconds.
 *
 * Never shown for a pause started by hovering the subtitles (word lookups),
 * while the cursor is on the subtitles, or while a dictionary popup is open.
 * It sits below the subtitles and its dim ends above them, so the subtitles win.
 */
Item {
    id: root

    /* The Player: provides state, hoverPaused and ocrMode */
    required property var player

    /* The subtitle text item, to stay clear of it */
    required property Item subtitleItem

    /* True while the cursor is on the subtitles or a popup is open */
    property bool blocked: false

    /* Seconds a manual pause must last before this shows */
    property int delayMs: 4000

    readonly property var info: Utils.parseMediaInfo(root.player.state.path, root.player.state.title)

    /* The plain file name, for local files */
    readonly property string fileName: {
        const path = root.player.state.path;
        if (!path || /^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(path)) {
            return "";
        }
        const parts = path.split(/[\\/]/);
        return parts[parts.length - 1];
    }

    readonly property bool wanted: MementoSettings.searchEpisodeInfo &&
                                   root.player.state.pause &&
                                   !root.player.hoverPaused &&
                                   !root.player.ocrMode &&
                                   !root.blocked

    /* Set once the pause has lasted long enough */
    property bool ready: false

    /* Space the text can use above the subtitles */
    readonly property real limit: root.subtitleItem.visible ? root.subtitleItem.y - 24 : root.height - 24
    readonly property real textY: Math.min(root.height * 0.2, root.limit - panel.height)
    readonly property bool fits: root.textY >= 24

    readonly property bool shown: root.ready && root.wanted

    onWantedChanged: {
        if (!root.wanted) {
            root.ready = false;
        }
    }

    Timer {
        interval: root.delayMs
        running: root.wanted && !root.ready
        repeat: false
        onTriggered: root.ready = true
    }

    anchors.fill: parent
    visible: opacity > 0
    opacity: root.shown ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: Math.max(MementoSettings.behaviorOscFadeDuration, 1)
        }
    }

    /*
     * The dim stops above the subtitles and fades out before them, so no
     * subtitle (Memento's or mpv's own) is ever darkened. Darkest top-left,
     * where the text is.
     */
    Item {
        id: dim
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        /* Memento's subtitles hidden: mpv may draw its own at the bottom */
        height: Math.max(0, root.subtitleItem.visible ? root.limit : root.height * 0.7)

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0.043, 0.047, 0.055, 0.70) }
                GradientStop { position: 0.70; color: Qt.rgba(0.043, 0.047, 0.055, 0.55) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Qt.rgba(0.043, 0.047, 0.055, 0.45) }
                GradientStop { position: 0.6; color: "transparent" }
            }
        }
    }

    Column {
        id: panel
        x: root.width * 0.06
        y: root.textY
        width: Math.min(root.width * 0.45, 900)
        spacing: 8
        visible: root.fits

        Label {
            width: panel.width
            text: qsTr("You're watching")
            color: "#a8a8a8"
            font.pixelSize: Math.max(14, root.height * 0.032)
        }

        Label {
            width: panel.width
            text: root.info.title
            color: "white"
            font.bold: true
            font.pixelSize: Math.max(24, root.height * 0.07)
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Label {
            width: panel.width
            visible: text.length > 0
            text: root.info.episode
            color: "white"
            font.bold: true
            font.pixelSize: Math.max(16, root.height * 0.045)
            wrapMode: Text.Wrap
        }

        Label {
            width: panel.width
            visible: text.length > 0
            text: root.fileName
            color: "#8a8a8a"
            font.pixelSize: Math.max(12, root.height * 0.026)
            elide: Text.ElideMiddle
        }
    }
}

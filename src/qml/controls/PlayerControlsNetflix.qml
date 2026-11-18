import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ripose.Memento

/**
 * Netflix-style controls: a progress bar on top that thickens on hover, and
 * a row of large icons below it. Drawn over a gradient by PlayerControls.
 *
 * Left: play/pause, previous, back 10 s, forward 10 s, next, volume, title.
 * Right: the mining tools (subtitle line back/forward, subtitle list, OCR),
 * then subtitle tracks, playback speed and fullscreen.
 */
Item {
    id: root

    required property MpvPlayer player

    readonly property real position: seekBar.position

    /* True while one of the menus is open, so the controls stay up */
    readonly property bool menuOpen: subtitlePopup.opened || speedPopup.opened

    readonly property color accent: "#e5383b"
    readonly property var info: Utils.parseMediaInfo(root.player.state.path, root.player.state.title)
    readonly property string shortEpisode: {
        const season = root.info.episode.match(/^Season (\d+) · Episode (\d+)$/);
        if (season) {
            return "S" + season[1] + " E" + season[2];
        }
        const episode = root.info.episode.match(/^Episode (\d+)$/);
        if (episode) {
            return "E" + episode[1];
        }
        return root.info.episode;
    }

    /* Volume to go back to when un-muting */
    property int lastVolume: 100

    /* Speeds offered in the speed menu */
    readonly property var speeds: [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    function makeTrackName(track) {
        let name = qsTr("Track %1").arg(track.id);
        if (track.language) {
            name += ` [${track.language}]`;
        }
        if (track.title) {
            name += ` - ${track.title}`;
        }
        return name;
    }

    component IconButton: ToolButton {
        id: button
        property string iconName: ""
        property int iconSize: 28
        focusPolicy: Qt.NoFocus
        padding: 6
        icon.source: Utils.toImageProvider(button.iconName, Qt.color(button.enabled ? "white" : "#808080"))
        icon.width: button.iconSize
        icon.height: button.iconSize
        opacity: button.hovered ? 1.0 : 0.85
        background: Item {}
        ToolTip.visible: button.hovered && ToolTip.text.length > 0
        ToolTip.delay: 600
    }

    /* ---- Progress bar ---- */

    RowLayout {
        id: progressRow
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 24
            rightMargin: 24
        }
        height: 30
        spacing: 16

        NetflixSlider {
            id: seekBar
            Layout.fillWidth: true
            Layout.fillHeight: true
            accent: root.accent
            enabled: from !== to
            from: 0
            to: root.player.state.duration
            chapters: root.player.state.chapters
            onMoved: root.player.controller.seek(value)

            Timer {
                interval: 250
                running: true
                repeat: true
                onTriggered: seekBar.value = root.player.state.timePosition
            }
        }

        Label {
            color: "white"
            opacity: 0.85
            text: Utils.toTimeString(seekBar.value) + " / " + Utils.toTimeString(root.player.state.duration)
        }
    }

    Loader {
        anchors.bottom: progressRow.top
        anchors.bottomMargin: 36
        x: progressRow.x + seekBar.x + seekBar.xPosition - width / 2
        active: MementoSettings.behaviorOscPreviewThumbnails
        sourceComponent: Component {
            PlayerThumbnail {
                visible: seekBar.hovered && !seekBar.pressed
                opacity: active ? 1 : 0
                path: root.player.state.path
                position: seekBar.cursorValue
            }
        }
    }

    /* ---- Button row ---- */

    RowLayout {
        anchors {
            left: parent.left
            right: parent.right
            top: progressRow.bottom
            bottom: parent.bottom
            leftMargin: 18
            rightMargin: 18
        }
        spacing: 4

        IconButton {
            visible: root.player.state.pause
            iconName: "play"
            iconSize: 34
            onClicked: root.player.controller.play()
        }
        IconButton {
            visible: !root.player.state.pause
            iconName: "pause"
            iconSize: 34
            onClicked: root.player.controller.pause()
        }
        IconButton {
            iconName: "skip-previous"
            ToolTip.text: qsTr("Previous in playlist")
            onClicked: root.player.controller.playlistPrev()
        }
        IconButton {
            iconName: "replay-10"
            ToolTip.text: qsTr("Back 10 seconds")
            onClicked: root.player.controller.command(["seek", "-10", "relative+exact"])
        }
        IconButton {
            iconName: "forward-10"
            ToolTip.text: qsTr("Forward 10 seconds")
            onClicked: root.player.controller.command(["seek", "10", "relative+exact"])
        }
        IconButton {
            iconName: "skip-next"
            ToolTip.text: qsTr("Next in playlist")
            onClicked: root.player.controller.playlistNext()
        }

        IconButton {
            Layout.leftMargin: 10
            iconName: root.player.state.volume > 0 ? "volume-on" : "volume-off"
            ToolTip.text: qsTr("Mute")
            onClicked: {
                if (root.player.state.volume > 0) {
                    root.lastVolume = root.player.state.volume;
                    root.player.controller.setVolume(0);
                } else {
                    root.player.controller.setVolume(root.lastVolume > 0 ? root.lastVolume : 100);
                }
            }
        }
        Slider {
            id: volumeSlider
            Layout.preferredWidth: 90
            focusPolicy: Qt.NoFocus
            from: 0
            to: root.player.state.maxVolume
            value: root.player.state.volume
            onMoved: root.player.controller.setVolume(value)

            background: Item {
                implicitHeight: 20
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: "#59ffffff"
                    Rectangle {
                        width: volumeSlider.visualPosition * parent.width
                        height: parent.height
                        radius: 2
                        color: "white"
                    }
                }
            }
            handle: Rectangle {
                x: volumeSlider.leftPadding + volumeSlider.visualPosition * (volumeSlider.availableWidth - width)
                y: volumeSlider.topPadding + volumeSlider.availableHeight / 2 - height / 2
                width: 12
                height: 12
                radius: 6
                color: "white"
                visible: volumeSlider.hovered || volumeSlider.pressed
            }
        }
        Label {
            Layout.preferredWidth: 44
            color: "white"
            opacity: 0.6
            font.pixelSize: 12
            text: `${root.player.state.volume}%`
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: 14
            visible: MementoSettings.searchEpisodeInfo && root.info.title.length > 0
            color: "white"
            elide: Text.ElideRight
            font.bold: true
            font.pixelSize: 15
            text: root.info.title.replace(/&/g, "&amp;").replace(/</g, "&lt;") +
                  (root.shortEpisode.length > 0 ? "<font color=\"#9a9a9a\" size=\"2\">&nbsp;&nbsp;" + root.shortEpisode.replace(/&/g, "&amp;").replace(/</g, "&lt;") + "</font>" : "")
            textFormat: Text.StyledText
        }
        Item {
            Layout.fillWidth: true
            visible: !(MementoSettings.searchEpisodeInfo && root.info.title.length > 0)
        }

        /* Mining tools */
        IconButton {
            iconName: "fast-rewind"
            ToolTip.text: qsTr("Previous subtitle line")
            onClicked: root.player.controller.subtitleSeek(-1, true)
        }
        IconButton {
            iconName: "fast-forward"
            ToolTip.text: qsTr("Next subtitle line")
            onClicked: root.player.controller.subtitleSeek(1, true)
        }
        IconButton {
            iconName: "list"
            ToolTip.text: qsTr("Subtitle list")
            onClicked: MementoSettings.windowSubtitleList = !MementoSettings.windowSubtitleList
        }
        IconButton {
            visible: Features.ocr && MementoSettings.ocrEnabled
            iconName: "eye"
            ToolTip.text: qsTr("OCR")
            onClicked: root.player.startOcrMode()
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 26
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            color: "#59ffffff"
        }

        /* Player options */
        IconButton {
            id: subtitleButton
            iconName: "subtitles"
            ToolTip.text: qsTr("Subtitle tracks")
            onClicked: subtitlePopup.opened ? subtitlePopup.close() : subtitlePopup.open()

            Popup {
                id: subtitlePopup
                parent: subtitleButton
                x: subtitleButton.width - width
                y: -height - 8
                padding: 6
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                contentItem: ColumnLayout {
                    spacing: 0

                    ItemDelegate {
                        Layout.fillWidth: true
                        text: (root.player.state.sid === 0 ? "✓  " : "     ") + qsTr("None")
                        onClicked: {
                            root.player.controller.setSid(0);
                            subtitlePopup.close();
                        }
                    }
                    Repeater {
                        model: root.player.state.subtitleTracks
                        delegate: ItemDelegate {
                            required property var modelData
                            Layout.fillWidth: true
                            enabled: root.player.state.secondarySid !== modelData.id
                            text: (root.player.state.sid === modelData.id ? "✓  " : "     ") + root.makeTrackName(modelData)
                            onClicked: {
                                root.player.controller.setSid(modelData.id);
                                subtitlePopup.close();
                            }
                        }
                    }
                }
            }
        }
        IconButton {
            id: speedButton
            iconName: "speed"
            ToolTip.text: qsTr("Playback speed")
            onClicked: speedPopup.opened ? speedPopup.close() : speedPopup.open()

            Popup {
                id: speedPopup
                parent: speedButton
                x: speedButton.width - width
                y: -height - 8
                padding: 6
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                contentItem: ColumnLayout {
                    spacing: 0

                    Repeater {
                        model: root.speeds
                        delegate: ItemDelegate {
                            required property var modelData
                            Layout.fillWidth: true
                            text: (Math.abs(root.player.state.speed - modelData) < 0.001 ? "✓  " : "     ") +
                                  (modelData === 1.0 ? qsTr("Normal") : `${modelData}×`)
                            onClicked: {
                                root.player.controller.setSpeed(modelData);
                                speedPopup.close();
                            }
                        }
                    }
                }
            }
        }
        IconButton {
            visible: !root.player.state.fullscreen
            iconName: "fullscreen"
            ToolTip.text: qsTr("Fullscreen")
            onClicked: root.player.controller.setFullscreen(true)
        }
        IconButton {
            visible: root.player.state.fullscreen
            iconName: "fullscreen-exit"
            ToolTip.text: qsTr("Exit fullscreen")
            onClicked: root.player.controller.setFullscreen(false)
        }
    }
}

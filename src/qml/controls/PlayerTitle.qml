import QtQuick
import QtQuick.Controls
import Ripose.Memento

/**
 * The show and episode at the top of the video, on a soft dark gradient.
 * Follows the controls: it fades in and out with them.
 */
Item {
    id: root

    /* The player controls, whose visibility and opacity this follows */
    required property Item controls

    /* The menu bar, if it takes space at the top */
    required property Item menu

    /* mpv state of the player */
    required property var player

    readonly property var info: Utils.parseMediaInfo(root.player.state.path, root.player.state.title)
    readonly property real menuHeight: root.menu.visible ? root.menu.height : 0

    height: 110 + root.menuHeight
    visible: MementoSettings.searchEpisodeInfo && root.controls.visible && root.info.title.length > 0
    opacity: root.controls.opacity

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#B0000000" }
            GradientStop { position: 1.0; color: "#00000000" }
        }
    }

    Label {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 24
            rightMargin: 24
            topMargin: root.menuHeight + 14
        }
        text: root.info.episode.length > 0 ? root.info.title + "  •  " + root.info.episode : root.info.title
        color: "white"
        font.bold: true
        font.pixelSize: 20
        elide: Text.ElideRight
    }
}

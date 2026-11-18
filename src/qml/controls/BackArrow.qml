import QtQuick
import QtQuick.Controls

/* The thin white ← used to back out of every page (same look as the pause
 * screen's arrow). At least 44 px to click, brighter on hover. */
Item {
    id: root

    property string tip: qsTr("Back")
    property real size: 30
    signal clicked()

    implicitWidth: 44
    implicitHeight: 44

    Text {
        anchors.verticalCenter: parent.verticalCenter
        x: 6
        text: "←"
        color: area.containsMouse ? "white" : "#d0d0d0"
        font.pixelSize: root.size
        font.weight: Font.Light
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    ToolTip.visible: area.containsMouse && root.tip.length > 0
    ToolTip.delay: 400
    ToolTip.text: root.tip
}

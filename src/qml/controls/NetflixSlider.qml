import QtQuick
import QtQuick.Controls
import Ripose.Memento

/**
 * Thin progress bar that thickens on hover, with chapter gaps and a time
 * label above the cursor. Same hover/position API as PlayerSlider.
 */
Slider {
    id: root

    property var chapters: []
    property color accent: "#e5383b"

    readonly property bool active: root.hovered || root.pressed

    readonly property real xPosition: {
        if (root.pressed)
        {
            return Math.max(0, Math.min(root.background.width, pointHandler.point.position.x));
        }
        else if (root.hovered)
        {
            return hoverHandler.point.position.x;
        }
        return -1;
    }

    readonly property real cursorValue: {
        if (root.xPosition !== -1)
        {
            return root.valueAt(root.xPosition / root.background.width);
        }
        return -1;
    }

    implicitHeight: 30
    implicitWidth: 200
    leftPadding: 0
    topPadding: 0
    rightPadding: 0
    bottomPadding: 0
    leftInset: 0
    topInset: 0
    rightInset: 0
    bottomInset: 0

    HoverHandler {
        id: hoverHandler
        grabPermissions: PointerHandler.TakeOverForbidden
    }

    PointHandler {
        id: pointHandler
        grabPermissions: PointerHandler.TakeOverForbidden
    }

    background: Item {
        implicitWidth: root.implicitWidth
        implicitHeight: root.implicitHeight

        Rectangle {
            id: groove
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: root.active ? 8 : 4
            radius: height / 2
            color: "#59ffffff"

            Behavior on height {
                NumberAnimation { duration: 120 }
            }

            Rectangle {
                width: root.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: root.accent
            }

            /* Chapter marks: thin dark gaps in the bar */
            Repeater {
                model: root.chapters
                delegate: Rectangle {
                    required property var modelData
                    visible: root.to > 0 && modelData > 0 && modelData < root.to
                    x: root.to > 0 ? modelData / root.to * groove.width - width / 2 : 0
                    width: 2
                    height: groove.height
                    color: "#101010"
                }
            }
        }

        /* Time above the cursor */
        Rectangle {
            visible: root.xPosition !== -1 && root.to > 0
            x: Math.max(0, Math.min(parent.width - width, root.xPosition - width / 2))
            y: -height - 4
            width: timeLabel.implicitWidth + 16
            height: timeLabel.implicitHeight + 8
            radius: 4
            color: "#E6000000"

            Label {
                id: timeLabel
                anchors.centerIn: parent
                color: "white"
                font.pixelSize: 12
                font.bold: true
                text: Utils.toTimeString(Math.max(0, root.cursorValue))
            }
        }
    }

    handle: Rectangle {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + root.availableHeight / 2 - height / 2
        width: 16
        height: 16
        radius: 8
        color: root.accent
        visible: root.active
    }
}

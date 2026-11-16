import QtQuick
import QtQuick.Controls

/**
 * A dark menu for the player's menu bar: same items as a normal Menu, dark
 * background, light text, white hover highlight.
 */
Menu {
    id: control

    leftInset: 0
    topInset: 0
    rightInset: 0
    bottomInset: 0

    palette.text: "#f0f0f0"
    palette.windowText: "#f0f0f0"
    palette.buttonText: "#f0f0f0"
    palette.window: "#1c1c1c"
    palette.base: "#1c1c1c"
    palette.disabled.text: "#777777"
    palette.disabled.windowText: "#777777"

    delegate: MenuItem {
        id: item
        background: Rectangle {
            implicitWidth: 200
            implicitHeight: 30
            radius: 4
            color: item.down ? "#33ffffff" : "#1fffffff"
            visible: item.enabled && (item.down || item.highlighted)
        }
    }

    background: Rectangle {
        implicitWidth: 200
        implicitHeight: 30
        radius: 8
        color: "#f01c1c1c"
        border.color: "#3a3a3a"
    }
}

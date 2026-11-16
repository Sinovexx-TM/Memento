import QtQuick
import Ripose.Memento

/* Yomitan-style frequency tag: green "Name:" pill, value in a dark box with a green outline */
Row {
    id: root

    property string name: ""
    property string value: ""

    spacing: 0

    MetaLabel {
        visible: root.name.length > 0
        text: root.name + ":"
        tip: ""
        color: "#5cb85c"
    }

    MetaLabel {
        text: root.value
        tip: ""
        color: PopupPalette.window
        border.color: "#5cb85c"
        border.width: 1
    }
}

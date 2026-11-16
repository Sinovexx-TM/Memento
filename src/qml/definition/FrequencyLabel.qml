import QtQuick
import Ripose.Memento

/* Two-part frequency pill: dictionary name, then the value */
Row {
    id: root

    property string name: ""
    property string value: ""

    spacing: 0

    MetaLabel {
        visible: root.name.length > 0
        text: root.name
        tip: ""
        color: "#5cb85c"
    }

    MetaLabel {
        text: root.value
        tip: ""
        color: PopupPalette.frequencyValue
    }
}

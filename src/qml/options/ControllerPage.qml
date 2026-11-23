import QtQuick
import QtQuick.Controls
import Ripose.Memento

/* Settings > Controller: the controller layout */
ScrollView {
    id: root
    clip: true
    contentWidth: availableWidth

    ControllerDiagram {
        x: 16
        y: 16
        width: root.availableWidth - 32
    }
}

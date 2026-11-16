import QtQuick
import QtQuick.Layouts
import Ripose.Memento

RowLayout {
    id: root
    Layout.fillWidth: true

    required property Tag tag

    PopupLabel {
        Layout.fillWidth: true
        wrapMode: TextEdit.WordWrap
        font.family: MementoSettings.interfaceSearchGlossaryFont.family
        font.pointSize: MementoSettings.interfaceSearchGlossaryFont.pointSize
        font.bold: true
        text: root.tag?.notes
    }

    PopupLabel {
        wrapMode: Text.WordWrap
        font.family: MementoSettings.interfaceSearchGlossaryFont.family
        font.pointSize: MementoSettings.interfaceSearchGlossaryFont.pointSize
        text: root.tag?.value
    }
}

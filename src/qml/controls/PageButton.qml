import QtQuick

/* The button used on the Library, Manga and list pages.
 * active = white (selected tab, +1), accent = red (starts something big). */
Rectangle {
    id: button

    property string text: ""
    property bool active: false
    property bool accent: false
    property int fontSize: 13
    signal clicked()

    implicitWidth: label.implicitWidth + 24
    implicitHeight: 32
    radius: 4
    color: accent ? (area.containsMouse ? "#ff5052" : "#e5383b") :
           active ? (area.containsMouse ? "#ffffff" : "#e6e6e6") :
           (area.containsMouse ? "#4d4d4d" : "#2e2e2e")
    opacity: enabled ? 1 : 0.4

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: button.active && !button.accent ? "#141414" : "#f2f2f2"
        font.pixelSize: button.fontSize
        font.bold: button.active
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}

import QtQuick
import QtQuick.Controls

/* The controller layout picture (Settings > Controller, Tools > Controls).
 * The picture's own footnote is cut off and replaced by the text below,
 * so it can follow changes without a new picture. */
Column {
    id: root
    spacing: 8

    Image {
        width: root.width
        height: width * 870 / 1800
        source: "qrc:/images/controller-layout.png"
        sourceClipRect: Qt.rect(0, 0, 1800, 870)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }

    Label {
        width: root.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        opacity: 0.7
        text: qsTr("First D-pad press only shows the outline (series pages start on your next episode). " +
                   "Manga: D-pad, A and B work on the manga pages; in the reader ← / → turn pages and B goes back.")
    }
}

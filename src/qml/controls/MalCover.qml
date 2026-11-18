import QtQuick
import Ripose.Memento

/* Small cover of an Anime list / Manga list row. Grey until the picture is
 * cached (MalClient keeps them in mal_covers). */
Rectangle {
    id: root

    property string kind: "anime"
    property int entryId: 0
    property string picture: ""
    property string source: ""

    implicitWidth: 40
    implicitHeight: 58
    radius: 3
    color: "#2e2e2e"
    clip: true

    function load() {
        root.source = MalClient.cover(root.kind, root.entryId, root.picture);
    }

    onEntryIdChanged: load()
    onPictureChanged: load()
    Component.onCompleted: load()

    Connections {
        target: MalClient
        enabled: root.source.length === 0
        function onCoverReady(kind, id, fileUrl) {
            if (kind === root.kind && id === root.entryId) {
                root.source = fileUrl;
            }
        }
    }

    Image {
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 80
        visible: status === Image.Ready
    }
}

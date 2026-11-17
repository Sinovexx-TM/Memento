import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ripose.Memento

import "../util/SubMatch.js" as SubMatch

/* Subtitle matching by episode number (logic in util/SubMatch.js).
 * - On opening a video with no Japanese subtitle file loaded, loads the
 *   matching subtitle from the folder or its "subs" subfolder (Japanese
 *   first). If it is unclear which one, asks.
 * - openFolderMatch(): rename the folder's subtitles to their videos'
 *   names, after showing a preview. */
Item {
    id: root

    required property var player

    SubFiles {
        id: files
    }

    function currentFolder() {
        return files.folderOf(root.player.state.path ?? "");
    }

    function scan(folder) {
        const subs = files.subtitles(folder);
        const videos = files.videos(folder);
        return { subs: subs, result: SubMatch.matchFolder(videos, subs) };
    }

    /* true when an external subtitle in Japanese is already loaded */
    function japaneseSubLoaded() {
        const tracks = root.player.state.subtitleTracks;
        for (let i = 0; i < tracks.length; ++i) {
            const t = tracks[i];
            if (!t.external) {
                continue;
            }
            const name = files.fileNameOf(t.externalFilename);
            const tag = SubMatch.langOf(SubMatch.splitExt(name).base).lang;
            if (tag === "ja" || (tag === "" && files.languageOf(t.externalFilename) === "ja")) {
                return true;
            }
        }
        return false;
    }

    function loadSub(sub) {
        root.player.controller.loadSubtitle(sub.path);
    }

    function autoLoad() {
        const folder = root.currentFolder();
        if (folder.length === 0 || root.japaneseSubLoaded()) {
            return;
        }
        const video = files.fileNameOf(root.player.state.path);
        const scanned = root.scan(folder);
        const picks = SubMatch.subsForVideo(video, scanned.result);

        if (picks.subs.length > 0) {
            /* Japanese first; it becomes the primary subtitle */
            root.loadSub(picks.subs[0]);
            root.player.controller.showText(qsTr("Loaded subtitle: %1").arg(picks.subs[0].name));
            return;
        }
        if (picks.unclear.length > 0) {
            pickDialog.openFor(video, picks.unclear);
        }
    }

    function openFolderMatch() {
        const folder = root.currentFolder();
        if (folder.length === 0) {
            root.player.controller.showText(qsTr("Open a local video first"));
            return;
        }
        previewDialog.openFor(folder, root.scan(folder).result);
    }

    Timer {
        id: autoLoadTimer
        /* Let mpv load its own subtitle tracks first */
        interval: 800
        onTriggered: root.autoLoad()
    }

    Connections {
        target: root.player.state
        function onPathChanged() {
            pickDialog.close();
            if ((root.player.state.path ?? "").length > 0) {
                autoLoadTimer.restart();
            }
        }
    }

    /* Several possible subtitles for this episode: the user picks */
    Dialog {
        id: pickDialog

        property var candidates: []

        function openFor(video, candidates) {
            pickDialog.candidates = candidates;
            pickLabel.text = qsTr("Which subtitle belongs to %1?").arg(video);
            pickDialog.open();
        }

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 700)
        height: Math.min(parent.height - 40, 520)
        modal: true
        title: qsTr("Pick a subtitle")
        standardButtons: Dialog.Cancel
        onAboutToShow: Utils.modalDialogs += 1
        onClosed: Utils.modalDialogs -= 1

        ColumnLayout {
            anchors.fill: parent

            Label {
                id: pickLabel
                Layout.fillWidth: true
                wrapMode: Label.WordWrap
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: pickDialog.candidates
                ScrollBar.vertical: ScrollBar { }
                delegate: ItemDelegate {
                    required property var modelData
                    width: ListView.view.width
                    text: (modelData.dir ? modelData.dir + "/" : "") + modelData.name +
                          (modelData.lang === "ja" ? "  (Japanese)" : "")
                    onClicked: {
                        root.loadSub(modelData);
                        pickDialog.close();
                    }
                }
            }
        }
    }

    /* Folder rename preview */
    Dialog {
        id: previewDialog

        property string folder: ""
        property var renames: []
        property var notes: []
        property string status: ""

        function openFor(folder, result) {
            previewDialog.folder = folder;
            previewDialog.renames = result.renames;
            let notes = [];
            if (result.matched.length > 0) {
                notes.push(qsTr("%1 already match their video").arg(result.matched.length));
            }
            const unclearVideos = result.unclear.length;
            if (unclearVideos > 0) {
                notes.push(qsTr("%1 video(s) unclear, not renamed (you'll be asked when you open them)").arg(unclearVideos));
            }
            if (result.unmatched.length > 0) {
                notes.push(qsTr("No video for: %1").arg(result.unmatched.map(s => s.name).join(", ")));
            }
            previewDialog.notes = notes;
            previewDialog.status = "";
            previewDialog.open();
        }

        function apply() {
            let done = 0;
            let errors = [];
            for (const r of previewDialog.renames) {
                const from = r.sub.path;
                const to = files.join(previewDialog.folder, r.newName);
                const error = files.rename(from, to);
                if (error.length === 0) {
                    ++done;
                } else {
                    errors.push(`${r.sub.name}: ${error}`);
                }
            }
            previewDialog.renames = [];
            previewDialog.status = qsTr("Renamed %1 subtitle file(s).").arg(done) +
                (errors.length ? "\n" + qsTr("Skipped:") + "\n" + errors.join("\n") : "");
            if (done > 0) {
                autoLoadTimer.restart();
            }
        }

        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 900)
        height: Math.min(parent.height - 40, 600)
        modal: true
        title: qsTr("Match subtitles in this folder")
        onAboutToShow: Utils.modalDialogs += 1
        onClosed: Utils.modalDialogs -= 1

        footer: DialogButtonBox {
            Button {
                text: qsTr("Rename")
                enabled: previewDialog.renames.length > 0
                highlighted: true
                DialogButtonBox.buttonRole: DialogButtonBox.ActionRole
                onClicked: previewDialog.apply()
            }
            Button {
                text: previewDialog.status.length > 0 ? qsTr("Close") : qsTr("Cancel")
                DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                onClicked: previewDialog.close()
            }
        }

        ColumnLayout {
            anchors.fill: parent

            Label {
                Layout.fillWidth: true
                wrapMode: Label.WordWrap
                visible: previewDialog.status.length === 0
                text: previewDialog.renames.length > 0 ?
                          qsTr("These subtitles will be renamed (nothing is overwritten):") :
                          qsTr("Nothing to rename.")
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                visible: previewDialog.status.length === 0
                model: previewDialog.renames
                ScrollBar.vertical: ScrollBar { }
                delegate: Label {
                    required property var modelData
                    width: ListView.view.width
                    wrapMode: Label.WrapAnywhere
                    bottomPadding: 6
                    text: (modelData.sub.dir ? modelData.sub.dir + "/" : "") + modelData.sub.name +
                          "\n    → " + modelData.newName
                }
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Label.WordWrap
                visible: previewDialog.notes.length > 0 && previewDialog.status.length === 0
                color: MementoPalette.placeholderText
                text: previewDialog.notes.join("\n")
            }

            Label {
                Layout.fillWidth: true
                Layout.fillHeight: true
                wrapMode: Label.WordWrap
                visible: previewDialog.status.length > 0
                text: previewDialog.status
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ripose.Memento

import "../util/Mal.js" as Mal

/* Pick the MyAnimeList entry for a show (and season): your own list first,
 * then a MAL search. Saved by show name + season in mal_matches.json. */
Dialog {
    id: root

    property string key: ""
    property string show: ""
    property int season: 1
    property var list: []
    property var results: []
    property string searchError: ""
    property bool searching: false
    property var selected: null

    /* Emitted after a match was saved */
    signal picked()

    function openFor(key, show, season, list, current) {
        root.key = key;
        root.show = show;
        root.season = season;
        root.list = list;
        root.results = [];
        root.searchError = "";
        root.selected = null;
        filterField.text = show;
        offsetBox.value = current && current.offset ? current.offset : 0;
        listView.model = root.filtered();
        root.open();
        filterField.selectAll();
        filterField.forceActiveFocus();
    }

    function filtered() {
        const q = filterField.text.trim();
        let rows = root.list.map(e => ({
            entry: e,
            score: q.length === 0 ? 0 : Math.max(...[e.title, e.en, e.ja].concat(e.synonyms || [])
                .filter(t => t).map(t => Mal.similarity(q, t) + (Mal.norm(t).includes(Mal.norm(q)) ? 0.5 : 0)))
        }));
        if (q.length > 0) {
            rows = rows.filter(r => r.score > 0.2);
        }
        rows.sort((a, b) => b.score - a.score ||
            (a.entry.status === "watching" ? -1 : 0) - (b.entry.status === "watching" ? -1 : 0));
        return rows.slice(0, 30).map(r => r.entry);
    }

    function save() {
        if (!root.selected) {
            return;
        }
        MalClient.setMatch(root.key, {
            id: root.selected.id,
            title: root.selected.title,
            offset: offsetBox.value,
            episodes: root.selected.episodes ?? 0,
            show: root.show,
            season: root.season
        });
        root.picked();
        root.close();
    }

    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(parent.width - 40, 720)
    height: Math.min(parent.height - 40, 600)
    modal: true
    title: root.season > 1 ?
        qsTr("MyAnimeList entry for %1 (season %2)").arg(root.show).arg(root.season) :
        qsTr("MyAnimeList entry for %1").arg(root.show)
    onAboutToShow: Utils.modalDialogs += 1
    onClosed: Utils.modalDialogs -= 1

    Connections {
        target: MalClient
        function onSearchReady(success, results, error) {
            if (!root.visible) {
                return;
            }
            root.searching = false;
            root.results = results;
            root.searchError = success ? (results.length === 0 ? qsTr("Nothing found.") : "") : error;
        }
    }

    footer: DialogButtonBox {
        Button {
            text: qsTr("Use this")
            highlighted: true
            enabled: root.selected !== null
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
            onClicked: root.save()
        }
        Button {
            text: qsTr("Cancel")
            DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
            onClicked: root.close()
        }
    }

    component EntryRow: ItemDelegate {
        id: row
        required property var modelData
        property bool isSelected: false
        width: ListView.view ? ListView.view.width : 0
        highlighted: isSelected
        contentItem: ColumnLayout {
            spacing: 1
            Label {
                Layout.fillWidth: true
                text: row.modelData.title
                font.bold: true
                elide: Label.ElideRight
            }
            Label {
                Layout.fillWidth: true
                elide: Label.ElideRight
                opacity: 0.7
                font.pixelSize: 12
                text: [
                    row.modelData.ja || row.modelData.en || "",
                    (row.modelData.mediaType || "").toUpperCase(),
                    row.modelData.episodes > 0 ? qsTr("%1 eps").arg(row.modelData.episodes) : qsTr("? eps"),
                    row.modelData.status ?
                        (Mal.STATUS_LABELS[row.modelData.status] ?? row.modelData.status) + " " +
                        row.modelData.watched + "/" + (row.modelData.episodes || "?") :
                        qsTr("not on your list")
                ].filter(x => x.length > 0).join("  ·  ")
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            TextField {
                id: filterField
                Layout.fillWidth: true
                placeholderText: qsTr("Filter your list, or search MAL")
                onTextChanged: listView.model = root.filtered()
                onAccepted: searchButton.clicked()
            }
            Button {
                id: searchButton
                text: root.searching ? qsTr("Searching…") : qsTr("Search MAL")
                enabled: !root.searching
                onClicked: {
                    root.searching = true;
                    root.searchError = "";
                    MalClient.search(filterField.text);
                }
            }
        }

        Label {
            text: qsTr("Your list")
            font.bold: true
        }

        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 2
            clip: true
            model: []
            ScrollBar.vertical: ScrollBar { }
            delegate: EntryRow {
                isSelected: root.selected !== null && root.selected.id === modelData.id
                onClicked: root.selected = modelData
                onDoubleClicked: { root.selected = modelData; root.save(); }
            }
        }

        Label {
            visible: root.results.length > 0 || root.searchError.length > 0
            text: qsTr("MAL search")
            font.bold: true
        }

        Label {
            visible: root.searchError.length > 0
            Layout.fillWidth: true
            wrapMode: Label.WordWrap
            color: "#e06c6c"
            text: root.searchError
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 2
            visible: root.results.length > 0
            clip: true
            model: root.results
            ScrollBar.vertical: ScrollBar { }
            delegate: EntryRow {
                isSelected: root.selected !== null && root.selected.id === modelData.id
                onClicked: root.selected = modelData
                onDoubleClicked: { root.selected = modelData; root.save(); }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                wrapMode: Label.WordWrap
                text: qsTr("Episode offset (only if the files number straight through seasons: file 13 = MAL episode 1 → 12)")
            }
            SpinBox {
                id: offsetBox
                from: 0
                to: 500
                editable: true
            }
        }
    }
}

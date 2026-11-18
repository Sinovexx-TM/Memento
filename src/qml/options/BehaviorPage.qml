import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import Ripose.Memento

Page {
    id: root

    property int preferredWidth: 600
    property int groupSpacing: 10

    FolderDialog {
        id: customFolderDialog
        title: qsTr("Select Custom Open Folder")
        currentFolder: MementoSettings.behaviorFileOpenCustom
        onAccepted: MementoSettings.behaviorFileOpenCustom = selectedFolder
    }

    footer: ColumnLayout {
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            visible: Features.isUnix && !scrollView.atBottom
            color: MementoPalette.border
            height: 1
        }

        DialogButtonBox {
            id: buttonBoxFooter
            Layout.fillWidth: true
            standardButtons: DialogButtonBox.Apply |
                             DialogButtonBox.RestoreDefaults |
                             DialogButtonBox.Reset

            onApplied: MementoSettings.writeBehaviorSettings()
            onClicked: function(button) {
                if (button === standardButton(DialogButtonBox.Reset))
                {
                    MementoSettings.loadBehaviorSettings();
                }
                else if (button === standardButton(DialogButtonBox.RestoreDefaults))
                {
                    MementoSettings.defaultBehaviorSettings();
                }
            }
        }
    }

    ScrollView {
        id: scrollView
        anchors.fill: parent
        contentWidth: scrollView.contentWidth
        leftPadding: root.groupSpacing
        rightPadding: root.groupSpacing
        clip: true

        readonly property bool atBottom:
            (ScrollBar.vertical.position + ScrollBar.vertical.size) >= 0.99

        ColumnLayout {
            id: scrollViewLayout
            width: parent.width
            spacing: root.groupSpacing

            SettingsBox {
                id: playerBox
                Layout.preferredWidth: root.preferredWidth
                Layout.topMargin: root.groupSpacing
                Layout.alignment: Qt.AlignHCenter
                title: qsTr("Player")

                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.groupSpacing

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Auto fit media on load")
                        }
                        Switch {
                            Layout.alignment: Qt.AlignRight
                            checked: MementoSettings.behaviorAutoFit
                            onClicked: MementoSettings.behaviorAutoFit = checked
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Auto fit media percentage")
                        }
                        SpinBox {
                            Layout.alignment: Qt.AlignRight
                            editable: true
                            from: 1
                            to: 1000
                            value: MementoSettings.behaviorAutoFitPercent
                            onValueModified: MementoSettings.behaviorAutoFitPercent = value
                        }
                    }
                }
            }

            SettingsBox {
                id: oscBox
                Layout.preferredWidth: root.preferredWidth
                Layout.alignment: Qt.AlignHCenter
                title: qsTr("On Screen Controller")

                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.groupSpacing

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Visibility duration milliseconds")
                        }
                        SpinBox {
                            Layout.alignment: Qt.AlignRight
                            editable: true
                            from: 50
                            to: 9999
                            value: MementoSettings.behaviorOscDuration
                            onValueModified: MementoSettings.behaviorOscDuration = value
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Fade duration milliseconds")
                        }
                        SpinBox {
                            Layout.alignment: Qt.AlignRight
                            editable: true
                            from: 0
                            to: 9999
                            value: MementoSettings.behaviorOscFadeDuration
                            onValueModified: MementoSettings.behaviorOscFadeDuration = value
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Minimum mouse pixel movement")
                        }
                        SpinBox {
                            Layout.alignment: Qt.AlignRight
                            editable: true
                            from: 0
                            to: 99
                            value: MementoSettings.behaviorOscMinMove
                            onValueModified: MementoSettings.behaviorOscMinMove = value
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Allow mpv to control cursor visibility")
                        }
                        Switch {
                            Layout.alignment: Qt.AlignRight
                            checked: MementoSettings.behaviorOscMpvCursor
                            onClicked: MementoSettings.behaviorOscMpvCursor = checked
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Show preview thumbnails")
                        }
                        Switch {
                            Layout.alignment: Qt.AlignRight
                            checked: MementoSettings.behaviorOscPreviewThumbnails
                            onClicked: MementoSettings.behaviorOscPreviewThumbnails = checked
                        }
                    }
                }
            }

            SettingsBox {
                id: subtitlesBox
                Layout.preferredWidth: root.preferredWidth
                Layout.alignment: Qt.AlignHCenter
                title: qsTr("Subtitles")

                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.groupSpacing

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Automatically pause at the end of subtitles")
                        }
                        Switch {
                            Layout.alignment: Qt.AlignRight
                            checked: MementoSettings.behaviorSubtitlePause
                            onClicked: MementoSettings.behaviorSubtitlePause = checked
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Show subtitles when the cursor is at the bottom of the player")
                        }
                        Switch {
                            Layout.alignment: Qt.AlignRight
                            checked: MementoSettings.behaviorSubtitleCursorShow
                            onClicked: MementoSettings.behaviorSubtitleCursorShow = checked
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Show secondary subtitles when the cursor is at the top of the player")
                        }
                        Switch {
                            Layout.alignment: Qt.AlignRight
                            checked: MementoSettings.behaviorSecondarySubtitleCursorShow
                            onClicked: MementoSettings.behaviorSecondarySubtitleCursorShow = checked
                        }
                    }
                }
            }

            SettingsBox {
                id: openFileDirectoryBox
                Layout.preferredWidth: root.preferredWidth
                Layout.bottomMargin: root.groupSpacing
                Layout.alignment: Qt.AlignHCenter
                title: qsTr("Open File Directory")

                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.groupSpacing

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Open file starting location")
                        }
                        ComboBox {
                            Layout.alignment: Qt.AlignRight
                            implicitContentWidthPolicy: ComboBox.WidestText
                            model: ListModel {
                                ListElement {
                                    text: qsTr("Current")
                                    value: MementoSetting.DirectoryCurrent
                                }
                                ListElement {
                                    text: qsTr("Custom")
                                    value: MementoSetting.DirectoryCustom
                                }
                                ListElement {
                                    text: qsTr("Documents")
                                    value: MementoSetting.DirectoryDocuments
                                }
                                ListElement {
                                    text: qsTr("Home")
                                    value: MementoSetting.DirectoryHome
                                }
                                ListElement {
                                    text: qsTr("Movies")
                                    value: MementoSetting.DirectoryMovies
                                }
                            }
                            textRole: "text"
                            valueRole: "value"
                            currentValue: MementoSettings.behaviorFileOpenDirectory
                            onActivated: MementoSettings.behaviorFileOpenDirectory = currentValue
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Custom file directory")
                        }
                        Button {
                            Layout.alignment: Qt.AlignRight
                            text: qsTr("Browse")
                            onClicked: customFolderDialog.open()
                        }
                    }
                    Label {
                        Layout.alignment: Qt.AlignRight
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        text: MementoSettings.behaviorFileOpenCustom
                    }
                }
            }

            SettingsBox {
                id: togglBox
                Layout.preferredWidth: root.preferredWidth
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: root.groupSpacing
                title: qsTr("Toggl (saved immediately)")

                property var workspaces: []
                property var projects: [{ name: "", label: "" }]
                property string listError: ""

                function loadLists() {
                    togglBox.listError = "";
                    TogglClient.loadWorkspaces();
                    TogglClient.loadProjects();
                }

                Component.onCompleted: {
                    if (TogglClient.hasToken()) {
                        togglBox.loadLists();
                    }
                }

                Connections {
                    target: TogglClient
                    function onWorkspacesLoaded(success, workspaces, error) {
                        if (!success) {
                            togglBox.listError = error;
                            return;
                        }
                        const list = [{ id: 0, name: qsTr("(default workspace)") }].concat(workspaces);
                        togglBox.workspaces = list;
                        workspaceBox.currentIndex = Math.max(0, list.findIndex(w => w.id === TogglClient.workspaceId));
                    }
                    function onProjectsLoaded(success, projects, error) {
                        if (!success) {
                            togglBox.listError = error;
                            return;
                        }
                        let list = [{ id: 0, name: "" }].concat(projects);
                        /* Keep a saved project that isn't in the list (archived, renamed) */
                        if (TogglClient.project.length > 0 &&
                                !list.some(p => p.name.toLowerCase() === TogglClient.project.toLowerCase())) {
                            list.push({ id: -1, name: TogglClient.project });
                        }
                        togglBox.projects = list;
                        projectBox.currentIndex = Math.max(0, list.findIndex(
                            p => p.name.toLowerCase() === TogglClient.project.toLowerCase()));
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.groupSpacing

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: qsTr("Ask to log finished episodes to Toggl")
                        }
                        Switch {
                            Layout.alignment: Qt.AlignRight
                            checked: TogglClient.enabled
                            onClicked: TogglClient.enabled = checked
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: qsTr("Episode end fallback (% of length, when there is no ending chapter or subtitle file)")
                        }
                        SpinBox {
                            Layout.alignment: Qt.AlignRight
                            editable: true
                            from: 50
                            to: 100
                            value: TogglClient.endFallbackPercent
                            onValueModified: TogglClient.endFallbackPercent = value
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: qsTr("Also ask when leaving or closing a file after (% watched)")
                        }
                        SpinBox {
                            Layout.alignment: Qt.AlignRight
                            editable: true
                            from: 10
                            to: 100
                            value: TogglClient.lateAskPercent
                            onValueModified: TogglClient.lateAskPercent = value
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: qsTr("Log time actually played (no pauses or skips) instead of the full length")
                        }
                        Switch {
                            Layout.alignment: Qt.AlignRight
                            checked: TogglClient.usePlayedTime
                            onClicked: TogglClient.usePlayedTime = checked
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: qsTr("API token (toggl.com → Profile settings → API Token)")
                        }
                        TextField {
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 260
                            echoMode: TextInput.Password
                            placeholderText: TogglClient.hasToken() ? qsTr("saved (type to replace)") : qsTr("paste your token")
                            onEditingFinished: {
                                if (text.length > 0) {
                                    TogglClient.setToken(text);
                                    text = "";
                                    togglBox.loadLists();
                                }
                            }
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Workspace")
                        }
                        ComboBox {
                            id: workspaceBox
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 260
                            textRole: "name"
                            valueRole: "id"
                            model: togglBox.workspaces
                            onActivated: {
                                TogglClient.workspaceId = currentValue;
                                TogglClient.loadProjects();
                            }
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Project")
                        }
                        ComboBox {
                            id: projectBox
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 260
                            textRole: "name"
                            valueRole: "name"
                            model: togglBox.projects
                            displayText: currentText.length > 0 ? currentText : qsTr("(no project)")
                            delegate: ItemDelegate {
                                required property var modelData
                                width: projectBox.width
                                text: modelData.name.length > 0 ? modelData.name : qsTr("(no project)")
                            }
                            onActivated: TogglClient.project = currentValue
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: qsTr("Description ({show} and {episode} are filled in)")
                        }
                        TextField {
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 260
                            placeholderText: "{show} E{episode}"
                            text: TogglClient.description
                            onEditingFinished: TogglClient.description = text
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Tags (comma separated, optional)")
                        }
                        TextField {
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 260
                            text: TogglClient.tags
                            onEditingFinished: TogglClient.tags = text
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: qsTr("Manga description ({show} and {volume} are filled in)")
                        }
                        TextField {
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 260
                            placeholderText: "{show} {volume}"
                            text: String(WatchHistory.option("manga-toggl-description", "{show} {volume}"))
                            onEditingFinished: WatchHistory.setOption("manga-toggl-description",
                                                                      text.length > 0 ? text : "{show} {volume}")
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Manga project")
                        }
                        ComboBox {
                            id: mangaProjectBox
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 260
                            textRole: "name"
                            valueRole: "name"
                            model: togglBox.projects
                            currentIndex: Math.max(0, togglBox.projects.findIndex(
                                p => p.name.toLowerCase() === String(WatchHistory.option("manga-toggl-project", "")).toLowerCase()))
                            displayText: currentText.length > 0 ? currentText : qsTr("(no project)")
                            delegate: ItemDelegate {
                                required property var modelData
                                width: mangaProjectBox.width
                                text: modelData.name.length > 0 ? modelData.name : qsTr("(no project)")
                            }
                            onActivated: WatchHistory.setOption("manga-toggl-project", currentValue)
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Label.WordWrap
                        color: togglBox.listError.length > 0 ? "#e06c6c" : MementoPalette.placeholderText
                        text: [
                            togglBox.listError,
                            qsTr("Example: %1").arg(TogglClient.describe("Frieren", "12")),
                            TogglClient.pendingCount > 0 ?
                                qsTr("%1 entry(s) waiting to be sent.").arg(TogglClient.pendingCount) : ""
                        ].filter(x => x.length > 0).join("\n")
                    }
                }
            }

            SettingsBox {
                id: arrowBox
                Layout.preferredWidth: root.preferredWidth
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: root.groupSpacing
                title: qsTr("Arrow keys (saved immediately)")

                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.groupSpacing

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: qsTr("← and → keys")
                        }
                        ComboBox {
                            id: arrowMode
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 260
                            textRole: "text"
                            valueRole: "value"
                            model: [
                                { text: qsTr("Go back/forward a few seconds"), value: "seconds" },
                                { text: qsTr("Previous/next subtitle line"), value: "lines" }
                            ]
                            Component.onCompleted: currentIndex = indexOfValue(WatchHistory.option("arrow-mode", "seconds"))
                            onActivated: WatchHistory.setOption("arrow-mode", currentValue)
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: qsTr("Seconds per key press")
                        }
                        SpinBox {
                            Layout.alignment: Qt.AlignRight
                            enabled: arrowMode.currentValue === "seconds"
                            editable: true
                            from: 1
                            to: 60
                            value: Number(WatchHistory.option("arrow-seconds", 5))
                            onValueModified: WatchHistory.setOption("arrow-seconds", value)
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Label.WordWrap
                        color: MementoPalette.placeholderText
                        text: qsTr("The 10 s buttons on the control bar always jump 10 seconds.")
                    }
                }
            }

            SettingsBox {
                id: malBox
                Layout.preferredWidth: root.preferredWidth
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: root.groupSpacing
                title: qsTr("MyAnimeList (saved immediately)")

                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.groupSpacing

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: qsTr("Offer to update MyAnimeList when an episode ends")
                        }
                        Switch {
                            Layout.alignment: Qt.AlignRight
                            checked: MalClient.enabled
                            onClicked: MalClient.enabled = checked
                        }
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            text: qsTr("Client ID")
                        }
                        TextField {
                            Layout.alignment: Qt.AlignRight
                            Layout.preferredWidth: 300
                            placeholderText: qsTr("from myanimelist.net/apiconfig")
                            text: MalClient.clientId
                            onEditingFinished: MalClient.clientId = text
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Label.WordWrap
                        textFormat: Text.StyledText
                        linkColor: "#6ea8fe"
                        text: qsTr("<a href=\"https://myanimelist.net/apiconfig\">How to get a client ID</a>: on that page click Create ID, App Type <b>other</b>, App Redirect URL <b>%1</b>, fill in the rest, submit, then copy the Client ID here.").arg(MalClient.redirectUri)
                        onLinkActivated: link => MalClient.openUrl(link)
                    }

                    SettingsBoxSeparator {
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignLeft
                            wrapMode: Label.WordWrap
                            text: MalClient.loggedIn ?
                                      qsTr("Logged in as %1").arg(MalClient.userName.length > 0 ? MalClient.userName : "…") :
                                      qsTr("Not logged in")
                        }
                        Button {
                            Layout.alignment: Qt.AlignRight
                            visible: !MalClient.loggedIn
                            enabled: MalClient.clientId.length > 0
                            text: qsTr("Log in…")
                            onClicked: MalClient.login()
                        }
                        Button {
                            Layout.alignment: Qt.AlignRight
                            visible: MalClient.loggedIn
                            text: qsTr("Log out")
                            onClicked: MalClient.logout()
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        wrapMode: Label.WordWrap
                        color: MementoPalette.placeholderText
                        text: [
                            MalClient.loginStatus,
                            MalClient.pendingCount > 0 ? qsTr("%1 update(s) waiting to be sent.").arg(MalClient.pendingCount) : ""
                        ].filter(x => x.length > 0).join("\n")
                    }
                }
            }
        }
    }
}

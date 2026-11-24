import QtQuick
import Ripose.Memento

/* Fork: keeps the Yomitan overlay in step with the player. Several times a
 * second it sends where the player is on screen, whether the overlay should
 * show, and the text shown now (subtitles, or the manga pages) with every
 * character's box. YomitanOverlay only passes on what changed. */
Item {
    id: root

    required property Item player
    required property Item subtitleItem
    required property Item mangaView

    /* Something covers the player (library, lists, OCR...) */
    property bool blocked: false

    visible: false

    function update() {
        const origin = root.player.mapToGlobal(0, 0);
        const visibility = root.player.Window.visibility;
        const reading = root.mangaView.visible && root.mangaView.reader.visible;
        /* Clicking Yomitan's popup can take activation from Memento for a
         * moment; hiding then would swallow the click (e.g. on +) */
        const active = Qt.application.state === Qt.ApplicationActive ||
                       YomitanOverlay.popupHover || YomitanOverlay.hover;
        const shown = active &&
                      visibility !== Window.Minimized &&
                      visibility !== Window.Hidden &&
                      Utils.modalDialogs === 0 &&
                      !root.blocked;

        YomitanOverlay.setWindow(origin.x, origin.y, root.player.width, root.player.height, shown);
        if (!shown) {
            /* Why it's hidden goes to the overlay log */
            const why = [];
            if (!active) why.push("app inactive");
            if (visibility === Window.Minimized || visibility === Window.Hidden) why.push("minimized");
            if (Utils.modalDialogs !== 0) why.push("dialogs=" + Utils.modalDialogs);
            if (root.blocked) why.push("blocked");
            YomitanOverlay.setText([], "hidden: " + why.join(", "));
            return;
        }
        if (reading) {
            YomitanOverlay.setText(root.mangaView.reader.overlayBlocks(root.player), "");
        } else if (root.subtitleItem.visible && root.subtitleItem.text.length > 0) {
            YomitanOverlay.setText(
                [{ vertical: false, lines: root.subtitleItem.charBoxes(root.player) }],
                root.subtitleItem.font.family);
        } else {
            YomitanOverlay.setText([], "");
        }
    }

    Timer {
        interval: 80
        repeat: true
        running: YomitanOverlay.active
        onTriggered: root.update()
    }
}

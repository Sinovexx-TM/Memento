import QtQuick
import QtQuick.Controls
import Ripose.Memento

/*
 * Controller navigation for every page except manga: finds the clickable
 * things (buttons, rows, menu items, dialog buttons) on the page or dialog
 * on top, moves a white outline between them with the D-pad, and A clicks
 * the selected one as the mouse would. B = Esc (back / close).
 */
Item {
    id: root

    required property var player
    required property var library
    required property var animeList
    required property var mangaViews

    /* The selected item (null = none yet) */
    property var current: null

    function pageScope() {
        for (const view of root.mangaViews) {
            if (view.visible)
                return view;
        }
        if (root.animeList.visible)
            return root.animeList;
        if (root.library.visible)
            return root.library;
        return null;
    }

    function clickable(item) {
        if (!item || !item.visible || !item.enabled || item.opacity <= 0)
            return false;
        if (item.width < 4 || item.height < 4)
            return false;
        return typeof item.clicked === "function";
    }

    function collect(item, scope, out) {
        if (!item || !item.visible || item === highlight)
            return;
        if (item !== scope && root.clickable(item)) {
            /* Leave out full-page mouse blockers */
            if (!(item.width >= scope.width * 0.8 && item.height >= scope.height * 0.8))
                out.push(item);
            return;
        }
        const kids = item.children;
        for (let i = 0; i < kids.length; ++i)
            root.collect(kids[i], scope, out);
    }

    function targetsIn(scope) {
        const out = [];
        root.collect(scope, scope, out);
        return out;
    }

    /* The dialog / menu on top if one is open, else the page */
    function scope() {
        const page = root.pageScope();
        const overlay = Overlay.overlay;
        if (overlay && (page !== null || Utils.modalDialogs > 0)) {
            const kids = overlay.children;
            for (let i = kids.length - 1; i >= 0; --i) {
                const k = kids[i];
                if (k.visible && k !== highlight && root.targetsIn(k).length > 0)
                    return k;
            }
        }
        return page;
    }

    function centre(item) {
        return item.mapToItem(null, item.width / 2, item.height / 2);
    }

    function flickableOf(item) {
        for (let p = item.parent; p; p = p.parent) {
            if (p.contentY !== undefined && p.contentHeight !== undefined && typeof p.flick === "function")
                return p;
        }
        return null;
    }

    function scrollTo(item) {
        const flick = root.flickableOf(item);
        if (!flick)
            return;
        const p = item.mapToItem(flick, 0, 0);
        const minY = flick.originY;
        const maxY = flick.originY + Math.max(0, flick.contentHeight - flick.height);
        if (p.y < 10)
            flick.contentY = Math.max(minY, flick.contentY + p.y - 40);
        else if (p.y + item.height > flick.height - 10)
            flick.contentY = Math.min(maxY, flick.contentY + p.y + item.height - flick.height + 40);
    }

    function select(item) {
        root.current = item;
        root.scrollTo(item);
        highlight.follow();
    }

    /* true = handled (or swallowed); false = the player should act */
    function handle(name) {
        /* Manga reader: left / right turn pages, B goes back */
        const reader = root.mangaViews[0].reader;
        if (reader && reader.visible && Utils.modalDialogs === 0) {
            if (name === "left")
                Gamepad.key(Qt.Key_Left);
            else if (name === "right")
                Gamepad.key(Qt.Key_Right);
            else if (name === "b")
                Gamepad.key(Qt.Key_Escape);
            return true;
        }
        const scope = root.scope();
        if (scope === null)
            return false;

        if (name === "b") {
            root.current = null;
            if (scope === root.library)
                root.library.handleGamepad("b");
            else if (root.mangaViews.indexOf(scope) >= 0 && typeof scope.back === "function")
                scope.back();
            else
                Gamepad.key(Qt.Key_Escape);
            return true;
        }

        const list = root.targetsIn(scope);
        if (list.length === 0)
            return true;
        const cur = list.indexOf(root.current);
        if (cur < 0) {
            if (["up", "down", "left", "right", "a"].indexOf(name) < 0)
                return true;
            /* First press selects: the next episode, else the top-left item */
            const next = list.find(item => item.parent && item.parent.isNext === true);
            const sorted = list.slice().sort((a, b) => {
                const pa = root.centre(a), pb = root.centre(b);
                return Math.abs(pa.y - pb.y) > 5 ? pa.y - pb.y : pa.x - pb.x;
            });
            root.select(next ?? sorted[0]);
            return true;
        }
        if (name === "a") {
            const item = root.current;
            root.current = null;
            Gamepad.click(item);
            /* Keep the selection when the same page stays */
            Qt.callLater(() => { if (item && item.visible) root.current = item; highlight.follow(); });
            return true;
        }
        if (["up", "down", "left", "right"].indexOf(name) < 0)
            return true;

        const c = root.centre(list[cur]);
        const vertical = name === "up" || name === "down";
        const sign = name === "down" || name === "right" ? 1 : -1;
        let best = null;
        let bestScore = Infinity;
        for (let i = 0; i < list.length; ++i) {
            if (i === cur)
                continue;
            const p = root.centre(list[i]);
            const along = vertical ? (p.y - c.y) * sign : (p.x - c.x) * sign;
            const across = vertical ? Math.abs(p.x - c.x) : Math.abs(p.y - c.y);
            if (along <= 5)
                continue;
            /* Prefer the same row / column, then the nearest */
            const score = along + across * 3;
            if (score < bestScore) {
                bestScore = score;
                best = list[i];
            }
        }
        if (best === null && !vertical) {
            /* Row ends: wrap to the previous / next item in reading order */
            const target = cur + sign;
            if (target >= 0 && target < list.length)
                best = list[target];
        }
        if (best !== null)
            root.select(best);
        return true;
    }

    /* White outline around the selected item, above everything */
    Rectangle {
        id: highlight
        parent: Overlay.overlay
        z: 100000
        color: "transparent"
        border.color: "white"
        border.width: 2
        radius: 6
        visible: false

        function follow() {
            const item = root.current;
            if (!item || !item.visible || !item.parent || !highlight.parent) {
                highlight.visible = false;
                return;
            }
            const p = item.mapToItem(highlight.parent, 0, 0);
            highlight.x = p.x - 3;
            highlight.y = p.y - 3;
            highlight.width = item.width + 6;
            highlight.height = item.height + 6;
            highlight.visible = true;
        }

        Timer {
            interval: 60
            repeat: true
            running: root.current !== null
            onTriggered: highlight.follow()
            onRunningChanged: if (!running) highlight.visible = false
        }
    }
}

pragma Singleton

import QtQml
import QtQuick

/**
 * Colours of the dictionary popup and search results: a dark theme in the
 * style of Yomitan's dark popup. Only the definition views use it; the rest
 * of Memento keeps the system palette (MementoPalette).
 */
QtObject {
    readonly property color window: "#1e1e1e"
    readonly property color base: "#1e1e1e"
    readonly property color alternate: "#262626"
    readonly property color text: "#d4d4d4"
    readonly property color strongText: "#ececec"
    readonly property color dimText: "#9a9a9a"
    readonly property color border: "#3a3a3a"
    readonly property color highlight: "#2f5f8f"
    readonly property color highlightedText: "#ffffff"
    readonly property color button: "#2a2a2a"
    readonly property color frequencyValue: "#2b2b2b"
}

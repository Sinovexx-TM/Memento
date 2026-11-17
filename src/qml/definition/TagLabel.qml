import QtQuick
import Ripose.Memento

MetaLabel {
    id: root

    required property Tag tag

    text: root.tag?.name ?? ""
    tip: root.tag?.notes ?? ""
    color: {
        if (root.tag.category === "name")
        {
            return "#a0306e";
        }
        else if (root.tag.category === "expression")
        {
            return "#c08a3e";
        }
        else if (root.tag.category === "popular")
        {
            return "#1f5c99";
        }
        else if (root.tag.category === "frequent")
        {
            return "#3d7a8c";
        }
        else if (root.tag.category === "archaism")
        {
            return "#b04a46";
        }
        else if (root.tag.category === "dictionary")
        {
            return "#9150ad";
        }
        else if (root.tag.category === "frequency")
        {
            return "#5cb85c";
        }
        else if (root.tag.category === "partOfSpeech")
        {
            return "#565656";
        }
        else if (root.tag.category === "search")
        {
            return "#8a8a91";
        }
        else if (root.tag.category === "pitch-accent-dictionary")
        {
            return "#6640be";
        }
        else
        {
            return "#8a8a91";
        }
    }
}

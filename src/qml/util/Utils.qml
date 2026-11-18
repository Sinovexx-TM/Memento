pragma Singleton

import QtCore
import QtQml
import Ripose.Memento

QtObject {
    /* Number of modal dialogs currently open. Dialogs started from the
     * dictionary popup raise it so the popup is not closed from under them. */
    property int modalDialogs: 0

    /**
     * Converts a built-in image name and color to a colored-image URL.
     * @param name The name of the SVG icon in the images/ path.
     * @param color The color to set the text to.
     * @return The image provider path for that SVG and color.
     */
    function toImageProvider(name, color) {
        const componentToHex = function(c) {
            const hex = Math.round(c * 255).toString(16);
            return hex.length === 1 ? "0" + hex : hex;
        };
        const colorString = componentToHex(color.a) +
                          componentToHex(color.r) +
                          componentToHex(color.g) +
                          componentToHex(color.b);
        const sourcePath = `:/images/${name}.svg`;
        return "image://colored-image/resource/" +
               `${encodeURIComponent(sourcePath)}/${colorString}`;
    }

    /**
     * Creates a regex, or a regex that matches nothing if the pattern is
     * invalid.
     * @param pattern The regex pattern.
     * @param flags The regex flags.
     * @return A RegExp object.
     */
    function safeRegex(pattern, flags) {
        try
        {
            return new RegExp(pattern, flags);
        }
        catch (error)
        {
            return /$a/; // This matches nothing
        }
    }

    /**
     * Makes a time string from a duration.
     * @param time The duration in seconds.
     * @return The time as a string in the format [H:]MM:SS
     */
    function toTimeString(time) {
        const SECONDS_IN_HOUR = 3600;
        const SECONDS_IN_MINUTE = 60;

        time = Math.floor(time);
        const hours = Math.floor(time / SECONDS_IN_HOUR);
        time -= hours * SECONDS_IN_HOUR;
        const minutes = Math.floor(time / SECONDS_IN_MINUTE);
        time -= minutes * SECONDS_IN_MINUTE;
        const seconds = time;

        let result = "";
        if (hours)
        {
            result += `${hours}:`;
        }
        result += `${minutes.toString().padStart(2, "0")}:`;
        result += seconds.toString().padStart(2, "0");
        return result;
    }

    /**
     * Gets the path of the directory type requested.
     * @param dir The MementoSetting.Directory type.
     */
    function getFileOpenDirectory(dir) {
        switch (dir)
        {
        case MementoSetting.DirectoryCurrent:
            return ".";
        case MementoSetting.DirectoryMovies:
            return StandardPaths.standardLocations(
                StandardPaths.MoviesLocation
            )[0];
        case MementoSetting.DirectoryDocuments:
            return StandardPaths.standardLocations(
                StandardPaths.DocumentsLocation
            )[0];
        case MementoSetting.DirectoryCustom:
            return MementoSettings.behaviorFileOpenCustom;
        case MementoSetting.DirectoryHome:
        default:
            return StandardPaths.standardLocations(
                StandardPaths.HomeLocation
            )[0];
        }
    }

    /**
     * Fold frequencies into a model where entries from the same dictionary
     * have their name omitted.
     * @param frequencies The list of Frequency objects.
     * @return An array of objects containing name and value properties.
     */
    function foldFrequencies(frequencies) {
        if (!frequencies)
        {
            return [];
        }

        let freqs = [];
        let currentName = null;
        for (let i = 0; i < frequencies.length; ++i)
        {
            const freq = frequencies[i];
            if (freq.dictionaryInfo.name === currentName)
            {
                freqs.push({
                    "name": "",
                    "value": freq.frequency,
                });
            }
            else
            {
                currentName = freq.dictionaryInfo.name;
                freqs.push({
                    "name": currentName,
                    "value": freq.frequency,
                });
            }

        }
        return freqs;
    }

    /**
     * Cleans separators and stray characters in a name fragment.
     */
    function cleanMediaText(s) {
        s = s.replace(/_/g, " ");
        if (s.trim().indexOf(" ") === -1) {
            s = s.replace(/\./g, " ");
        }
        return s.replace(/\s+/g, " ").replace(/^[ \-._]+|[ \-._]+$/g, "");
    }

    /**
     * Splits one file name (no folder) into a show name and an episode label.
     * Brackets and parentheses are dropped first. Port of a tested prototype.
     * @return {title, episode}; episode is "" when none was found.
     */
    function parseMediaFileName(name) {
        const tags = /\b(\d{3,4}p|\d{3,4}x\d{3,4}|x26[45]|h\.?26[45]|hevc|av1|avc|aac|flac|opus|ac3|eac3|dts|10bit|8bit|web[- ]?dl|web[- ]?rip|bd[- ]?rip|blu[- ]?ray|bd|dvd|dvdrip|hdtv|raw|multi[- ]?subs?|dual[- ]?audio|repack|proper|batch|uncensored|nf|amzn|cr|crunchyroll)\b/gi;
        const plain = name.replace(/\.[A-Za-z0-9]{2,4}$/, "");
        let s = plain.replace(/\[[^\]]*\]|\([^)]*\)|\{[^}]*\}|【[^】]*】/g, " ");
        s = Utils.cleanMediaText(s);

        const patterns = [
            [/^(.*?)[ ._-]*\bS(\d{1,2})[ ._-]*E(\d{1,3})\b/i, "se"],
            [/^(.*?)[ ._-]*\b(\d{1,2})x(\d{2,3})\b/i, "se"],
            [/^(.*?)[ ._-]*\bSeason[ ._]?(\d{1,2})[ ._-]*(?:Episode|Ep|E)?[ ._]*(\d{1,3})\b/i, "se"],
            [/^(.*?)[ ._-]*\b(?:Episode|Ep|E)[ ._]*(\d{1,3})\b/i, "e"],
            [/^(.*?)[ ._-]*第\s*(\d{1,3})\s*[話话回]/i, "e"],
            [/^(.*?)[ ._-]*#\s*(\d{1,3})\b/i, "e"],
            [/^(.*?)\s+-\s+(\d{1,3})(?:v\d)?(?:\s|$)/i, "e"]
        ];

        let show = null;
        let season = null;
        let episode = null;
        for (let i = 0; i < patterns.length; ++i) {
            const m = s.match(patterns[i][0]);
            if (m && m[1].trim().length > 0) {
                show = m[1];
                if (patterns[i][1] === "se") {
                    season = parseInt(m[2]);
                    episode = parseInt(m[3]);
                } else {
                    episode = parseInt(m[2]);
                }
                break;
            }
        }
        if (show === null) {
            const m = s.match(/^(.*\D)\s+(\d{1,3})$/);
            if (m && m[1].trim().length > 0) {
                show = m[1];
                episode = parseInt(m[2]);
            }
        }
        if (show === null) {
            /* No episode (a movie): cut at the year or the first release tag
             * ("Dragon Ball Super Broly 2018 v3 BluRay ..." -> "Dragon Ball Super Broly") */
            const m = s.match(/^(.*?\S)\s+(?:(?:19|20)\d{2}|v\d|\d{3,4}p|blu[- ]?ray|bd(?:rip)?|web(?:[- ]?(?:dl|rip))?|dvd(?:rip)?|hdtv|amzn|nf|cr)(?=\s|-|$)/i);
            show = m ? m[1] : s;
        }

        show = Utils.cleanMediaText(show.replace(tags, " "));
        if (show.length === 0) {
            return { title: plain, episode: "" };
        }
        let label = "";
        if (episode !== null) {
            label = season !== null
                ? qsTr("Season %1 · Episode %2").arg(season).arg(episode)
                : qsTr("Episode %1").arg(episode);
        }
        return { title: show, episode: label };
    }

    /**
     * Works out what to show for the playing media.
     * Files named only by a number or tag ("01.mkv", "PV2.mkv") take the show
     * name from their folder. Streams use mpv's own title.
     *
     * @param path The full path or URL of the media.
     * @param mediaTitle mpv's media title (used for streams).
     * @return {title, episode}
     */
    function parseMediaInfo(path, mediaTitle) {
        if (!path || path.length === 0) {
            return { title: mediaTitle ?? "", episode: "" };
        }
        if (/^[A-Za-z][A-Za-z0-9+.-]*:\/\//.test(path) && !/^file:/i.test(path)) {
            return { title: mediaTitle && mediaTitle.length > 0 ? mediaTitle : path, episode: "" };
        }

        const parts = path.split(/[\\/]/).filter(p => p.length > 0);
        const name = parts.length > 0 ? parts[parts.length - 1] : path;
        const base = name.replace(/\.[A-Za-z0-9]{2,4}$/, "").trim();
        let r = Utils.parseMediaFileName(name);

        /* Episode written as a lone bracket group: "Show [03][1080p]" */
        if (r.episode.length === 0) {
            const m = name.match(/\[(\d{1,3})(?:v\d)?\]/);
            if (m) {
                r.episode = qsTr("Episode %1").arg(parseInt(m[1]));
            }
        }

        /* Extras: "Show - SP1", "Show - ED", or a bracket like [Drama05] */
        if (r.episode.length === 0) {
            let m = r.title.match(/^(.*?)\s+-\s+((?:NC)?(?:SP|OP|ED|OVA|ONA|PV|CM|Special)\d*)$/i);
            if (m && m[1].trim().length > 0) {
                r = { title: m[1].trim(), episode: m[2] };
            } else {
                m = name.match(/\[([A-Za-z]{2,8}\d{1,3})\]/);
                if (m) {
                    r.episode = m[1];
                }
            }
        }

        /* Bare file names: the show is the parent folder */
        const bare = base.match(/^(\d{1,3})$/);
        const shortName = base.match(/^[A-Za-z]{1,6}\d{0,2}$/);
        if ((bare || shortName) && parts.length >= 2) {
            const folder = Utils.parseMediaFileName(parts[parts.length - 2]).title;
            if (folder.length > 0) {
                return {
                    title: folder,
                    episode: bare ? qsTr("Episode %1").arg(parseInt(base)) : base
                };
            }
        }
        return r;
    }
}

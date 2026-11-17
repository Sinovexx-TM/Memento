#ifndef SUBFILES_H
#define SUBFILES_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>

/**
 * @brief File helpers for subtitle matching (SubMatch.js does the matching).
 */
class SubFiles : public QObject
{
    Q_OBJECT

public:
    explicit SubFiles(QObject *parent = nullptr);

    /**
     * @brief The folder of a local file, "" for streams.
     */
    Q_INVOKABLE QString folderOf(const QString &path) const;

    /**
     * @brief File name of a path.
     */
    Q_INVOKABLE QString fileNameOf(const QString &path) const;

    /**
     * @brief Video file names in a folder.
     */
    Q_INVOKABLE QStringList videos(const QString &folder) const;

    /**
     * @brief Subtitle files in a folder and its "subs" subfolder.
     * @return [{ name, dir ("" or the subfolder name), path, lang }], lang
     * "ja" when the text contains Japanese, else "".
     */
    Q_INVOKABLE QVariantList subtitles(const QString &folder) const;

    /**
     * @brief "ja" if the file's text contains Japanese, else "".
     */
    Q_INVOKABLE QString languageOf(const QString &path) const;

    /**
     * @brief Rename (or move) a file. Never overwrites.
     * @return "" on success, otherwise a short error.
     */
    Q_INVOKABLE QString rename(const QString &from, const QString &to) const;

    /**
     * @brief Join a folder and a file name.
     */
    Q_INVOKABLE QString join(const QString &folder, const QString &name) const;
};

#endif // SUBFILES_H

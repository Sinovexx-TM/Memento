#ifndef WATCHHISTORY_H
#define WATCHHISTORY_H

#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

/**
 * @brief Watch history and the anime library folder.
 *
 * History lives in watch_history.json in the config folder:
 * { "episodes": { key: { pos, dur, done, date, watchedDate } },
 *   "names": { folder key: display name } }.
 * Keys are made by Library.js (normalised paths). Dates are ms since epoch.
 */
class WatchHistory : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString libraryRoot READ libraryRoot WRITE setLibraryRoot NOTIFY libraryRootChanged)

public:
    explicit WatchHistory(QObject *parent = nullptr);

    QString libraryRoot() const;
    void setLibraryRoot(const QString &path);

    /**
     * @brief Series folders directly inside the library folder.
     * @return [{ name, path }] sorted by name.
     */
    Q_INVOKABLE QVariantList seriesFolders() const;

    /**
     * @brief Video files in a series folder and its subfolders (3 levels).
     * @return [{ rel (path relative to the folder, "/"), path }].
     */
    Q_INVOKABLE QVariantList videosIn(const QString &folder) const;

    /**
     * @brief Video files directly in the library folder (not in a series
     * folder). Library.js groups them by show name.
     * @return [{ rel (file name), path }].
     */
    Q_INVOKABLE QVariantList looseVideos() const;

    /**
     * @brief All episode entries, keyed as stored.
     */
    Q_INVOKABLE QVariantMap entries() const;

    /**
     * @brief Saves the position of an episode. Once done it stays done
     * (only setWatched clears it).
     */
    Q_INVOKABLE void record(const QString &key, double pos, double duration, bool done);

    /**
     * @brief Marks episodes watched or unwatched.
     */
    Q_INVOKABLE void setWatched(const QStringList &keys, bool watched);

    /**
     * @brief Custom display names of series folders.
     */
    Q_INVOKABLE QVariantMap names() const;
    Q_INVOKABLE void setName(const QString &key, const QString &name);

    /**
     * @brief Turns a file:// URL from a folder dialog into a local path.
     */
    Q_INVOKABLE QString localPath(const QUrl &url) const;

    /**
     * @brief AniList info per series key: { id, title, english, native,
     * posterUrl, poster (local file URL), none (true = nothing found) }.
     */
    Q_INVOKABLE QVariantMap media() const;

    /**
     * @brief Searches AniList for anime. Emits aniListResults(tag, ...).
     * Results: [{ id, title, english, native, posterUrl, episodes, year, format }]
     */
    Q_INVOKABLE void searchAniList(const QString &query, const QString &tag);

    /**
     * @brief Saves the AniList entry of a series and downloads its poster.
     * An empty map clears it; { none: true } = no poster (fallback tile).
     */
    Q_INVOKABLE void setMedia(const QString &key, const QVariantMap &media);

signals:
    void changed();
    void libraryRootChanged();
    void aniListResults(const QString &tag, bool success, const QVariantList &results, const QString &error);

private:
    void load();
    void save();

    void downloadPoster(const QString &key, const QString &url, int id);

    QVariantMap m_episodes;
    QVariantMap m_names;
    QVariantMap m_media;
    QNetworkAccessManager m_manager;
};

#endif // WATCHHISTORY_H

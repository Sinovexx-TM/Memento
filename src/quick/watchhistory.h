#ifndef WATCHHISTORY_H
#define WATCHHISTORY_H

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

signals:
    void changed();
    void libraryRootChanged();

private:
    void load();
    void save();

    QVariantMap m_episodes;
    QVariantMap m_names;
};

#endif // WATCHHISTORY_H

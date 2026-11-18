#include "watchhistory.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>

#include "util/directoryutils.h"

namespace
{
constexpr const char *GROUP = "library";
const QStringList VIDEO_FILTERS{"*.mkv", "*.mp4", "*.avi", "*.webm", "*.m4v", "*.mov"};
constexpr int MAX_DEPTH = 3;

QString historyFile()
{
    return QDir(DirectoryUtils::getConfigDir()).filePath("watch_history.json");
}

qint64 now()
{
    return QDateTime::currentMSecsSinceEpoch();
}
}

WatchHistory::WatchHistory(QObject *parent) : QObject(parent)
{
    load();
}

QString WatchHistory::libraryRoot() const
{
    QSettings settings;
    settings.beginGroup(GROUP);
    QString root = settings.value("root").toString();
    if (root.isEmpty())
    {
        /* Default: Documents/Anime Files/Anime when it exists */
        const QString guess = QDir(
            QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation))
            .filePath("Anime Files/Anime");
        if (QFileInfo(guess).isDir())
        {
            root = guess;
        }
    }
    return root.isEmpty() ? QString() : QDir::cleanPath(root);
}

void WatchHistory::setLibraryRoot(const QString &path)
{
    QSettings settings;
    settings.beginGroup(GROUP);
    settings.setValue("root", path);
    emit libraryRootChanged();
}

QVariantList WatchHistory::seriesFolders() const
{
    QVariantList result;
    const QString root = libraryRoot();
    if (root.isEmpty())
    {
        return result;
    }
    QDir dir(root);
    const QStringList names = dir.entryList(
        QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::IgnoreCase);
    for (const QString &name : names)
    {
        result << QVariantMap{
            {"name", name},
            {"path", QDir::cleanPath(dir.filePath(name))},
        };
    }
    return result;
}

QVariantList WatchHistory::videosIn(const QString &folder) const
{
    QVariantList result;
    if (folder.isEmpty())
    {
        return result;
    }
    const QDir base(folder);
    QDirIterator it(folder, VIDEO_FILTERS, QDir::Files, QDirIterator::Subdirectories);
    while (it.hasNext())
    {
        const QString path = QDir::cleanPath(it.next());
        const QString rel = base.relativeFilePath(path);
        if (rel.count('/') > MAX_DEPTH)
        {
            continue;
        }
        result << QVariantMap{{"rel", rel}, {"path", path}};
    }
    return result;
}

QVariantMap WatchHistory::entries() const
{
    return m_episodes;
}

void WatchHistory::record(const QString &key, double pos, double duration, bool done)
{
    if (key.isEmpty())
    {
        return;
    }
    QVariantMap entry = m_episodes.value(key).toMap();
    const bool wasDone = entry.value("done").toBool();
    entry["pos"] = pos;
    if (duration > 0)
    {
        entry["dur"] = duration;
    }
    entry["date"] = now();
    if (done && !wasDone)
    {
        entry["done"] = true;
        entry["watchedDate"] = now();
    }
    m_episodes[key] = entry;
    save();
    emit changed();
}

void WatchHistory::setWatched(const QStringList &keys, bool watched)
{
    for (const QString &key : keys)
    {
        QVariantMap entry = m_episodes.value(key).toMap();
        if (watched)
        {
            if (entry.value("done").toBool())
            {
                continue;
            }
            entry["done"] = true;
            entry["watchedDate"] = now();
            entry["date"] = now();
        }
        else
        {
            entry.remove("done");
            entry.remove("watchedDate");
            entry["pos"] = 0;
        }
        m_episodes[key] = entry;
    }
    save();
    emit changed();
}

QVariantMap WatchHistory::names() const
{
    return m_names;
}

void WatchHistory::setName(const QString &key, const QString &name)
{
    if (name.trimmed().isEmpty())
    {
        m_names.remove(key);
    }
    else
    {
        m_names[key] = name.trimmed();
    }
    save();
    emit changed();
}

QString WatchHistory::localPath(const QUrl &url) const
{
    return url.isLocalFile() ? QDir::cleanPath(url.toLocalFile()) : url.toString();
}

void WatchHistory::load()
{
    QFile file(historyFile());
    if (!file.open(QIODevice::ReadOnly))
    {
        return;
    }
    const QJsonObject obj = QJsonDocument::fromJson(file.readAll()).object();
    m_episodes = obj.value("episodes").toObject().toVariantMap();
    m_names = obj.value("names").toObject().toVariantMap();
}

void WatchHistory::save()
{
    QJsonObject obj;
    obj["version"] = 1;
    obj["episodes"] = QJsonObject::fromVariantMap(m_episodes);
    obj["names"] = QJsonObject::fromVariantMap(m_names);

    QSaveFile file(historyFile());
    if (!file.open(QIODevice::WriteOnly))
    {
        return;
    }
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    file.commit();
}

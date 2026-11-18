#include "watchhistory.h"

#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
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
    m_manager.setTransferTimeout(20000);
    load();
}

QString WatchHistory::libraryRoot() const
{
    QSettings settings;
    settings.beginGroup(GROUP);
    const QString root = settings.value("root").toString();
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

QVariantList WatchHistory::looseVideos() const
{
    QVariantList result;
    const QString root = libraryRoot();
    if (root.isEmpty())
    {
        return result;
    }
    QDir dir(root);
    for (const QString &name : dir.entryList(VIDEO_FILTERS, QDir::Files, QDir::Name))
    {
        result << QVariantMap{
            {"rel", name},
            {"path", QDir::cleanPath(dir.filePath(name))},
        };
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

QVariant WatchHistory::option(const QString &key, const QVariant &fallback) const
{
    QSettings settings;
    settings.beginGroup("fork");
    return settings.value(key, fallback);
}

void WatchHistory::setOption(const QString &key, const QVariant &value)
{
    QSettings settings;
    settings.beginGroup("fork");
    settings.setValue(key, value);
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
    m_media = obj.value("media").toObject().toVariantMap();
}

void WatchHistory::save()
{
    QJsonObject obj;
    obj["version"] = 1;
    obj["episodes"] = QJsonObject::fromVariantMap(m_episodes);
    obj["names"] = QJsonObject::fromVariantMap(m_names);
    obj["media"] = QJsonObject::fromVariantMap(m_media);

    QSaveFile file(historyFile());
    if (!file.open(QIODevice::WriteOnly))
    {
        return;
    }
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    file.commit();
}

QVariantMap WatchHistory::media() const
{
    return m_media;
}

void WatchHistory::searchAniList(const QString &query, const QString &tag)
{
    static const QString gql =
        "query ($q: String) { Page(perPage: 12) { media(search: $q, type: ANIME) {"
        " id title { romaji english native } coverImage { large extraLarge }"
        " episodes seasonYear format } } }";
    QJsonObject variables;
    variables["q"] = query.trimmed();
    QJsonObject body;
    body["query"] = gql;
    body["variables"] = variables;

    QNetworkRequest request{QUrl("https://graphql.anilist.co")};
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setRawHeader("Accept", "application/json");
    QNetworkReply *reply = m_manager.post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [this, reply, tag] {
        reply->deleteLater();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QJsonObject obj = QJsonDocument::fromJson(reply->readAll()).object();
        if (status != 200)
        {
            emit aniListResults(tag, false, {}, status > 0 ?
                QStringLiteral("AniList HTTP %1").arg(status) : reply->errorString());
            return;
        }
        QVariantList results;
        const QJsonArray list = obj.value("data").toObject().value("Page").toObject()
            .value("media").toArray();
        for (const auto &item : list)
        {
            const QJsonObject m = item.toObject();
            const QJsonObject title = m.value("title").toObject();
            const QJsonObject cover = m.value("coverImage").toObject();
            QString poster = cover.value("extraLarge").toString();
            if (poster.isEmpty())
            {
                poster = cover.value("large").toString();
            }
            results << QVariantMap{
                {"id", m.value("id").toInt()},
                {"title", title.value("romaji").toString()},
                {"english", title.value("english").toString()},
                {"native", title.value("native").toString()},
                {"posterUrl", poster},
                {"episodes", m.value("episodes").toInt()},
                {"year", m.value("seasonYear").toInt()},
                {"format", m.value("format").toString()},
            };
        }
        emit aniListResults(tag, true, results, QString());
    });
}

void WatchHistory::setMedia(const QString &key, const QVariantMap &media)
{
    if (media.isEmpty())
    {
        m_media.remove(key);
    }
    else
    {
        m_media[key] = media;
    }
    save();
    emit changed();

    const QString url = media.value("posterUrl").toString();
    if (!url.isEmpty())
    {
        downloadPoster(key, url, media.value("id").toInt());
    }
}

void WatchHistory::downloadPoster(const QString &key, const QString &url, int id)
{
    const QString folder = QDir(DirectoryUtils::getConfigDir()).filePath("posters");
    QDir().mkpath(folder);
    QString ext = QUrl(url).fileName().section('.', -1).toLower();
    if (ext.isEmpty() || ext.size() > 4)
    {
        ext = "jpg";
    }
    const QString file = QDir(folder).filePath(QStringLiteral("anilist_%1.%2").arg(id).arg(ext));

    auto store = [this, key, file] {
        QVariantMap media = m_media.value(key).toMap();
        if (media.isEmpty())
        {
            return;
        }
        media["poster"] = QUrl::fromLocalFile(file).toString();
        m_media[key] = media;
        save();
        emit changed();
    };
    if (QFileInfo::exists(file))
    {
        store();
        return;
    }

    QNetworkReply *reply = m_manager.get(QNetworkRequest{QUrl(url)});
    connect(reply, &QNetworkReply::finished, this, [reply, file, store] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError)
        {
            return;
        }
        QSaveFile out(file);
        if (out.open(QIODevice::WriteOnly))
        {
            out.write(reply->readAll());
            if (out.commit())
            {
                store();
            }
        }
    });
}

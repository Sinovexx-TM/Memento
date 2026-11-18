#include "malclient.h"

#include <QByteArrayList>
#include <QDateTime>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QSettings>
#include <QTcpSocket>
#include <QTimer>
#include <QUrlQuery>

#include "util/directoryutils.h"

namespace
{
constexpr const char *GROUP = "mal";
constexpr quint16 PORT = 47215;
constexpr const char *AUTH_URL = "https://myanimelist.net/v1/oauth2/authorize";
constexpr const char *TOKEN_URL = "https://myanimelist.net/v1/oauth2/token";
constexpr const char *API = "https://api.myanimelist.net/v2";
constexpr int TIMEOUT_MS = 20000;
constexpr int LOGIN_TIMEOUT_MS = 5 * 60 * 1000;
constexpr const char *LIST_FIELDS =
    "list_status{status,num_episodes_watched,start_date,finish_date},"
    "num_episodes,alternative_titles,media_type";
constexpr const char *MANGA_FIELDS =
    "list_status{status,num_chapters_read,num_volumes_read,start_date,finish_date},"
    "num_chapters,num_volumes,alternative_titles,media_type";

QString configFile(const QString &name)
{
    return QDir(DirectoryUtils::getConfigDir()).filePath(name);
}

QJsonDocument readJson(const QString &name)
{
    QFile file(configFile(name));
    if (!file.open(QIODevice::ReadOnly))
    {
        return {};
    }
    return QJsonDocument::fromJson(file.readAll());
}

void writeJson(const QString &name, const QJsonDocument &doc)
{
    QSaveFile file(configFile(name));
    if (!file.open(QIODevice::WriteOnly))
    {
        return;
    }
    file.write(doc.toJson(QJsonDocument::Indented));
    file.commit();
}

QString randomString(int length)
{
    /* PKCE code verifier characters (RFC 7636 "unreserved") */
    static const QString chars =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
    QString result;
    result.reserve(length);
    for (int i = 0; i < length; ++i)
    {
        result += chars.at(QRandomGenerator::system()->bounded(chars.size()));
    }
    return result;
}

QByteArray formEncode(const QList<QPair<QString, QString>> &pairs)
{
    QByteArrayList items;
    for (const auto &pair : pairs)
    {
        items << QUrl::toPercentEncoding(pair.first) + "=" + QUrl::toPercentEncoding(pair.second);
    }
    return items.join('&');
}

qint64 nowSecs()
{
    return QDateTime::currentSecsSinceEpoch();
}
}

MalClient::MalClient(QObject *parent) : QObject(parent)
{
    m_manager.setTransferTimeout(TIMEOUT_MS);
    connect(&m_server4, &QTcpServer::newConnection, this, [this] { onLoginConnection(&m_server4); });
    connect(&m_server6, &QTcpServer::newConnection, this, [this] { onLoginConnection(&m_server6); });
    loadLogin();
    m_pending = readJson("mal_pending.json").array();
}

/* Options */

bool MalClient::enabled() const
{
    QSettings settings;
    settings.beginGroup(GROUP);
    return settings.value("enabled", true).toBool();
}

void MalClient::setEnabled(bool value)
{
    QSettings settings;
    settings.beginGroup(GROUP);
    settings.setValue("enabled", value);
    emit optionsChanged();
}

QString MalClient::clientId() const
{
    QFile file(configFile("mal_client_id.txt"));
    if (!file.open(QIODevice::ReadOnly))
    {
        return {};
    }
    return QString::fromUtf8(file.readAll()).trimmed();
}

void MalClient::setClientId(const QString &value)
{
    if (value.trimmed() == clientId())
    {
        return;
    }
    QSaveFile file(configFile("mal_client_id.txt"));
    if (file.open(QIODevice::WriteOnly))
    {
        file.write(value.trimmed().toUtf8());
        file.commit();
    }
    emit optionsChanged();
}

bool MalClient::loggedIn() const
{
    return !m_refreshToken.isEmpty();
}

QString MalClient::userName() const
{
    return m_userName;
}

QString MalClient::loginStatus() const
{
    return m_loginStatus;
}

bool MalClient::busy() const
{
    return m_busy;
}

int MalClient::pendingCount() const
{
    return m_pending.size();
}

QString MalClient::redirectUri() const
{
    return QStringLiteral("http://localhost:%1/mal").arg(PORT);
}

void MalClient::setBusy(bool busy)
{
    if (m_busy != busy)
    {
        m_busy = busy;
        emit busyChanged();
    }
}

void MalClient::setLoginStatus(const QString &status)
{
    m_loginStatus = status;
    emit loginChanged();
}

void MalClient::openUrl(const QString &url) const
{
    QDesktopServices::openUrl(QUrl(url));
}

/* Login */

void MalClient::loadLogin()
{
    const QJsonObject obj = readJson("mal_login.json").object();
    m_accessToken = obj.value("access_token").toString();
    m_refreshToken = obj.value("refresh_token").toString();
    m_expiresAt = static_cast<qint64>(obj.value("expires_at").toDouble());
    m_userName = obj.value("user").toString();
}

void MalClient::saveLogin()
{
    QJsonObject obj;
    obj["access_token"] = m_accessToken;
    obj["refresh_token"] = m_refreshToken;
    obj["expires_at"] = static_cast<double>(m_expiresAt);
    obj["user"] = m_userName;
    writeJson("mal_login.json", QJsonDocument(obj));
}

void MalClient::login()
{
    if (clientId().isEmpty())
    {
        setLoginStatus(tr("Enter your MAL client ID first."));
        return;
    }
    if (!m_server4.isListening() && !m_server6.isListening())
    {
        const bool ok4 = m_server4.listen(QHostAddress::LocalHost, PORT);
        const bool ok6 = m_server6.listen(QHostAddress::LocalHostIPv6, PORT);
        if (!ok4 && !ok6)
        {
            setLoginStatus(tr("Could not listen on port %1: %2")
                .arg(PORT).arg(m_server4.errorString()));
            return;
        }
        QTimer::singleShot(LOGIN_TIMEOUT_MS, this, [this] {
            if (m_server4.isListening() || m_server6.isListening())
            {
                m_server4.close();
                m_server6.close();
                setLoginStatus(tr("Login timed out. Try again."));
            }
        });
    }

    /* MAL only supports the "plain" PKCE method: challenge = verifier */
    m_verifier = randomString(128);
    m_state = randomString(24);

    QUrl url(AUTH_URL);
    QUrlQuery query;
    query.addQueryItem("response_type", "code");
    query.addQueryItem("client_id", clientId());
    query.addQueryItem("code_challenge", m_verifier);
    query.addQueryItem("code_challenge_method", "plain");
    query.addQueryItem("state", m_state);
    query.addQueryItem("redirect_uri", redirectUri());
    url.setQuery(query);
    setLoginStatus(tr("Waiting for the login in your browser…"));
    QDesktopServices::openUrl(url);
}

void MalClient::onLoginConnection(QTcpServer *server)
{
    while (QTcpSocket *socket = server->nextPendingConnection())
    {
        connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
        connect(socket, &QTcpSocket::readyRead, this, [this, socket] {
            if (!socket->canReadLine())
            {
                return;
            }
            /* "GET /mal?code=...&state=... HTTP/1.1" */
            const QList<QByteArray> parts = socket->readLine().trimmed().split(' ');
            const QUrl url(parts.size() >= 2 ? QString::fromUtf8(parts[1]) : QString());
            const QUrlQuery query(url);

            if (url.path() != "/mal")
            {
                socket->write("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                socket->disconnectFromHost();
                return;
            }

            const QString code = query.queryItemValue("code");
            const QString state = query.queryItemValue("state");
            const QString error = query.queryItemValue("error");
            const QByteArray page = code.isEmpty() ?
                QByteArray("<html><body style=\"font-family:sans-serif\"><h2>MyAnimeList login failed</h2><p>You can close this tab and try again in Memento.</p></body></html>") :
                QByteArray("<html><body style=\"font-family:sans-serif\"><h2>Logged in to MyAnimeList</h2><p>You can close this tab and go back to Memento.</p></body></html>");
            socket->write("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: " +
                          QByteArray::number(page.size()) + "\r\n\r\n" + page);
            socket->disconnectFromHost();

            m_server4.close();
            m_server6.close();
            if (code.isEmpty())
            {
                setLoginStatus(tr("Login cancelled or refused (%1).").arg(error.isEmpty() ? tr("no code") : error));
                return;
            }
            finishLogin(code, state);
        });
    }
}

void MalClient::finishLogin(const QString &code, const QString &state)
{
    if (state != m_state)
    {
        setLoginStatus(tr("Login failed: the answer did not match this login. Try again."));
        return;
    }
    setLoginStatus(tr("Finishing login…"));
    requestToken({
        {"client_id", clientId()},
        {"grant_type", "authorization_code"},
        {"code", code},
        {"redirect_uri", redirectUri()},
        {"code_verifier", m_verifier},
    }, [this](bool ok, const QString &error) {
        if (!ok)
        {
            setLoginStatus(tr("Login failed: %1").arg(error));
            return;
        }
        setLoginStatus(QString());
        fetchUser();
        fetchList();
    });
}

void MalClient::requestToken(
    const QList<QPair<QString, QString>> &form,
    std::function<void(bool, const QString &)> done)
{
    QNetworkRequest request{QUrl(TOKEN_URL)};
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");
    QNetworkReply *reply = m_manager.post(request, formEncode(form));
    connect(reply, &QNetworkReply::finished, this, [this, reply, done] {
        reply->deleteLater();
        const QByteArray body = reply->readAll();
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QJsonObject obj = QJsonDocument::fromJson(body).object();
        if (status != 200 || !obj.contains("access_token"))
        {
            done(false, errorText(status, body, reply->errorString()));
            return;
        }
        m_accessToken = obj.value("access_token").toString();
        m_refreshToken = obj.value("refresh_token").toString(m_refreshToken);
        m_expiresAt = nowSecs() + obj.value("expires_in").toInt(3600);
        saveLogin();
        emit loginChanged();
        done(true, QString());
    });
}

void MalClient::ensureToken(std::function<void(bool, const QString &)> done)
{
    if (m_refreshToken.isEmpty())
    {
        done(false, tr("Not logged in to MyAnimeList (Options > Behavior)."));
        return;
    }
    if (!m_accessToken.isEmpty() && m_expiresAt - 300 > nowSecs())
    {
        done(true, QString());
        return;
    }
    requestToken({
        {"client_id", clientId()},
        {"grant_type", "refresh_token"},
        {"refresh_token", m_refreshToken},
    }, [this, done](bool ok, const QString &error) {
        if (!ok)
        {
            done(false, tr("MAL login expired, log in again (Options > Behavior): %1").arg(error));
            return;
        }
        done(true, QString());
    });
}

void MalClient::logout()
{
    m_accessToken.clear();
    m_refreshToken.clear();
    m_expiresAt = 0;
    m_userName.clear();
    QFile::remove(configFile("mal_login.json"));
    setLoginStatus(QString());
}

/* API */

QString MalClient::errorText(int status, const QByteArray &body, const QString &fallback)
{
    const QJsonObject obj = QJsonDocument::fromJson(body).object();
    QString message = obj.value("message").toString();
    if (message.isEmpty())
    {
        message = obj.value("error").toString();
    }
    if (message.isEmpty())
    {
        message = fallback;
    }
    return status > 0 ? QStringLiteral("HTTP %1: %2").arg(status).arg(message) : message;
}

void MalClient::api(const QByteArray &verb, const QUrl &url, const QByteArray &form, Callback callback, bool retried)
{
    ensureToken([=, this](bool ok, const QString &error) {
        if (!ok)
        {
            callback(false, 0, {}, error);
            return;
        }
        QNetworkRequest request(url);
        request.setRawHeader("Authorization", "Bearer " + m_accessToken.toUtf8());
        if (!form.isEmpty())
        {
            request.setHeader(QNetworkRequest::ContentTypeHeader, "application/x-www-form-urlencoded");
        }
        QNetworkReply *reply = m_manager.sendCustomRequest(request, verb, form);
        connect(reply, &QNetworkReply::finished, this, [=, this] {
            reply->deleteLater();
            const QByteArray body = reply->readAll();
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            if (status == 401 && !retried)
            {
                /* Token revoked or expired early: refresh once */
                m_accessToken.clear();
                api(verb, url, form, callback, true);
                return;
            }
            if (status < 200 || status >= 300)
            {
                callback(false, status, body, errorText(status, body, reply->errorString()));
                return;
            }
            callback(true, status, body, QString());
        });
    });
}

void MalClient::fetchUser()
{
    api("GET", QUrl(QString(API) + "/users/@me"), {}, [this](bool ok, int, const QByteArray &body, const QString &) {
        if (!ok)
        {
            return;
        }
        m_userName = QJsonDocument::fromJson(body).object().value("name").toString();
        saveLogin();
        emit loginChanged();
    });
}

QVariantMap MalClient::entryFromNode(const QJsonObject &node, const QJsonObject &status)
{
    const QJsonObject alt = node.value("alternative_titles").toObject();
    QVariantList synonyms;
    for (const auto &s : alt.value("synonyms").toArray())
    {
        synonyms << s.toString();
    }
    return QVariantMap{
        {"id", node.value("id").toInt()},
        {"title", node.value("title").toString()},
        {"en", alt.value("en").toString()},
        {"ja", alt.value("ja").toString()},
        {"synonyms", synonyms},
        {"episodes", node.value("num_episodes").toInt()},
        {"mediaType", node.value("media_type").toString()},
        {"status", status.value("status").toString()},
        {"watched", status.value("num_episodes_watched").toInt()},
        {"startDate", status.value("start_date").toString()},
        {"finishDate", status.value("finish_date").toString()},
        {"onList", !status.isEmpty()},
    };
}

void MalClient::fetchList()
{
    QUrl url(QString(API) + "/users/@me/animelist");
    QUrlQuery query;
    query.addQueryItem("fields", LIST_FIELDS);
    query.addQueryItem("limit", "1000");
    query.addQueryItem("nsfw", "true");
    url.setQuery(query);
    fetchListPage(url, {}, false);
}

void MalClient::fetchMangaList()
{
    QUrl url(QString(API) + "/users/@me/mangalist");
    QUrlQuery query;
    query.addQueryItem("fields", MANGA_FIELDS);
    query.addQueryItem("limit", "1000");
    query.addQueryItem("nsfw", "true");
    url.setQuery(query);
    fetchListPage(url, {}, true);
}

QVariantList MalClient::cachedMangaList() const
{
    return readJson("mal_manga_cache.json").array().toVariantList();
}

QVariantMap MalClient::mangaFromNode(const QJsonObject &node, const QJsonObject &status)
{
    const QJsonObject alt = node.value("alternative_titles").toObject();
    return QVariantMap{
        {"id", node.value("id").toInt()},
        {"title", node.value("title").toString()},
        {"en", alt.value("en").toString()},
        {"ja", alt.value("ja").toString()},
        {"chapters", node.value("num_chapters").toInt()},
        {"volumes", node.value("num_volumes").toInt()},
        {"mediaType", node.value("media_type").toString()},
        {"status", status.value("status").toString()},
        {"chaptersRead", status.value("num_chapters_read").toInt()},
        {"volumesRead", status.value("num_volumes_read").toInt()},
        {"startDate", status.value("start_date").toString()},
        {"finishDate", status.value("finish_date").toString()},
        {"onList", !status.isEmpty()},
    };
}

void MalClient::fetchListPage(const QUrl &url, QVariantList entries, bool manga)
{
    api("GET", url, {}, [this, entries, manga](bool ok, int, const QByteArray &body, const QString &error) mutable {
        if (!ok)
        {
            if (manga)
            {
                emit mangaListReady(false, cachedMangaList(), error);
            }
            else
            {
                emit listReady(false, cachedList(), error);
            }
            return;
        }
        const QJsonObject obj = QJsonDocument::fromJson(body).object();
        for (const auto &item : obj.value("data").toArray())
        {
            const QJsonObject o = item.toObject();
            const QJsonObject node = o.value("node").toObject();
            const QJsonObject status = o.value("list_status").toObject();
            entries << (manga ? mangaFromNode(node, status) : entryFromNode(node, status));
        }
        const QString next = obj.value("paging").toObject().value("next").toString();
        if (!next.isEmpty())
        {
            fetchListPage(QUrl(next), entries, manga);
            return;
        }
        writeJson(manga ? "mal_manga_cache.json" : "mal_list_cache.json",
                  QJsonDocument(QJsonArray::fromVariantList(entries)));
        if (manga)
        {
            emit mangaListReady(true, entries, QString());
        }
        else
        {
            emit listReady(true, entries, QString());
        }
    });
}

QVariantList MalClient::cachedList() const
{
    return readJson("mal_list_cache.json").array().toVariantList();
}

void MalClient::search(const QString &query)
{
    const QString q = query.trimmed().left(64);
    if (q.size() < 3)
    {
        emit searchReady(false, {}, tr("Type at least 3 letters."));
        return;
    }
    QUrl url(QString(API) + "/anime");
    QUrlQuery params;
    params.addQueryItem("q", q);
    params.addQueryItem("limit", "15");
    params.addQueryItem("fields", "num_episodes,alternative_titles,media_type,"
                                  "my_list_status{status,num_episodes_watched,start_date,finish_date}");
    params.addQueryItem("nsfw", "true");
    url.setQuery(params);
    api("GET", url, {}, [this](bool ok, int, const QByteArray &body, const QString &error) {
        if (!ok)
        {
            emit searchReady(false, {}, error);
            return;
        }
        QVariantList results;
        for (const auto &item : QJsonDocument::fromJson(body).object().value("data").toArray())
        {
            const QJsonObject node = item.toObject().value("node").toObject();
            results << entryFromNode(node, node.value("my_list_status").toObject());
        }
        emit searchReady(true, results, QString());
    });
}

/* Updates */

void MalClient::updateEntry(int animeId, const QString &title, const QVariantMap &fields)
{
    queueUpdate(animeId, title, fields, false);
}

void MalClient::updateMangaEntry(int mangaId, const QString &title, const QVariantMap &fields)
{
    queueUpdate(mangaId, title, fields, true);
}

void MalClient::queueUpdate(int id, const QString &title, const QVariantMap &fields, bool manga)
{
    const QString kind = manga ? "manga" : "anime";
    /* A newer update of the same entry replaces a waiting one */
    for (int i = m_pending.size() - 1; i >= 0; --i)
    {
        const QJsonObject o = m_pending[i].toObject();
        if (o.value("id").toInt() == id && o.value("kind").toString("anime") == kind)
        {
            m_pending.removeAt(i);
        }
    }
    QJsonObject entry;
    entry["id"] = id;
    entry["kind"] = kind;
    entry["title"] = title;
    entry["fields"] = QJsonObject::fromVariantMap(fields);
    m_pending.append(entry);
    savePending();
    if (!m_busy)
    {
        sendNext();
    }
}

void MalClient::retryPending()
{
    if (!m_busy)
    {
        sendNext();
    }
}

void MalClient::savePending()
{
    writeJson("mal_pending.json", QJsonDocument(m_pending));
    emit pendingChanged();
}

void MalClient::sendNext()
{
    if (m_pending.isEmpty())
    {
        setBusy(false);
        emit updateFinished(true, QString());
        return;
    }
    setBusy(true);
    const QJsonObject entry = m_pending.first().toObject();
    const int id = entry.value("id").toInt();
    const QString title = entry.value("title").toString();
    QList<QPair<QString, QString>> form;
    const QJsonObject fields = entry.value("fields").toObject();
    for (const QString &key : fields.keys())
    {
        const QJsonValue value = fields.value(key);
        form << qMakePair(key, value.isDouble() ?
            QString::number(static_cast<qint64>(value.toDouble())) : value.toString());
    }
    const bool manga = entry.value("kind").toString("anime") == "manga";
    const QUrl url(QStringLiteral("%1/%2/%3/my_list_status")
                       .arg(QString(API), manga ? QStringLiteral("manga") : QStringLiteral("anime"))
                       .arg(id));
    api("PATCH", url, formEncode(form), [this, id, title, manga](bool ok, int, const QByteArray &body, const QString &error) {
        if (!ok)
        {
            setBusy(false);
            emit updateFinished(false, tr("%1: %2").arg(title, error));
            return;
        }
        if (!m_pending.isEmpty())
        {
            m_pending.removeFirst();
        }
        savePending();
        if (manga)
        {
            updateMangaCache(id, title, QJsonDocument::fromJson(body).object());
            emit mangaEntryUpdated(id);
        }
        else
        {
            updateCache(id, title, QJsonDocument::fromJson(body).object());
            emit entryUpdated(id);
        }
        sendNext();
    });
}

void MalClient::updateCache(int animeId, const QString &title, const QJsonObject &status)
{
    QJsonArray list = readJson("mal_list_cache.json").array();
    bool found = false;
    for (int i = 0; i < list.size(); ++i)
    {
        QJsonObject o = list[i].toObject();
        if (o.value("id").toInt() != animeId)
        {
            continue;
        }
        o["status"] = status.value("status").toString();
        o["watched"] = status.value("num_episodes_watched").toInt();
        o["startDate"] = status.value("start_date").toString();
        o["finishDate"] = status.value("finish_date").toString();
        o["onList"] = true;
        list[i] = o;
        found = true;
    }
    if (!found)
    {
        QJsonObject node;
        node["id"] = animeId;
        node["title"] = title;
        list.append(QJsonObject::fromVariantMap(entryFromNode(node, status)));
    }
    writeJson("mal_list_cache.json", QJsonDocument(list));
}

void MalClient::updateMangaCache(int mangaId, const QString &title, const QJsonObject &status)
{
    QJsonArray list = readJson("mal_manga_cache.json").array();
    bool found = false;
    for (int i = 0; i < list.size(); ++i)
    {
        QJsonObject o = list[i].toObject();
        if (o.value("id").toInt() != mangaId)
        {
            continue;
        }
        o["status"] = status.value("status").toString();
        o["chaptersRead"] = status.value("num_chapters_read").toInt();
        o["volumesRead"] = status.value("num_volumes_read").toInt();
        o["startDate"] = status.value("start_date").toString();
        o["finishDate"] = status.value("finish_date").toString();
        o["onList"] = true;
        list[i] = o;
        found = true;
    }
    if (!found)
    {
        QJsonObject node;
        node["id"] = mangaId;
        node["title"] = title;
        list.append(QJsonObject::fromVariantMap(mangaFromNode(node, status)));
    }
    writeJson("mal_manga_cache.json", QJsonDocument(list));
}

/* Matches */

QVariantMap MalClient::matches() const
{
    return readJson("mal_matches.json").object().toVariantMap();
}

void MalClient::setMatch(const QString &key, const QVariantMap &match)
{
    QJsonObject obj = readJson("mal_matches.json").object();
    obj[key] = QJsonObject::fromVariantMap(match);
    writeJson("mal_matches.json", QJsonDocument(obj));
}

void MalClient::removeMatch(const QString &key)
{
    QJsonObject obj = readJson("mal_matches.json").object();
    obj.remove(key);
    writeJson("mal_matches.json", QJsonDocument(obj));
}

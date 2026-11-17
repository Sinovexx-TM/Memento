#include "togglclient.h"

#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSettings>
#include <QUrl>

#include "util/directoryutils.h"

namespace
{
constexpr const char *GROUP = "toggl";
constexpr const char *API = "https://api.track.toggl.com/api/v9";
constexpr int TIMEOUT_MS = 20000;

QString configFile(const QString &name)
{
    return QDir(DirectoryUtils::getConfigDir()).filePath(name);
}

QVariant readOption(const char *key, const QVariant &fallback)
{
    QSettings settings;
    settings.beginGroup(GROUP);
    return settings.value(key, fallback);
}

void writeOption(const char *key, const QVariant &value)
{
    QSettings settings;
    settings.beginGroup(GROUP);
    settings.setValue(key, value);
}
}

TogglClient::TogglClient(QObject *parent) : QObject(parent)
{
    m_manager.setTransferTimeout(TIMEOUT_MS);
}

bool TogglClient::enabled() const
{
    return readOption("enabled", true).toBool();
}

void TogglClient::setEnabled(bool value)
{
    writeOption("enabled", value);
    emit optionsChanged();
}

double TogglClient::endFallbackPercent() const
{
    return readOption("end-fallback-percent", 90.0).toDouble();
}

void TogglClient::setEndFallbackPercent(double value)
{
    writeOption("end-fallback-percent", value);
    emit optionsChanged();
}

double TogglClient::lateAskPercent() const
{
    return readOption("late-ask-percent", 80.0).toDouble();
}

void TogglClient::setLateAskPercent(double value)
{
    writeOption("late-ask-percent", value);
    emit optionsChanged();
}

bool TogglClient::usePlayedTime() const
{
    return readOption("use-played-time", false).toBool();
}

void TogglClient::setUsePlayedTime(bool value)
{
    writeOption("use-played-time", value);
    emit optionsChanged();
}

QString TogglClient::description() const
{
    return readOption("description", QStringLiteral("AJATT - Anime")).toString();
}

void TogglClient::setDescription(const QString &value)
{
    writeOption("description", value);
    emit optionsChanged();
}

QString TogglClient::project() const
{
    return readOption("project", QStringLiteral("Anime")).toString();
}

void TogglClient::setProject(const QString &value)
{
    writeOption("project", value);
    emit optionsChanged();
}

QString TogglClient::tokenPath() const
{
    return QDir::toNativeSeparators(configFile("toggl_token.txt"));
}

QString TogglClient::token() const
{
    QFile file(configFile("toggl_token.txt"));
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
    {
        return {};
    }
    return QString::fromUtf8(file.readAll()).trimmed();
}

bool TogglClient::hasToken() const
{
    return !token().isEmpty();
}

int TogglClient::pendingCount() const
{
    return loadPending().size();
}

bool TogglClient::busy() const
{
    return m_busy;
}

QJsonArray TogglClient::loadPending() const
{
    QFile file(configFile("toggl_pending.json"));
    if (!file.open(QIODevice::ReadOnly))
    {
        return {};
    }
    return QJsonDocument::fromJson(file.readAll()).array();
}

void TogglClient::savePending(const QJsonArray &entries)
{
    const QString path = configFile("toggl_pending.json");
    if (entries.isEmpty())
    {
        QFile::remove(path);
    }
    else
    {
        QFile file(path);
        if (file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        {
            file.write(QJsonDocument(entries).toJson());
        }
    }
    emit pendingChanged();
}

void TogglClient::logEntry(int durationSeconds)
{
    if (durationSeconds <= 0)
    {
        return;
    }

    const QDateTime start = QDateTime::currentDateTimeUtc().addSecs(-durationSeconds);
    QJsonObject entry{
        {"start", start.toString(Qt::ISODate)},
        {"duration", durationSeconds},
        {"description", description()},
        {"project", project()},
    };

    /* Saved before sending, so a crash or a failed call never loses it */
    QJsonArray entries = loadPending();
    entries.append(entry);
    savePending(entries);

    retryPending();
}

void TogglClient::retryPending()
{
    if (m_busy)
    {
        return;
    }
    if (loadPending().isEmpty())
    {
        emit finished(true, {});
        return;
    }
    if (token().isEmpty())
    {
        emit finished(false, tr("No Toggl token. Put your API token in %1").arg(tokenPath()));
        return;
    }

    m_busy = true;
    emit busyChanged();
    sendNext();
}

void TogglClient::discardPending()
{
    savePending({});
}

void TogglClient::fail(const QString &error)
{
    m_busy = false;
    emit busyChanged();
    emit finished(false, error);
}

void TogglClient::request(
    const QByteArray &verb, const QString &path, const QByteArray &body, Callback callback)
{
    QNetworkRequest req(QUrl(QString::fromLatin1(API) + path));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader(
        "Authorization",
        "Basic " + (token() + ":api_token").toUtf8().toBase64()
    );

    QNetworkReply *reply = m_manager.sendCustomRequest(req, verb, body);
    connect(reply, &QNetworkReply::finished, this, [reply, callback] {
        reply->deleteLater();
        const int status =
            reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray data = reply->readAll();
        if (reply->error() != QNetworkReply::NoError || status < 200 || status >= 300)
        {
            QString error;
            if (status == 401 || status == 403)
            {
                error = tr("Toggl refused the token (HTTP %1).").arg(status);
            }
            else if (status > 0)
            {
                error = tr("Toggl error (HTTP %1): %2")
                    .arg(status)
                    .arg(QString::fromUtf8(data.left(200)).trimmed());
            }
            else
            {
                error = tr("Could not reach Toggl: %1").arg(reply->errorString());
            }
            callback(false, data, error);
            return;
        }
        callback(true, data, {});
    });
}

void TogglClient::sendNext()
{
    const QJsonArray entries = loadPending();
    if (entries.isEmpty())
    {
        m_busy = false;
        emit busyChanged();
        emit finished(true, {});
        return;
    }

    if (m_workspaceId == 0)
    {
        request("GET", "/me", {}, [this] (bool ok, const QByteArray &body, const QString &error) {
            if (!ok)
            {
                fail(error);
                return;
            }
            m_workspaceId = QJsonDocument::fromJson(body).object()
                .value("default_workspace_id").toInteger();
            if (m_workspaceId == 0)
            {
                fail(tr("Toggl did not return a workspace."));
                return;
            }
            sendNext();
        });
        return;
    }

    const QJsonObject entry = entries.first().toObject();
    const QString projectName = entry.value("project").toString().trimmed();

    if (!projectName.isEmpty() &&
        (m_projectId == 0 || m_projectIdName.compare(projectName, Qt::CaseInsensitive) != 0))
    {
        const QString path = QString("/workspaces/%1/projects?active=true&per_page=200")
            .arg(m_workspaceId);
        request("GET", path, {}, [this, projectName] (bool ok, const QByteArray &body, const QString &error) {
            if (!ok)
            {
                fail(error);
                return;
            }
            const QJsonArray projects = QJsonDocument::fromJson(body).array();
            for (const QJsonValue &value : projects)
            {
                const QJsonObject item = value.toObject();
                if (item.value("name").toString()
                        .compare(projectName, Qt::CaseInsensitive) == 0)
                {
                    m_projectId = item.value("id").toInteger();
                    m_projectIdName = projectName;
                    sendNext();
                    return;
                }
            }
            fail(tr("No Toggl project named \"%1\".").arg(projectName));
        });
        return;
    }

    QJsonObject body{
        {"created_with", "Memento"},
        {"description", entry.value("description").toString()},
        {"start", entry.value("start").toString()},
        {"duration", entry.value("duration").toInt()},
        {"workspace_id", m_workspaceId},
    };
    if (!projectName.isEmpty())
    {
        body.insert("project_id", m_projectId);
    }

    const QString path = QString("/workspaces/%1/time_entries").arg(m_workspaceId);
    request("POST", path, QJsonDocument(body).toJson(QJsonDocument::Compact),
            [this] (bool ok, const QByteArray &, const QString &error) {
        if (!ok)
        {
            fail(error);
            return;
        }
        QJsonArray remaining = loadPending();
        if (!remaining.isEmpty())
        {
            remaining.removeFirst();
        }
        savePending(remaining);
        sendNext();
    });
}

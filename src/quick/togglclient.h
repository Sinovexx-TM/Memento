#ifndef TOGGLCLIENT_H
#define TOGGLCLIENT_H

#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QVariantList>

#include <functional>

/**
 * @brief Logs finished episodes to Toggl Track (API v9).
 *
 * Self-contained: its options live in the QSettings group "toggl", the API
 * token is read from toggl_token.txt in Memento's config folder (never part
 * of the repository), and entries that could not be sent are kept in
 * toggl_pending.json in the same folder until a retry succeeds.
 */
class TogglClient : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY optionsChanged)
    Q_PROPERTY(double endFallbackPercent READ endFallbackPercent WRITE setEndFallbackPercent NOTIFY optionsChanged)
    Q_PROPERTY(double lateAskPercent READ lateAskPercent WRITE setLateAskPercent NOTIFY optionsChanged)
    Q_PROPERTY(bool usePlayedTime READ usePlayedTime WRITE setUsePlayedTime NOTIFY optionsChanged)
    Q_PROPERTY(QString description READ description WRITE setDescription NOTIFY optionsChanged)
    Q_PROPERTY(QString project READ project WRITE setProject NOTIFY optionsChanged)
    Q_PROPERTY(QString tags READ tags WRITE setTags NOTIFY optionsChanged)
    Q_PROPERTY(double workspaceId READ workspaceId WRITE setWorkspaceId NOTIFY optionsChanged)
    Q_PROPERTY(QString tokenPath READ tokenPath CONSTANT)
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY pendingChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit TogglClient(QObject *parent = nullptr);

    bool enabled() const;
    void setEnabled(bool value);
    double endFallbackPercent() const;
    void setEndFallbackPercent(double value);
    double lateAskPercent() const;
    void setLateAskPercent(double value);
    bool usePlayedTime() const;
    void setUsePlayedTime(bool value);
    QString description() const;
    void setDescription(const QString &value);
    QString project() const;
    void setProject(const QString &value);
    QString tags() const;
    void setTags(const QString &value);
    double workspaceId() const;
    void setWorkspaceId(double value);

    QString tokenPath() const;
    int pendingCount() const;
    bool busy() const;

    /**
     * @brief true when the token file exists and is not empty.
     */
    Q_INVOKABLE bool hasToken() const;

    /**
     * @brief Saves the API token to toggl_token.txt (empty removes it).
     */
    Q_INVOKABLE void setToken(const QString &token);

    /**
     * @brief Fetches the user's workspaces. Emits workspacesLoaded.
     */
    Q_INVOKABLE void loadWorkspaces();

    /**
     * @brief Fetches the active projects of the chosen workspace (or the
     * default one). Emits projectsLoaded.
     */
    Q_INVOKABLE void loadProjects();

    /**
     * @brief The description for an episode: the template with {show} and
     * {episode} filled in.
     */
    Q_INVOKABLE QString describe(const QString &show, const QString &episode) const;

    /**
     * @brief Queue a finished time entry ending now and send all queued
     * entries. Emits finished() when done.
     * @param durationSeconds Length of the entry.
     * @param show Show name for {show}.
     * @param episode Episode number or label for {episode}.
     */
    Q_INVOKABLE void logEntry(int durationSeconds, const QString &show, const QString &episode);

    /**
     * @brief Queue an entry with its own description and project (manga
     * reading) ending at endMs (0 = now), and send all queued entries.
     */
    Q_INVOKABLE void logCustom(int durationSeconds, const QString &description,
                               const QString &project, double endMs);

    /**
     * @brief Send all queued entries again. Emits finished() when done.
     */
    Q_INVOKABLE void retryPending();

    /**
     * @brief Drop all queued entries.
     */
    Q_INVOKABLE void discardPending();

signals:
    void optionsChanged();
    void pendingChanged();
    void busyChanged();

    /**
     * @param success true when every queued entry was sent.
     * @param error Short human readable error when success is false.
     */
    void finished(bool success, const QString &error);

    /* [{ id, name }] */
    void workspacesLoaded(bool success, const QVariantList &workspaces, const QString &error);
    void projectsLoaded(bool success, const QVariantList &projects, const QString &error);

private:
    using Callback = std::function<void(bool ok, const QByteArray &body, const QString &error)>;

    QString token() const;
    QJsonArray loadPending() const;
    void savePending(const QJsonArray &entries);
    void request(const QByteArray &verb, const QString &path, const QByteArray &body, Callback callback);
    void sendNext();
    void withWorkspace(std::function<void(bool ok, const QString &error)> done);
    void fail(const QString &error);

    QNetworkAccessManager m_manager;
    bool m_busy{false};
    qint64 m_workspaceId{0};
    qint64 m_projectId{0};
    QString m_projectIdName;
};

#endif // TOGGLCLIENT_H

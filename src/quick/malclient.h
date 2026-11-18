#ifndef MALCLIENT_H
#define MALCLIENT_H

#include <QByteArray>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>
#include <QTcpServer>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>
#include <QSet>

#include <functional>

/**
 * @brief MyAnimeList (official API v2): OAuth2 login with PKCE, the user's
 * list, search and list updates with a retry queue.
 *
 * Files in the config folder (outside the repository):
 * - mal_client_id.txt   the user's own client ID
 * - mal_login.json      access/refresh token
 * - mal_matches.json    show name|season -> { id, title, offset, episodes }
 * - mal_list_cache.json last fetched list (for matching without waiting)
 * - mal_manga_cache.json last fetched manga list
 * - mal_covers\          small cover pictures of list entries
 * - mal_pending.json    updates that failed, sent again later (anime and manga)
 */
class MalClient : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY optionsChanged)
    Q_PROPERTY(QString clientId READ clientId WRITE setClientId NOTIFY optionsChanged)
    Q_PROPERTY(bool loggedIn READ loggedIn NOTIFY loginChanged)
    Q_PROPERTY(QString userName READ userName NOTIFY loginChanged)
    Q_PROPERTY(QString loginStatus READ loginStatus NOTIFY loginChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY pendingChanged)
    Q_PROPERTY(QString redirectUri READ redirectUri CONSTANT)

public:
    explicit MalClient(QObject *parent = nullptr);

    bool enabled() const;
    void setEnabled(bool value);
    QString clientId() const;
    void setClientId(const QString &value);
    bool loggedIn() const;
    QString userName() const;
    QString loginStatus() const;
    bool busy() const;
    int pendingCount() const;
    QString redirectUri() const;

    /**
     * @brief Opens MAL's login page in the browser and waits for the
     * redirect on localhost.
     */
    Q_INVOKABLE void login();
    Q_INVOKABLE void logout();

    /**
     * @brief Fetches the whole list. Emits listReady.
     */
    Q_INVOKABLE void fetchList();

    /**
     * @brief The last fetched list (may be empty).
     * @return [{ id, title, en, ja, synonyms, episodes, status, watched,
     * startDate, finishDate }]
     */
    Q_INVOKABLE QVariantList cachedList() const;

    /**
     * @brief Searches MAL. Emits searchReady.
     */
    Q_INVOKABLE void search(const QString &query);

    /**
     * @brief Queues an update of a list entry and sends the queue.
     * @param fields status, num_watched_episodes, start_date, finish_date
     */
    Q_INVOKABLE void updateEntry(int animeId, const QString &title, const QVariantMap &fields);
    Q_INVOKABLE void retryPending();

    /**
     * @brief The manga list: fetch (emits mangaListReady), last fetched copy,
     * and updates (fields: status, num_chapters_read, num_volumes_read,
     * start_date, finish_date). Same login and retry queue as the anime list.
     * Entries: { id, title, en, ja, chapters, volumes, status, chaptersRead,
     * volumesRead, startDate, finishDate, onList }
     */
    Q_INVOKABLE void fetchMangaList();
    Q_INVOKABLE QVariantList cachedMangaList() const;
    Q_INVOKABLE void updateMangaEntry(int mangaId, const QString &title, const QVariantMap &fields);

    Q_INVOKABLE QVariantMap matches() const;
    Q_INVOKABLE void setMatch(const QString &key, const QVariantMap &match);
    Q_INVOKABLE void removeMatch(const QString &key);

    /**
     * @brief Cover picture of a list entry, kept in mal_covers.
     * @param kind "anime" or "manga"
     * @param url  the entry's picture (MAL's CDN only)
     * @return the local file URL, or "" while it downloads (coverReady
     * follows) or when there is none.
     */
    Q_INVOKABLE QString cover(const QString &kind, int id, const QString &url);

    /**
     * @brief Opens a URL in the browser.
     */
    Q_INVOKABLE void openUrl(const QString &url) const;

signals:
    void optionsChanged();
    void loginChanged();
    void busyChanged();
    void pendingChanged();
    void listReady(bool success, const QVariantList &entries, const QString &error);
    void searchReady(bool success, const QVariantList &results, const QString &error);
    void updateFinished(bool success, const QString &error);
    void entryUpdated(int animeId);
    void mangaListReady(bool success, const QVariantList &entries, const QString &error);
    void mangaEntryUpdated(int mangaId);
    void coverReady(const QString &kind, int id, const QString &fileUrl);

private:
    using Callback = std::function<void(bool ok, int status, const QByteArray &body, const QString &error)>;

    void loadLogin();
    void saveLogin();
    void setLoginStatus(const QString &status);
    void onLoginConnection(QTcpServer *server);
    void finishLogin(const QString &code, const QString &state);
    void requestToken(const QList<QPair<QString, QString>> &form, std::function<void(bool, const QString &)> done);
    void ensureToken(std::function<void(bool, const QString &)> done);
    void api(const QByteArray &verb, const QUrl &url, const QByteArray &form, Callback callback, bool retried = false);
    void fetchUser();
    void fetchListPage(const QUrl &url, QVariantList entries, bool manga);
    void queueUpdate(int id, const QString &title, const QVariantMap &fields, bool manga);
    void sendNext();
    void savePending();
    void setBusy(bool busy);
    void updateCache(int animeId, const QString &title, const QJsonObject &status);
    void updateMangaCache(int mangaId, const QString &title, const QJsonObject &status);
    static QVariantMap entryFromNode(const QJsonObject &node, const QJsonObject &status);
    static QVariantMap mangaFromNode(const QJsonObject &node, const QJsonObject &status);
    static QString errorText(int status, const QByteArray &body, const QString &fallback);
    void downloadNextCover();

    struct CoverJob
    {
        QString kind;
        int id;
        QString url;
        int tries{0};
    };
    QList<CoverJob> m_coverQueue;
    QSet<QString> m_coverRequested;
    int m_coverActive{0};

    QNetworkAccessManager m_manager;
    QTcpServer m_server4;
    QTcpServer m_server6;
    QString m_verifier;
    QString m_state;

    QString m_accessToken;
    QString m_refreshToken;
    qint64 m_expiresAt{0};
    QString m_userName;
    QString m_loginStatus;

    QJsonArray m_pending;
    bool m_busy{false};
};

#endif // MALCLIENT_H

#ifndef MANGALIBRARY_H
#define MANGALIBRARY_H

#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QUrl>
#include <QVariantList>
#include <QVariantMap>

/**
 * @brief Manga volumes read with mokuro's OCR output.
 *
 * A volume is a folder of page images; its text comes from the
 * "<folder>.mokuro" file mokuro writes next to it. Reading progress lives in
 * manga_history.json, finished reading sessions in manga_sessions.csv (both
 * in Memento's config folder). Volumes without text can be sent to mokuro,
 * which runs as a separate Python process (python -m mokuro).
 */
class MangaLibrary : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString root READ root WRITE setRoot NOTIFY rootChanged)
    Q_PROPERTY(QString python READ python WRITE setPython NOTIFY pythonChanged)
    Q_PROPERTY(bool running READ running NOTIFY jobChanged)
    Q_PROPERTY(QString jobVolume READ jobVolume NOTIFY jobChanged)
    Q_PROPERTY(QString jobKind READ jobKind NOTIFY jobChanged)
    Q_PROPERTY(int jobDone READ jobDone NOTIFY jobChanged)
    Q_PROPERTY(int jobTotal READ jobTotal NOTIFY jobChanged)
    Q_PROPERTY(QString jobLine READ jobLine NOTIFY jobChanged)
    Q_PROPERTY(QStringList queue READ queue NOTIFY jobChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY jobChanged)
    Q_PROPERTY(QString sessionsPath READ sessionsPath CONSTANT)

public:
    explicit MangaLibrary(QObject *parent = nullptr);
    ~MangaLibrary();

    QString root() const;
    void setRoot(const QString &path);
    QString python() const;
    void setPython(const QString &path);
    bool running() const { return m_process != nullptr; }
    QString jobVolume() const { return m_jobVolume; }
    QString jobKind() const { return m_jobKind; }
    int jobDone() const { return m_jobDone; }
    int jobTotal() const { return m_jobTotal; }
    QString jobLine() const { return m_jobLine; }
    QStringList queue() const { return m_queue; }
    QString lastError() const { return m_lastError; }
    QString sessionsPath() const;

    /**
     * @brief Every volume under the root: [{ path, name, series, seriesPath,
     * mokuro (path or ""), pages, cover (file URL) }], naturally sorted.
     */
    Q_INVOKABLE QVariantList volumes() const;

    /**
     * @brief Pages of a volume: [{ image (file URL), w, h, blocks: [{ box,
     * vertical, fontSize, lines, coords }] }]. Images without OCR data get
     * an empty block list.
     */
    Q_INVOKABLE QVariantList loadVolume(const QString &path) const;

    /* Reading progress: { key: { page, pages, read: [page indices], chars,
     * seconds, lastDate, done } } */
    Q_INVOKABLE QVariantMap history() const;
    Q_INVOKABLE void saveProgress(const QString &path, const QVariantMap &entry);

    /**
     * @brief The reading session in progress, saved on every page turn so
     * closing the app never loses it.
     */
    Q_INVOKABLE void saveOpenSession(const QVariantMap &session);
    Q_INVOKABLE QVariantMap openSession() const;

    /**
     * @brief Ends a session: appends it to manga_sessions.csv and clears the
     * open session. Sessions under a minute are dropped.
     */
    Q_INVOKABLE bool finishSession(const QVariantMap &session);

    /**
     * @brief Runs mokuro on the volumes (queued, one at a time).
     */
    Q_INVOKABLE void runMokuro(const QStringList &paths);
    Q_INVOKABLE void cancelMokuro();

    /**
     * @brief Installs mokuro with pip (python -m pip install mokuro).
     */
    Q_INVOKABLE void installMokuro();

    /**
     * @brief Checks whether the Python finds mokuro. Emits mokuroChecked.
     */
    Q_INVOKABLE void checkMokuro();

    Q_INVOKABLE QString localPath(const QUrl &url) const;

signals:
    void rootChanged();
    void pythonChanged();
    void jobChanged();
    void historyChanged();
    void volumeFinished(const QString &path, bool success, const QString &error);
    void installFinished(bool success, const QString &error);
    void mokuroChecked(bool installed, const QString &detail);

private:
    void startNext();
    void startProcess(const QStringList &args, const QString &kind, const QString &volume);
    void readOutput();
    void processFinished(int exitCode, QProcess::ExitStatus status);

    QProcess *m_process{nullptr};
    QStringList m_queue;
    QString m_jobVolume;
    QString m_jobKind;
    int m_jobDone{0};
    int m_jobTotal{0};
    QString m_jobLine;
    QString m_lastError;
    QString m_tail;
};

#endif // MANGALIBRARY_H

#ifndef YOMITANOVERLAY_H
#define YOMITANOVERLAY_H

#include <QObject>
#include <QProcess>
#include <QString>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

/**
 * @brief Runs the Yomitan overlay (fork): a separate see-through program
 *        (overlay/memento-overlay.exe, Electron + the real Yomitan) laid over
 *        the player. Memento sends it the text it shows with every
 *        character's screen box; Yomitan does the lookups and cards.
 *
 * Talks to the overlay over a local TCP connection, one JSON object per
 * line. When the overlay is missing, fails to start or crashes for good,
 * active is false and Memento's own popup is used.
 */
class YomitanOverlay : public QObject
{
    Q_OBJECT

    /* User setting: use the overlay (default on) */
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

    /* User setting: draw the overlay's text in red to check it lines up */
    Q_PROPERTY(bool showText READ showText WRITE setShowText NOTIFY showTextChanged)

    /* The overlay program is installed next to memento.exe */
    Q_PROPERTY(bool available READ available CONSTANT)

    /* Connected and Yomitan loaded: lookups go through the overlay */
    Q_PROPERTY(bool active READ active NOTIFY activeChanged)

    /* Cursor over the overlay's text / over Yomitan's popup */
    Q_PROPERTY(bool hover READ hover NOTIFY hoverChanged)
    Q_PROPERTY(bool popupHover READ popupHover NOTIFY hoverChanged)

    /* Yomitan's popup is showing */
    Q_PROPERTY(bool popupOpen READ popupOpen NOTIFY popupOpenChanged)

    /* Human-readable state for the settings page */
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)

public:
    explicit YomitanOverlay(QObject *parent = nullptr);
    ~YomitanOverlay() override;

    bool enabled() const { return m_enabled; }
    void setEnabled(bool value);
    bool showText() const { return m_showText; }
    void setShowText(bool value);
    bool available() const;
    bool active() const { return m_active; }
    bool hover() const { return m_hover; }
    bool popupHover() const { return m_popupHover; }
    bool popupOpen() const { return m_popupOpen; }
    QString status() const { return m_status; }

    /**
     * @brief Where the overlay window goes (screen coordinates) and whether
     *        it should be shown now. Only sent when something changed.
     */
    Q_INVOKABLE void setWindow(qreal x, qreal y, qreal w, qreal h, bool visible);

    /**
     * @brief The text to lay out, as blocks of lines with one box per
     *        character: [{vertical, lines: [{text, rects: [[x, y, w, h]]}]}],
     *        boxes relative to the window. Only sent when it changed.
     */
    Q_INVOKABLE void setText(const QVariantList &blocks, const QString &font);

    /** @brief Opens Yomitan's own settings page. */
    Q_INVOKABLE void openSettings();

    /** @brief Closes Yomitan's popup if it is open. */
    Q_INVOKABLE void closePopup();

    /** @brief Starts the overlay again after it gave up. */
    Q_INVOKABLE void restart();

Q_SIGNALS:
    void enabledChanged();
    void showTextChanged();
    void activeChanged();
    void hoverChanged();
    void popupOpenChanged();
    void statusChanged();

    /**
     * @brief Yomitan added a note.
     * @param info time (ms, just before the add), deck, model, fields.
     */
    void noteAdded(const QVariantMap &info);

private:
    void start();
    void stop();
    void send(const QVariantMap &message);
    void onNewConnection();
    void onReadyRead();
    void onProcessFinished();
    void handle(const QVariantMap &message);
    void setActive(bool value);
    void setStatus(const QString &value);
    void resetState();

    bool m_enabled = true;
    bool m_showText = false;
    bool m_active = false;
    bool m_hover = false;
    bool m_popupHover = false;
    bool m_popupOpen = false;
    QString m_status;

    QTcpServer m_server;
    QTcpSocket *m_socket = nullptr;
    QProcess *m_process = nullptr;
    QByteArray m_buffer;
    QTimer m_restartTimer;
    int m_restarts = 0;
    bool m_stopping = false;

    /* Last messages sent, so unchanged ones aren't repeated */
    QByteArray m_lastWindow;
    QByteArray m_lastText;
};

#endif // YOMITANOVERLAY_H

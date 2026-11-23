#include "yomitanoverlay.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>

namespace
{
constexpr const char *SETTINGS_GROUP = "yomitan-overlay";
constexpr int MAX_RESTARTS = 3;

QString overlayExe()
{
    return QDir(QCoreApplication::applicationDirPath())
        .filePath("overlay/memento-overlay.exe");
}
}

YomitanOverlay::YomitanOverlay(QObject *parent) : QObject(parent)
{
    QSettings settings;
    settings.beginGroup(SETTINGS_GROUP);
    m_enabled = settings.value("enabled", true).toBool();
    m_showText = settings.value("show-text", false).toBool();
    settings.endGroup();

    connect(&m_server, &QTcpServer::newConnection,
            this, &YomitanOverlay::onNewConnection);

    m_restartTimer.setSingleShot(true);
    m_restartTimer.setInterval(3000);
    connect(&m_restartTimer, &QTimer::timeout, this, &YomitanOverlay::start);

    if (!available())
    {
        setStatus(tr("Not installed (Memento's own popup is used)"));
    }
    else if (!m_enabled)
    {
        setStatus(tr("Off (Memento's own popup is used)"));
    }
    else
    {
        /* Start once the event loop runs */
        QTimer::singleShot(0, this, &YomitanOverlay::start);
    }
}

YomitanOverlay::~YomitanOverlay()
{
    m_stopping = true;
    stop();
}

bool YomitanOverlay::available() const
{
    return QFileInfo::exists(overlayExe());
}

void YomitanOverlay::setEnabled(bool value)
{
    if (m_enabled == value)
    {
        return;
    }
    m_enabled = value;
    QSettings settings;
    settings.setValue(QString(SETTINGS_GROUP) + "/enabled", value);
    emit enabledChanged();

    if (value)
    {
        m_restarts = 0;
        start();
    }
    else
    {
        stop();
        setStatus(tr("Off (Memento's own popup is used)"));
    }
}

void YomitanOverlay::setShowText(bool value)
{
    if (m_showText == value)
    {
        return;
    }
    m_showText = value;
    QSettings settings;
    settings.setValue(QString(SETTINGS_GROUP) + "/show-text", value);
    emit showTextChanged();
    send({{"type", "debug"}, {"on", value}});
}

void YomitanOverlay::start()
{
    if (!m_enabled || !available() || m_process != nullptr)
    {
        return;
    }
    if (!m_server.isListening() &&
        !m_server.listen(QHostAddress::LocalHost, 0))
    {
        setStatus(tr("Could not open a local port: %1").arg(m_server.errorString()));
        return;
    }

    m_process = new QProcess(this);
    m_process->setProgram(overlayExe());
    m_process->setArguments({QString("--port=%1").arg(m_server.serverPort())});
    m_process->setWorkingDirectory(QFileInfo(overlayExe()).absolutePath());
    m_process->setProcessChannelMode(QProcess::ForwardedChannels);
    connect(m_process, &QProcess::finished,
            this, &YomitanOverlay::onProcessFinished);
    connect(m_process, &QProcess::errorOccurred, this,
        [this] (QProcess::ProcessError error)
        {
            if (error == QProcess::FailedToStart)
            {
                onProcessFinished();
            }
        });
    setStatus(tr("Starting…"));
    m_process->start();
}

void YomitanOverlay::stop()
{
    send({{"type", "quit"}});
    if (m_socket)
    {
        m_socket->flush();
        m_socket->disconnectFromHost();
    }
    if (m_process)
    {
        QProcess *process = m_process;
        m_process = nullptr;
        process->disconnect(this);
        if (!process->waitForFinished(1500))
        {
            process->kill();
            process->waitForFinished(1000);
        }
        process->deleteLater();
    }
    if (m_socket)
    {
        m_socket->deleteLater();
        m_socket = nullptr;
    }
    m_restartTimer.stop();
    resetState();
}

void YomitanOverlay::restart()
{
    stop();
    m_restarts = 0;
    m_enabled = true;
    emit enabledChanged();
    start();
}

void YomitanOverlay::resetState()
{
    m_buffer.clear();
    m_lastWindow.clear();
    m_lastText.clear();
    setActive(false);
    if (m_hover || m_popupHover)
    {
        m_hover = m_popupHover = false;
        emit hoverChanged();
    }
    if (m_popupOpen)
    {
        m_popupOpen = false;
        emit popupOpenChanged();
    }
}

void YomitanOverlay::onProcessFinished()
{
    if (m_process)
    {
        m_process->deleteLater();
        m_process = nullptr;
    }
    if (m_socket)
    {
        m_socket->deleteLater();
        m_socket = nullptr;
    }
    resetState();
    if (m_stopping || !m_enabled)
    {
        return;
    }
    if (++m_restarts <= MAX_RESTARTS)
    {
        setStatus(tr("Stopped, restarting…"));
        m_restartTimer.start();
    }
    else
    {
        setStatus(tr("Keeps stopping (Memento's own popup is used)"));
    }
}

void YomitanOverlay::onNewConnection()
{
    while (QTcpSocket *socket = m_server.nextPendingConnection())
    {
        if (m_socket)
        {
            m_socket->deleteLater();
        }
        m_socket = socket;
        m_buffer.clear();
        m_lastWindow.clear();
        m_lastText.clear();
        connect(socket, &QTcpSocket::readyRead,
                this, &YomitanOverlay::onReadyRead);
        connect(socket, &QTcpSocket::disconnected, this,
            [this, socket] ()
            {
                if (m_socket == socket)
                {
                    m_socket = nullptr;
                    resetState();
                }
                socket->deleteLater();
            });
    }
}

void YomitanOverlay::onReadyRead()
{
    if (!m_socket)
    {
        return;
    }
    m_buffer += m_socket->readAll();
    qsizetype nl;
    while ((nl = m_buffer.indexOf('\n')) >= 0)
    {
        const QByteArray line = m_buffer.left(nl);
        m_buffer.remove(0, nl + 1);
        const QJsonDocument doc = QJsonDocument::fromJson(line);
        if (doc.isObject())
        {
            handle(doc.object().toVariantMap());
        }
    }
}

void YomitanOverlay::handle(const QVariantMap &message)
{
    const QString type = message.value("type").toString();
    if (type == "ready")
    {
        if (message.value("extension").toBool())
        {
            m_restarts = 0;
            setStatus(tr("Running (Yomitan %1)")
                .arg(message.value("version").toString()));
            send({{"type", "debug"}, {"on", m_showText}});
            setActive(true);
        }
        else
        {
            setStatus(tr("Yomitan could not be loaded (Memento's own popup is used)"));
        }
    }
    else if (type == "hover")
    {
        const bool on = message.value("on").toBool();
        const bool popup = message.value("popup").toBool();
        if (on != m_hover || popup != m_popupHover)
        {
            m_hover = on;
            m_popupHover = popup;
            emit hoverChanged();
        }
    }
    else if (type == "popup")
    {
        const bool open = message.value("open").toBool();
        if (open != m_popupOpen)
        {
            m_popupOpen = open;
            emit popupOpenChanged();
        }
    }
    else if (type == "resend")
    {
        /* The page reloaded: send window and text again */
        const QByteArray window = m_lastWindow;
        const QByteArray text = m_lastText;
        m_lastWindow.clear();
        m_lastText.clear();
        if (m_socket && !window.isEmpty())
        {
            m_socket->write(window);
            m_lastWindow = window;
        }
        if (m_socket && !text.isEmpty())
        {
            m_socket->write(text);
            m_lastText = text;
        }
    }
    else if (type == "noteAdded")
    {
        emit noteAdded(message);
    }
    else if (type == "log")
    {
        qWarning("Yomitan overlay: %s", qPrintable(message.value("message").toString()));
    }
}

void YomitanOverlay::send(const QVariantMap &message)
{
    if (!m_socket || m_socket->state() != QAbstractSocket::ConnectedState)
    {
        return;
    }
    QByteArray data = QJsonDocument(QJsonObject::fromVariantMap(message))
        .toJson(QJsonDocument::Compact);
    data += '\n';
    m_socket->write(data);
}

void YomitanOverlay::setWindow(qreal x, qreal y, qreal w, qreal h, bool visible)
{
    if (!m_active)
    {
        return;
    }
    QVariantMap message{
        {"type", "window"},
        {"x", qRound(x)}, {"y", qRound(y)},
        {"w", qRound(w)}, {"h", qRound(h)},
        {"visible", visible},
    };
    QByteArray data = QJsonDocument(QJsonObject::fromVariantMap(message))
        .toJson(QJsonDocument::Compact) + '\n';
    if (data == m_lastWindow)
    {
        return;
    }
    m_lastWindow = data;
    m_socket->write(data);
}

void YomitanOverlay::setText(const QVariantList &blocks, const QString &font)
{
    if (!m_active)
    {
        return;
    }
    QVariantMap message{
        {"type", "text"},
        {"font", font},
        {"blocks", blocks},
    };
    QByteArray data = QJsonDocument(QJsonObject::fromVariantMap(message))
        .toJson(QJsonDocument::Compact) + '\n';
    if (data == m_lastText)
    {
        return;
    }
    m_lastText = data;
    m_socket->write(data);
}

void YomitanOverlay::openSettings()
{
    send({{"type", "openSettings"}});
}

void YomitanOverlay::closePopup()
{
    send({{"type", "closePopup"}});
}

void YomitanOverlay::setActive(bool value)
{
    if (m_active != value)
    {
        m_active = value;
        emit activeChanged();
    }
}

void YomitanOverlay::setStatus(const QString &value)
{
    if (m_status != value)
    {
        m_status = value;
        emit statusChanged();
    }
}

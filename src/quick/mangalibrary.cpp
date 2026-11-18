#include "mangalibrary.h"

#include <QCollator>
#include <QDateTime>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QProcessEnvironment>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QTimeZone>

#include "util/directoryutils.h"

namespace
{
constexpr const char *GROUP = "manga";
const QStringList IMAGE_FILTERS{"*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif", "*.bmp", "*.gif"};
constexpr int MAX_DEPTH = 5;
constexpr int MIN_PAGES = 3;

QString configFile(const QString &name)
{
    return QDir(DirectoryUtils::getConfigDir()).filePath(name);
}

QCollator naturalCollator()
{
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    return collator;
}

QStringList imagesIn(const QString &folder)
{
    QStringList files = QDir(folder).entryList(IMAGE_FILTERS, QDir::Files);
    const QCollator collator = naturalCollator();
    std::sort(files.begin(), files.end(), [&collator] (const QString &a, const QString &b) {
        return collator.compare(a, b) < 0;
    });
    return files;
}

QJsonObject readJson(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
    {
        return {};
    }
    return QJsonDocument::fromJson(file.readAll()).object();
}

bool writeJson(const QString &path, const QJsonObject &obj)
{
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
    {
        return false;
    }
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    return file.commit();
}

QString csvField(QString value)
{
    if (value.contains(',') || value.contains('"') || value.contains('\n'))
    {
        value.replace('"', "\"\"");
        return '"' + value + '"';
    }
    return value;
}

QString isoUtc(qint64 ms)
{
    return QDateTime::fromMSecsSinceEpoch(ms, QTimeZone::UTC).toString(Qt::ISODate);
}
}

MangaLibrary::MangaLibrary(QObject *parent) : QObject(parent) {}

MangaLibrary::~MangaLibrary()
{
    if (m_process)
    {
        m_process->disconnect(this);
        m_process->kill();
        m_process->waitForFinished(2000);
    }
}

QString MangaLibrary::root() const
{
    QSettings settings;
    settings.beginGroup(GROUP);
    const QString root = settings.value("root").toString();
    return root.isEmpty() ? QString() : QDir::cleanPath(root);
}

void MangaLibrary::setRoot(const QString &path)
{
    QSettings settings;
    settings.beginGroup(GROUP);
    settings.setValue("root", path);
    emit rootChanged();
}

QString MangaLibrary::python() const
{
    QSettings settings;
    settings.beginGroup(GROUP);
    return settings.value("python", QStringLiteral("python")).toString();
}

void MangaLibrary::setPython(const QString &path)
{
    QSettings settings;
    settings.beginGroup(GROUP);
    settings.setValue("python", path.trimmed().isEmpty() ? QStringLiteral("python") : path.trimmed());
    emit pythonChanged();
}

QString MangaLibrary::sessionsPath() const
{
    return QDir::toNativeSeparators(configFile("manga_sessions.csv"));
}

QString MangaLibrary::localPath(const QUrl &url) const
{
    return url.isLocalFile() ? url.toLocalFile() : url.toString();
}

QVariantList MangaLibrary::volumes() const
{
    const QString base = root();
    if (base.isEmpty() || !QFileInfo(base).isDir())
    {
        return {};
    }
    const QDir rootDir(base);
    QList<QVariantMap> found;

    QDirIterator it(base, QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext())
    {
        const QString folder = it.next();
        const QString rel = rootDir.relativeFilePath(folder);
        const QStringList parts = rel.split('/', Qt::SkipEmptyParts);
        if (parts.size() > MAX_DEPTH)
        {
            continue;
        }
        bool skip = false;
        for (const QString &part : parts)
        {
            if (part.startsWith('.') || part.startsWith("_ocr"))
            {
                skip = true;
                break;
            }
        }
        if (skip)
        {
            continue;
        }
        const QStringList images = imagesIn(folder);
        if (images.size() < MIN_PAGES)
        {
            continue;
        }
        const QFileInfo info(folder);
        const QString mokuro = info.dir().filePath(info.fileName() + ".mokuro");
        found << QVariantMap{
            {"path", QDir::cleanPath(folder)},
            {"name", info.fileName()},
            {"series", parts.first()},
            {"seriesPath", QDir::cleanPath(rootDir.filePath(parts.first()))},
            {"mokuro", QFileInfo::exists(mokuro) ? mokuro : QString()},
            {"pages", images.size()},
            {"cover", QUrl::fromLocalFile(QDir(folder).filePath(images.first())).toString()},
        };
    }

    const QCollator collator = naturalCollator();
    std::sort(found.begin(), found.end(), [&collator] (const QVariantMap &a, const QVariantMap &b) {
        const int series = collator.compare(a["series"].toString(), b["series"].toString());
        if (series != 0)
        {
            return series < 0;
        }
        return collator.compare(a["path"].toString(), b["path"].toString()) < 0;
    });

    QVariantList result;
    for (const QVariantMap &volume : found)
    {
        result << volume;
    }
    return result;
}

QVariantList MangaLibrary::loadVolume(const QString &path) const
{
    const QDir dir(path);
    const QFileInfo info(path);
    const QJsonObject mokuro = readJson(info.dir().filePath(info.fileName() + ".mokuro"));

    QHash<QString, QJsonObject> ocr;
    for (const QJsonValue &value : mokuro.value("pages").toArray())
    {
        const QJsonObject page = value.toObject();
        ocr.insert(QDir::cleanPath(page.value("img_path").toString()).toLower(), page);
    }

    QVariantList pages;
    for (const QString &file : imagesIn(path))
    {
        const QJsonObject page = ocr.value(file.toLower());
        QVariantList blocks;
        for (const QJsonValue &value : page.value("blocks").toArray())
        {
            const QJsonObject block = value.toObject();
            blocks << QVariantMap{
                {"box", block.value("box").toArray().toVariantList()},
                {"vertical", block.value("vertical").toBool()},
                {"fontSize", block.value("font_size").toDouble()},
                {"lines", block.value("lines").toArray().toVariantList()},
                {"coords", block.value("lines_coords").toArray().toVariantList()},
            };
        }
        pages << QVariantMap{
            {"image", QUrl::fromLocalFile(dir.filePath(file)).toString()},
            {"file", dir.filePath(file)},
            {"w", page.value("img_width").toDouble()},
            {"h", page.value("img_height").toDouble()},
            {"blocks", blocks},
            {"ocr", !page.isEmpty()},
        };
    }
    return pages;
}

QVariantMap MangaLibrary::history() const
{
    return readJson(configFile("manga_history.json")).value("volumes").toObject().toVariantMap();
}

void MangaLibrary::saveProgress(const QString &path, const QVariantMap &entry)
{
    const QString file = configFile("manga_history.json");
    QJsonObject obj = readJson(file);
    QJsonObject volumes = obj.value("volumes").toObject();
    volumes.insert(QDir::cleanPath(path), QJsonObject::fromVariantMap(entry));
    obj.insert("version", 1);
    obj.insert("volumes", volumes);
    writeJson(file, obj);
    emit historyChanged();
}

void MangaLibrary::saveOpenSession(const QVariantMap &session)
{
    writeJson(configFile("manga_session_open.json"), QJsonObject::fromVariantMap(session));
}

QVariantMap MangaLibrary::openSession() const
{
    return readJson(configFile("manga_session_open.json")).toVariantMap();
}

bool MangaLibrary::finishSession(const QVariantMap &session)
{
    QFile::remove(configFile("manga_session_open.json"));
    const qint64 start = static_cast<qint64>(session.value("start").toDouble());
    const qint64 end = static_cast<qint64>(session.value("end").toDouble());
    const int seconds = session.value("seconds").toInt();
    if (start <= 0 || end < start || seconds < 60)
    {
        return false;
    }

    QFile file(configFile("manga_sessions.csv"));
    const bool fresh = !file.exists() || file.size() == 0;
    if (!file.open(QIODevice::Append | QIODevice::Text))
    {
        return false;
    }
    if (fresh)
    {
        file.write("start_utc,end_utc,series,volume,pages,chars,active_seconds\n");
    }
    const QStringList row{
        isoUtc(start),
        isoUtc(end),
        csvField(session.value("series").toString()),
        csvField(session.value("volume").toString()),
        QString::number(session.value("pages").toInt()),
        QString::number(session.value("chars").toInt()),
        QString::number(seconds),
    };
    file.write((row.join(',') + '\n').toUtf8());
    return true;
}

void MangaLibrary::runMokuro(const QStringList &paths)
{
    for (const QString &path : paths)
    {
        const QString clean = QDir::cleanPath(path);
        if (!m_queue.contains(clean) && clean != m_jobVolume)
        {
            m_queue << clean;
        }
    }
    m_lastError.clear();
    emit jobChanged();
    if (!m_process)
    {
        startNext();
    }
}

void MangaLibrary::cancelMokuro()
{
    m_queue.clear();
    if (m_process)
    {
        m_process->kill();
    }
    emit jobChanged();
}

void MangaLibrary::installMokuro()
{
    if (m_process)
    {
        return;
    }
    m_lastError.clear();
    startProcess({"-m", "pip", "install", "--upgrade", "mokuro"}, "install", {});
}

void MangaLibrary::checkMokuro()
{
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process] (int code, QProcess::ExitStatus) {
        const QString out = QString::fromUtf8(process->readAll()).trimmed();
        emit mokuroChecked(code == 0, out.section('\n', -1));
        process->deleteLater();
    });
    connect(process, &QProcess::errorOccurred, this, [this, process] (QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
        {
            emit mokuroChecked(false, tr("Python wasn't found (%1).").arg(python()));
            process->deleteLater();
        }
    });
    process->setProcessChannelMode(QProcess::MergedChannels);
    process->start(python(), {"-c", "import importlib.metadata as m; print('mokuro ' + m.version('mokuro'))"});
}

void MangaLibrary::startNext()
{
    while (!m_queue.isEmpty())
    {
        const QString volume = m_queue.takeFirst();
        if (QFileInfo(volume).isDir())
        {
            startProcess({"-m", "mokuro", volume, "--disable_confirmation=True"}, "mokuro", volume);
            return;
        }
    }
    m_jobVolume.clear();
    m_jobKind.clear();
    emit jobChanged();
}

void MangaLibrary::startProcess(const QStringList &args, const QString &kind, const QString &volume)
{
    m_process = new QProcess(this);
    m_jobKind = kind;
    m_jobVolume = volume;
    m_jobDone = 0;
    m_jobTotal = 0;
    m_jobLine = kind == "install" ? tr("Starting pip…") : tr("Starting mokuro…");
    m_tail.clear();

    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert("PYTHONUNBUFFERED", "1");
    env.insert("PYTHONIOENCODING", "utf-8");
    m_process->setProcessEnvironment(env);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    if (!volume.isEmpty())
    {
        m_process->setWorkingDirectory(QFileInfo(volume).absolutePath());
    }

    connect(m_process, &QProcess::readyRead, this, &MangaLibrary::readOutput);
    connect(m_process, &QProcess::finished, this, &MangaLibrary::processFinished);
    connect(m_process, &QProcess::errorOccurred, this, [this] (QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart || !m_process)
        {
            return;
        }
        m_lastError = tr("Python wasn't found (\"%1\"). Install Python 3.10 or newer from "
                         "python.org (tick \"Add python.exe to PATH\"), or set the Python "
                         "path in Manga > Settings.").arg(python());
        const QString kind = m_jobKind;
        const QString volume = m_jobVolume;
        m_process->deleteLater();
        m_process = nullptr;
        m_queue.clear();
        m_jobVolume.clear();
        m_jobKind.clear();
        emit jobChanged();
        if (kind == "install")
        {
            emit installFinished(false, m_lastError);
        }
        else
        {
            emit volumeFinished(volume, false, m_lastError);
        }
    });
    emit jobChanged();
    m_process->start(python(), args);
}

void MangaLibrary::readOutput()
{
    if (!m_process)
    {
        return;
    }
    m_tail += QString::fromUtf8(m_process->readAll());
    static const QRegularExpression splitter("[\r\n]");
    QStringList parts = m_tail.split(splitter);
    m_tail = parts.takeLast();
    m_tail = m_tail.right(4000);

    static const QRegularExpression count("\\|\\s*(\\d+)/(\\d+)\\s*\\[");
    static const QRegularExpression percent("(\\d+)%\\|");
    for (const QString &raw : parts)
    {
        const QString line = raw.trimmed();
        if (line.isEmpty())
        {
            continue;
        }
        m_jobLine = line.left(200);
        const QRegularExpressionMatch c = count.match(line);
        if (c.hasMatch())
        {
            m_jobDone = c.captured(1).toInt();
            m_jobTotal = c.captured(2).toInt();
        }
        else
        {
            const QRegularExpressionMatch p = percent.match(line);
            if (p.hasMatch())
            {
                m_jobDone = p.captured(1).toInt();
                m_jobTotal = 100;
            }
        }
    }
    emit jobChanged();
}

void MangaLibrary::processFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_process)
    {
        return;
    }
    readOutput();
    const QString kind = m_jobKind;
    const QString volume = m_jobVolume;
    const bool ok = status == QProcess::NormalExit && exitCode == 0;
    QString error;
    if (!ok)
    {
        error = m_jobLine.isEmpty() ? tr("Exited with code %1.").arg(exitCode) : m_jobLine;
        if (m_jobLine.contains("No module named mokuro") || m_jobLine.contains("No module named 'mokuro'"))
        {
            error = tr("mokuro isn't installed for this Python. Press Install mokuro.");
        }
        m_lastError = error;
    }
    m_process->deleteLater();
    m_process = nullptr;

    if (kind == "install")
    {
        m_jobKind.clear();
        emit jobChanged();
        emit installFinished(ok, error);
        return;
    }

    emit volumeFinished(volume, ok, error);
    if (!ok && error.contains("isn't installed"))
    {
        m_queue.clear();
    }
    startNext();
}

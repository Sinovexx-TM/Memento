#include "subfiles.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStringDecoder>
#include <QVariantMap>

namespace
{
const QStringList VIDEO_FILTERS{"*.mkv", "*.mp4", "*.avi", "*.webm", "*.m4v", "*.mov"};
const QStringList SUB_FILTERS{"*.srt", "*.ass", "*.ssa", "*.vtt"};
constexpr qint64 SNIFF_BYTES = 64 * 1024;
constexpr int JAPANESE_CHARS_NEEDED = 20;
}

SubFiles::SubFiles(QObject *parent) : QObject(parent)
{
}

QString SubFiles::folderOf(const QString &path) const
{
    if (path.isEmpty() || path.contains("://"))
    {
        return {};
    }
    QFileInfo info(path);
    return info.exists() ? info.absolutePath() : QString();
}

QString SubFiles::fileNameOf(const QString &path) const
{
    return QFileInfo(path).fileName();
}

QString SubFiles::join(const QString &folder, const QString &name) const
{
    return QDir(folder).filePath(name);
}

QStringList SubFiles::videos(const QString &folder) const
{
    if (folder.isEmpty())
    {
        return {};
    }
    return QDir(folder).entryList(VIDEO_FILTERS, QDir::Files, QDir::Name);
}

QString SubFiles::languageOf(const QString &path) const
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
    {
        return {};
    }
    const QByteArray data = file.read(SNIFF_BYTES);

    QString text;
    if (data.startsWith("\xFF\xFE") || data.startsWith("\xFE\xFF"))
    {
        auto decoder = QStringDecoder(
            data.startsWith("\xFF\xFE") ? QStringDecoder::Utf16LE : QStringDecoder::Utf16BE);
        text = decoder(data.mid(2));
    }
    else
    {
        auto decoder = QStringDecoder(QStringDecoder::Utf8);
        text = decoder(data);
        if (decoder.hasError())
        {
            /* Old Japanese subs are often Shift-JIS */
            auto sjis = QStringDecoder("Shift_JIS");
            if (sjis.isValid())
            {
                text = sjis(data);
            }
        }
    }

    int japanese = 0;
    for (const QChar ch : std::as_const(text))
    {
        const char16_t c = ch.unicode();
        if ((c >= 0x3040 && c <= 0x30FF) || (c >= 0x4E00 && c <= 0x9FFF))
        {
            if (++japanese >= JAPANESE_CHARS_NEEDED)
            {
                return QStringLiteral("ja");
            }
        }
    }
    return {};
}

QVariantList SubFiles::subtitles(const QString &folder) const
{
    QVariantList result;
    if (folder.isEmpty())
    {
        return result;
    }

    QDir dir(folder);
    QStringList dirs{QString()};
    for (const QString &sub : dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot))
    {
        if (sub.compare("subs", Qt::CaseInsensitive) == 0 ||
            sub.compare("subtitles", Qt::CaseInsensitive) == 0)
        {
            dirs << sub;
        }
    }

    for (const QString &sub : dirs)
    {
        QDir d(sub.isEmpty() ? folder : dir.filePath(sub));
        for (const QString &name : d.entryList(SUB_FILTERS, QDir::Files, QDir::Name))
        {
            const QString path = d.filePath(name);
            result << QVariantMap{
                {"name", name},
                {"dir", sub},
                {"path", path},
                {"lang", languageOf(path)},
            };
        }
    }
    return result;
}

QString SubFiles::rename(const QString &from, const QString &to) const
{
    if (QFileInfo::exists(to))
    {
        return tr("%1 already exists").arg(QFileInfo(to).fileName());
    }
    QFile file(from);
    if (!file.rename(to))
    {
        return file.errorString();
    }
    return {};
}

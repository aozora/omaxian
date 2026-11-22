#include "history.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QUrl>
#include <QtConcurrent>
#include <algorithm>

History::History(const QString &folder, const QString &musicFolder, QObject *parent)
    : QAbstractListModel(parent), m_folder(folder), m_musicFolder(musicFolder) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(150);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });
    connect(&m_debounce, &QTimer::timeout, this, &History::rescan);
    connect(&m_scan, &QFutureWatcher<QList<Entry>>::finished, this, [this] {
        const QList<Entry> entries = m_scan.result();
        beginResetModel();
        m_entries = entries;
        endResetModel();
        emit countChanged();
        if (m_again) {
            m_again = false;
            rescan();
        }
    });
    rescan();
}

namespace {

// A zlib stream, as a PNG's compressed text keeps it. qUncompress wants the
// size first; a guess is enough, as it grows the buffer when it must.
QByteArray inflate(const QByteArray &stream) {
    QByteArray sized(4, '\0');
    sized[2] = char(0x01); // 64 KiB
    return qUncompress(sized + stream);
}

// A PNG's text under `keyword`, read from its chunks up to the pixels. Qt's
// own reader turns the text's newlines into spaces, and the newline is what
// separates the prompt from the settings after it.
QString pngText(const QString &path, const QByteArray &keyword) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly) || file.read(8) != QByteArray("\x89PNG\r\n\x1a\n", 8))
        return {};
    while (!file.atEnd()) {
        const QByteArray head = file.read(8);
        if (head.size() < 8)
            break;
        const quint32 length = quint32(uchar(head[0])) << 24 | quint32(uchar(head[1])) << 16
                             | quint32(uchar(head[2])) << 8 | quint32(uchar(head[3]));
        const QByteArray type = head.mid(4, 4);
        if (type == "IDAT" || type == "IEND" || length > 16 * 1024 * 1024)
            break;
        if (type != "tEXt" && type != "zTXt" && type != "iTXt") {
            file.skip(qint64(length) + 4);
            continue;
        }
        const QByteArray body = file.read(length);
        file.skip(4);
        const qsizetype end = body.indexOf('\0');
        if (end < 0 || body.left(end) != keyword)
            continue;
        // stable-diffusion.cpp writes plain tEXt, in UTF-8 whatever the
        // standard says; Qt, which writes the posters, keeps to the standard's
        // Latin-1 wherever the text fits it, so "tô" is one byte that is no
        // UTF-8. Other writers compress a long text.
        if (type == "tEXt" || type == "zTXt") {
            const QByteArray text = type == "tEXt" ? body.mid(end + 1) : inflate(body.mid(end + 2));
            return text.isValidUtf8() ? QString::fromUtf8(text) : QString::fromLatin1(text);
        }
        // iTXt: keyword, compression flag and method, language, translated
        // keyword, then the text.
        if (end + 2 >= body.size())
            continue;
        const bool compressed = body.at(end + 1) != 0;
        qsizetype text = body.indexOf('\0', end + 3);
        text = text < 0 ? -1 : body.indexOf('\0', text + 1);
        if (text >= 0)
            return QString::fromUtf8(compressed ? inflate(body.mid(text + 1)) : body.mid(text + 1));
    }
    return {};
}

} // namespace

History::Entry History::readEntry(const QString &path, const QString &musicFolder) {
    Entry entry;
    entry.path = path;
    entry.modified = QFileInfo(path).lastModified();
    const QString parameters = pngText(path, "parameters");
    // A clip's poster names the clip beside it.
    // Only its own: the clip of the same name beside it.
    const QFileInfo poster(path);
    if (pngText(path, "fantasi-video") == poster.completeBaseName() + ".webm")
        entry.video = poster.absoluteDir().filePath(poster.completeBaseName() + ".webm");
    // A song's poster likewise, the song being with the music.
    if (!musicFolder.isEmpty() && pngText(path, "fantasi-audio") == poster.completeBaseName() + ".mp3") {
        entry.audio = musicFolder + "/" + poster.completeBaseName() + ".mp3";
        entry.title = pngText(path, "fantasi-title");
        for (const char level : QByteArray::fromHex(pngText(path, "fantasi-wave").toLatin1()))
            entry.wave << uchar(level) / 255.0;
    }
    const qsizetype settings = parameters.lastIndexOf("\nSteps: ");
    entry.prompt = (settings >= 0 ? parameters.left(settings) : parameters).trimmed();
    static const QRegularExpression seed("(?:^|, )Seed: (-?\\d+)"), size("(?:^|, )Size: (\\d+x\\d+)");
    const QString line = settings >= 0 ? parameters.mid(settings + 1) : QString();
    if (const auto match = seed.match(line); match.hasMatch())
        entry.seed = match.captured(1).toLongLong();
    if (const auto match = size.match(line); match.hasMatch())
        entry.size = match.captured(1);
    return entry;
}

QList<History::Entry> History::scan(const QString &folder, const QString &musicFolder) {
    QList<Entry> entries;
    for (const QFileInfo &info : QDir(folder).entryInfoList({"*.png", "*.jpg", "*.jpeg", "*.webp"}, QDir::Files))
        entries << readEntry(info.filePath(), musicFolder);
    std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) {
        return a.modified != b.modified ? a.modified > b.modified : a.path > b.path;
    });
    return entries;
}

void History::watch() {
    const QStringList paths = m_watcher.directories();
    if (!paths.isEmpty())
        m_watcher.removePaths(paths);
    // Before the first image there is no folder: its nearest parent is
    // watched, so the first one shows.
    QString ancestor = m_folder;
    while (!QFileInfo::exists(ancestor) && ancestor != "/")
        ancestor = QFileInfo(ancestor).absolutePath();
    m_watcher.addPath(ancestor);
}

void History::rescan() {
    watch();
    // Reading every image's header is slow for a big folder, so it happens
    // off the window's thread, one scan at a time.
    if (m_scan.isRunning()) {
        m_again = true;
        return;
    }
    m_scan.setFuture(QtConcurrent::run(&History::scan, m_folder, m_musicFolder));
}

int History::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : int(m_entries.size()); }

QVariant History::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_entries.size())
        return {};
    const Entry &entry = m_entries.at(index.row());
    switch (role) {
    case UrlRole:
        return QUrl::fromLocalFile(entry.path).toString();
    case PathRole:
        return entry.path;
    case PromptRole:
        return entry.prompt;
    case VideoRole:
        return entry.video.isEmpty() ? QString() : QUrl::fromLocalFile(entry.video).toString();
    case AudioRole:
        return entry.audio.isEmpty() ? QString() : QUrl::fromLocalFile(entry.audio).toString();
    case TitleRole:
        return entry.title;
    case WaveRole:
        return entry.wave;
    case SeedRole:
        return entry.seed;
    case SizeRole:
        return entry.size;
    default:
        return {};
    }
}

QHash<int, QByteArray> History::roleNames() const {
    return {{UrlRole, "url"}, {PathRole, "path"}, {PromptRole, "prompt"}, {SeedRole, "seed"}, {SizeRole, "size"}, {VideoRole, "video"},
            {AudioRole, "audio"}, {TitleRole, "title"}, {WaveRole, "wave"}};
}

QVariantMap History::song(const QString &url) const {
    const QString path = QUrl(url).toLocalFile();
    for (const Entry &entry : m_entries)
        if (!path.isEmpty() && entry.audio == path)
            return {{"title", entry.title}, {"wave", entry.wave}};
    return {{"title", QString()}, {"wave", QVariantList()}};
}

bool History::remove(int row) {
    if (row < 0 || row >= m_entries.size())
        return false;
    if (!QFile::moveToTrash(m_entries.at(row).path))
        return false;
    // A clip or a song goes with its poster.
    for (const QString &media : {m_entries.at(row).video, m_entries.at(row).audio})
        if (!media.isEmpty())
            QFile::moveToTrash(media);
    beginRemoveRows({}, row, row);
    m_entries.removeAt(row);
    endRemoveRows();
    emit countChanged();
    return true;
}

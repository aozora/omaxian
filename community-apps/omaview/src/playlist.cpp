#include "playlist.h"

#include <QCollator>
#include <QDir>
#include <QFileInfo>
#include <QImageReader>
#include <QLocale>
#include <QSet>
#include <QStringView>
#include <algorithm>

namespace playlist {

namespace {

const QSet<QString> &videoExtensions() {
    static const QSet<QString> set{"mkv", "mp4", "m4v", "mov", "webm", "avi", "wmv", "flv", "mpg", "mpeg",
                                   "m2ts", "mts", "ts", "ogv", "3gp", "3g2", "asf", "vob", "divx", "f4v"};
    return set;
}

const QSet<QString> &audioExtensions() {
    static const QSet<QString> set{"mp3", "flac", "ogg", "oga", "opus", "m4a", "aac", "wav", "wma", "alac",
                                   "aiff", "aif", "ape", "mka", "wv"};
    return set;
}

// Whatever Qt's image plugins read here, so installing kimageformats brings
// HEIC, AVIF and JPEG XL without a change to Omaview. PDF is a document, not a
// picture, though Qt's PDF module offers it as an image format.
const QSet<QString> &pictureExtensions() {
    static const QSet<QString> set = [] {
        QSet<QString> found{"jpg", "jpeg", "png", "gif", "webp", "bmp", "svg"};
        for (const QByteArray &format : QImageReader::supportedImageFormats())
            found << QString::fromLatin1(format).toLower();
        found.remove("pdf");
        for (const QString &suffix : videoExtensions())
            found.remove(suffix);
        for (const QString &suffix : audioExtensions())
            found.remove(suffix);
        return found;
    }();
    return set;
}

QStringView fileNameOf(const QString &path) {
    const QStringView view(path);
    const qsizetype slash = view.lastIndexOf('/');
    return slash >= 0 ? view.sliced(slash + 1) : view;
}

QString suffixOf(const QString &path) {
    const QStringView name = fileNameOf(path);
    const qsizetype dot = name.lastIndexOf('.');
    return dot >= 0 ? name.sliced(dot + 1).toString().toLower() : QString();
}

}  // namespace

Kind kind(const QString &path) {
    const QString suffix = suffixOf(path);
    if (videoExtensions().contains(suffix))
        return Kind::Video;
    if (audioExtensions().contains(suffix))
        return Kind::Audio;
    if (pictureExtensions().contains(suffix))
        return Kind::Picture;
    return Kind::None;
}

bool picture(const QString &path) { return kind(path) == Kind::Picture; }

// Natural, case-insensitive order. Precomputes sort keys once per path rather
// than constructing QFileInfo and running collation on every comparison.
static void sort(QStringList &paths) {
    if (paths.size() < 2)
        return;
    // Qt's C-locale collator bypasses ICU, dropping numeric mode and
    // sortKey() case-insensitivity; fall back to an ICU locale when C is set.
    const QLocale locale;
    QCollator collator(locale.language() == QLocale::C ? QLocale(QLocale::English) : locale);
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    struct Item {
        QCollatorSortKey key;
        QString path;
    };
    QList<Item> items;
    items.reserve(paths.size());
    for (QString &path : paths)
        items.push_back({collator.sortKey(fileNameOf(path).toString()), std::move(path)});
    std::sort(items.begin(), items.end(), [](const Item &a, const Item &b) {
        const int order = a.key.compare(b.key);
        return order != 0 ? order < 0 : a.path < b.path;
    });
    for (qsizetype i = 0; i < paths.size(); ++i)
        paths[i] = std::move(items[i].path);
}

QStringList siblings(const QString &path) {
    const QFileInfo file(path);
    const Kind own = kind(path);
    QStringList found;
    for (const QFileInfo &entry : file.dir().entryInfoList(QDir::Files | QDir::Readable)) {
        const Kind other = kind(entry.fileName());
        if (other == Kind::None)
            continue;
        if ((own == Kind::Picture && other == Kind::Audio) || (own == Kind::Audio && other == Kind::Picture))
            continue;
        found << entry.absoluteFilePath();
    }
    const QString self = file.absoluteFilePath();
    if (!found.contains(self))
        found << self;
    sort(found);
    return found;
}

QStringList folder(const QString &directory) {
    QStringList pictures, songs, videos;
    for (const QFileInfo &entry : QDir(directory).entryInfoList(QDir::Files | QDir::Readable)) {
        switch (kind(entry.fileName())) {
        case Kind::Picture: pictures << entry.absoluteFilePath(); break;
        case Kind::Audio: songs << entry.absoluteFilePath(); break;
        case Kind::Video: videos << entry.absoluteFilePath(); break;
        case Kind::None: break;
        }
    }
    // An album's cover doesn't make it a folder of pictures: whichever there
    // are more of wins.
    QStringList found = pictures.size() > songs.size() ? std::move(pictures) : std::move(songs);
    found.append(videos);
    sort(found);
    return found;
}

}  // namespace playlist

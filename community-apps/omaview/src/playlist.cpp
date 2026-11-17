#include "playlist.h"

#include <QCollator>
#include <QDir>
#include <QFileInfo>
#include <QImageReader>
#include <QSet>
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

QString suffixOf(const QString &path) {
    return QFileInfo(path).suffix().toLower();
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

// Natural, case-insensitive order.
static void sort(QStringList &paths) {
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(paths.begin(), paths.end(), [&](const QString &a, const QString &b) {
        const int order = collator.compare(QFileInfo(a).fileName(), QFileInfo(b).fileName());
        return order != 0 ? order < 0 : a < b;
    });
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
    QStringList found;
    int pictures = 0, songs = 0;
    for (const QFileInfo &entry : QDir(directory).entryInfoList(QDir::Files | QDir::Readable)) {
        const Kind each = kind(entry.fileName());
        if (each == Kind::None)
            continue;
        pictures += each == Kind::Picture;
        songs += each == Kind::Audio;
        found << entry.absoluteFilePath();
    }
    // An album's cover doesn't make it a folder of pictures: whichever there
    // are more of wins.
    const Kind left = pictures > songs ? Kind::Audio : Kind::Picture;
    found.removeIf([left](const QString &path) { return kind(path) == left; });
    sort(found);
    return found;
}

}  // namespace playlist

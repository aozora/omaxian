#include "frames.h"

#include <QCache>
#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QEventLoopLocker>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QMutex>
#include <QPainter>
#include <QPointer>
#include <QProcess>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QThread>
#include <QThreadPool>
#include <QtConcurrent>
#include <algorithm>
#include <numeric>
#include <cmath>
#include <sys/stat.h>
#include <unistd.h>
#include <utime.h>

#include "positions.h"
#include "probe.h"
#include "texts.h"

namespace frames {

namespace {

QString seconds(double value) {
    return QString::number(std::max(0.0, value), 'f', 3);
}

// Runs ffmpeg and returns stdout, or empty with the reason in *error.
QByteArray ffmpeg(const QStringList &arguments, int timeoutMs, QString *error, bool lowPriority = false,
                  const std::atomic_bool *cancelled = nullptr) {
    const QString tool = probe::toolPath("ffmpeg");
    if (tool.isEmpty()) {
        if (error)
            *error = Texts::tr("ffmpeg was not found. Install ffmpeg.");
        return {};
    }
    QProcess process;
    if (lowPriority)
        process.setChildProcessModifier([] { (void)::nice(10); });
    process.start(tool, QStringList{"-nostdin", "-v", "error"} + arguments);
    // Waits in slices, so a cancelled preview stops its ffmpeg promptly.
    QElapsedTimer clock;
    clock.start();
    while (!process.waitForFinished(100)) {
        if (process.state() == QProcess::NotRunning)
            break;
        if ((cancelled && *cancelled) || clock.elapsed() > timeoutMs) {
            process.kill();
            process.waitForFinished(1000);
            if (error)
                *error = Texts::tr("ffmpeg took too long.");
            return {};
        }
    }
    if (process.exitStatus() != QProcess::NormalExit || process.exitCode() != 0) {
        if (error) {
            const QString message = QString::fromUtf8(process.readAllStandardError()).trimmed().section('\n', -1);
            *error = message.isEmpty() ? Texts::tr("ffmpeg could not read this file.")
                                       : message;
        }
        return {};
    }
    return process.readAllStandardOutput();
}

}  // namespace

namespace {

// Read rather than set and restored, which would race other threads making
// files; Linux reports it in /proc since 4.7.
mode_t processUmask() {
    QFile status("/proc/self/status");
    if (status.open(QIODevice::ReadOnly))
        for (const QByteArray &line : status.readAll().split('\n'))
            if (line.startsWith("Umask:")) {
                bool ok = false;
                const uint mask = line.mid(6).trimmed().toUInt(&ok, 8);
                if (ok)
                    return mode_t(mask);
            }
    return 022;
}

}  // namespace

QImage extract(const QString &path, double at, QString *error) {
    // -ss before -i seeks the input, which ffmpeg makes exact when decoding.
    const QByteArray png = ffmpeg({"-ss", seconds(at), "-i", path, "-map", "0:V:0", "-frames:v", "1",
                                   "-f", "image2pipe", "-c:v", "png", "-"},
                                  60000, error);
    if (png.isEmpty()) {
        if (error && error->isEmpty())
            *error = Texts::tr("There is no frame at that time.");
        return {};
    }
    QImage image = QImage::fromData(png, "PNG");
    if (image.isNull() && error)
        *error = Texts::tr("ffmpeg gave a frame that could not be read.");
    return image;
}

bool savePng(const QImage &image, const QString &path, QString *error) {
    QSaveFile file(path);
    file.setDirectWriteFallback(false);
    if (!file.open(QIODevice::WriteOnly) || !image.save(&file, "PNG")) {
        if (error)
            *error = file.errorString();
        file.cancelWriting();
        return false;
    }
    // A QSaveFile's temp file is 0600 whatever the umask; give it what a new
    // file would get, or what the file it replaces had.
    QFileDevice::Permissions permissions = QFileDevice::ReadOwner | QFileDevice::WriteOwner
                                           | QFileDevice::ReadGroup | QFileDevice::ReadOther;
    if (QFileInfo::exists(path))
        permissions = QFile::permissions(path);
    else {
        const mode_t mask = processUmask();
        permissions = QFileDevice::Permissions();
        const mode_t mode = 0666 & ~mask;
        if (mode & 0400) permissions |= QFileDevice::ReadOwner | QFileDevice::ReadUser;
        if (mode & 0200) permissions |= QFileDevice::WriteOwner | QFileDevice::WriteUser;
        if (mode & 0040) permissions |= QFileDevice::ReadGroup;
        if (mode & 0020) permissions |= QFileDevice::WriteGroup;
        if (mode & 0004) permissions |= QFileDevice::ReadOther;
        if (mode & 0002) permissions |= QFileDevice::WriteOther;
    }
    file.setPermissions(permissions);
    if (!file.commit()) {
        if (error)
            *error = file.errorString();
        return false;
    }
    return true;
}

bool copyWithWlCopy(const QByteArray &png) {
    auto run = [&](const QString &tool, const QStringList &args) {
        QProcess process;
        process.start(tool, args);
        if (!process.waitForStarted(2000))
            return false;
        process.write(png);
        process.closeWriteChannel();
        return process.waitForFinished(5000) && process.exitStatus() == QProcess::NormalExit
            && process.exitCode() == 0;
    };

    // wl-copy forks a server that holds the clipboard and returns at once.
    const QString wlCopy = probe::toolPath("wl-copy");
    if (!wlCopy.isEmpty() && !qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY")
        && run(wlCopy, {"--type", "image/png"}))
        return true;

    // Omaxian / X11: xclip keeps serving the PNG after Omaview quits.
    const QString xclip = probe::toolPath("xclip");
    if (!xclip.isEmpty()
        && run(xclip, {"-selection", "clipboard", "-t", "image/png", "-i"}))
        return true;
    return false;
}

PreviewLayout PreviewLayout::forVideo(double duration, QSize videoSize) {
    PreviewLayout layout;
    if (duration <= 0 || videoSize.isEmpty())
        return layout;
    // One every two seconds for short clips, never more than 100, so a film
    // costs the same as a trailer and the atlas stays small.
    layout.count = std::clamp(int(duration / 2), 1, 100);
    layout.interval = duration / layout.count;
    layout.columns = std::min(10, layout.count);
    const int width = 192;
    const int height = std::clamp(int(std::lround(width * double(videoSize.height()) / videoSize.width())) & ~1,
                                  54, 384);
    layout.tileSize = QSize(width, height);
    return layout;
}

QString previewCacheDirectory() {
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + "/omaview/previews";
}

QString previewCachePath(const QString &videoPath) {
    const QString key = Positions::key(videoPath);
    return key.isEmpty() ? QString() : previewCacheDirectory() + "/" + key + ".jpg";
}

namespace {

QString cachePath(const QString &path, const char *kind) {
    const QString key = Positions::key(path);
    return key.isEmpty() ? QString() : previewCacheDirectory() + "/" + key + kind;
}

// One lock per cache file, so asking for one that is being made waits for it
// rather than making it twice, and never waits on another's.
std::shared_ptr<QMutex> lockFor(const QString &cache) {
    static QMutex guard;
    static QHash<QString, std::weak_ptr<QMutex>> locks;
    QMutexLocker locker(&guard);
    if (locks.size() > 512)
        locks.removeIf([](const auto &entry) { return entry.value().expired(); });
    std::shared_ptr<QMutex> lock = locks.value(cache).lock();
    if (!lock) {
        lock = std::make_shared<QMutex>();
        locks.insert(cache, lock);
    }
    return lock;
}

// Files ffmpeg had nothing for, such as a song in an .mp4 or a broken video,
// aren't tried again every time their tile comes back.
QMutex failedLock;
QSet<QString> failed;
bool hasFailed(const QString &cache) {
    QMutexLocker locker(&failedLock);
    return failed.contains(cache);
}
void markFailed(const QString &cache) {
    QMutexLocker locker(&failedLock);
    failed.insert(cache);
}

// Read from the cache, and touched, so pruning removes what hasn't been
// looked at lately rather than what was made first.
QImage readCached(const QString &cache) {
    QImage image(cache);
    if (!image.isNull())
        (void)::utime(QFile::encodeName(cache).constData(), nullptr);
    return image;
}

// Written whole or not at all, and the cache pruned on the first write and
// every 32nd after, rather than after every one.
void writeCached(const QImage &image, const QString &cache) {
    if (!QDir().mkpath(previewCacheDirectory()))
        return;
    QSaveFile file(cache);
    if (!file.open(QIODevice::WriteOnly) || !image.save(&file, "JPG", 85) || !file.commit())
        return;
    static std::atomic_int writes{0};
    static QMutex pruning;
    // The first write of a run prunes too, so short runs, a small folder
    // browsed and closed, don't leave the cache to grow.
    if (writes++ % 32 == 0 && pruning.tryLock()) {
        prunePreviewCache(previewCacheDirectory(), previewCacheLimit);
        pruning.unlock();
    }
}

// The strips' seeks run in a pool of their own, so the app's other work in
// the background, reading a picture's header, say, never waits behind them.
QThreadPool &shotPool() {
    static QThreadPool *pool = [] {
        auto *created = new QThreadPool;
        created->setMaxThreadCount(std::max(4, QThread::idealThreadCount()));
        return created;
    }();
    return *pool;
}

// The last strips decoded, so a preview's ten frames decode the strip once.
QMutex stripsLock;
QCache<QString, QImage> strips(64 * 1024 * 1024);

}  // namespace

QImage poster(const QString &path, const std::atomic_bool *cancelled) {
    const QString cache = cachePath(path, ".poster.jpg");
    if (cache.isEmpty() || hasFailed(cache))
        return {};
    const std::shared_ptr<QMutex> lock = lockFor(cache);
    QMutexLocker locker(lock.get());
    QImage image = readCached(cache);
    if (!image.isNull())
        return image;
    // A clip shorter than the first try has its first frame.
    for (const QString &at : {QStringLiteral("3"), QStringLiteral("0")}) {
        const QByteArray png = ffmpeg({"-ss", at, "-i", path, "-map", "0:V:0", "-frames:v", "1", "-vf", "scale=640:-2",
                                       "-f", "image2pipe", "-c:v", "png", "-"},
                                      20000, nullptr, true, cancelled);
        image = QImage::fromData(png, "PNG");
        if (!image.isNull() || (cancelled && *cancelled))
            break;
    }
    if (!image.isNull())
        writeCached(image, cache);
    else if (!(cancelled && *cancelled))
        markFailed(cache);
    return image;
}

bool filmstripTried(const QString &path) {
    const QString cache = cachePath(path, ".strip.jpg");
    return cache.isEmpty() || hasFailed(cache) || QFileInfo::exists(cache);
}

QImage makeFilmstrip(const QString &path, const std::atomic_bool *cancelled) {
    const QString cache = cachePath(path, ".strip.jpg");
    if (cache.isEmpty() || hasFailed(cache))
        return {};
    {
        QMutexLocker locker(&stripsLock);
        if (const QImage *kept = strips.object(cache))
            return *kept;
    }
    const std::shared_ptr<QMutex> lock = lockFor(cache);
    QMutexLocker locker(lock.get());
    QImage strip = readCached(cache);
    if (strip.isNull()) {
        const double duration = probe::run(path, 5000, cancelled).duration;
        if (duration <= 0) {
            if (!(cancelled && *cancelled))
                markFailed(cache);
            return {};
        }
        // The ten seeks run side by side. In a long video each takes the
        // keyframe at or before its time, which needs no decoding past it; a
        // short one, whose keyframes may be far apart, is decoded to the frame.
        const bool keyframes = duration > 60;
        QList<int> indices(filmstripFrames);
        std::iota(indices.begin(), indices.end(), 0);
        QList<QImage> shots = QtConcurrent::blockingMapped(&shotPool(), indices, [&](int i) {
            QStringList arguments;
            if (keyframes)
                arguments << "-skip_frame" << "nokey" << "-noaccurate_seek";
            arguments << "-ss" << seconds(duration * (i + 0.5) / filmstripFrames) << "-i" << path << "-map"
                      << "0:V:0" << "-frames:v" << "1" << "-vf" << "scale=320:-2" << "-f" << "image2pipe" << "-c:v"
                      << "png" << "-";
            return QImage::fromData(ffmpeg(arguments, 20000, nullptr, true, cancelled), "PNG");
        });
        if (cancelled && *cancelled)
            return {};
        // A seek that found nothing, past the last frame of a clip whose sound
        // runs on, borrows its neighbour's frame rather than losing the strip.
        const auto found = std::find_if(shots.begin(), shots.end(), [](const QImage &shot) { return !shot.isNull(); });
        if (found == shots.end()) {
            markFailed(cache);
            return {};
        }
        for (int i = 0; i < shots.size(); ++i)
            if (shots[i].isNull())
                shots[i] = i > 0 && !shots[i - 1].isNull() ? shots[i - 1] : *found;
        const QSize size = shots.first().size();
        strip = QImage(size.width() * filmstripFrames, size.height(), QImage::Format_RGB32);
        strip.fill(Qt::black);
        QPainter painter(&strip);
        for (int i = 0; i < filmstripFrames; ++i)
            painter.drawImage(QRect(QPoint(i * size.width(), 0), size), shots[i]);
        painter.end();
        writeCached(strip, cache);
    }
    QMutexLocker kept(&stripsLock);
    strips.insert(cache, new QImage(strip), int(strip.sizeInBytes()));
    return strip;
}

QImage filmstripFrame(const QString &path, int n, const std::atomic_bool *cancelled) {
    if (n < 0 || n >= filmstripFrames)
        return {};
    const QImage strip = makeFilmstrip(path, cancelled);
    if (strip.isNull())
        return {};
    const int width = strip.width() / filmstripFrames;
    return strip.copy(n * width, 0, width, strip.height());
}

void prunePreviewCache(const QString &directory, qint64 limitBytes) {
    QFileInfoList files = QDir(directory).entryInfoList({"*.jpg"}, QDir::Files, QDir::Time | QDir::Reversed);
    qint64 total = 0;
    for (const QFileInfo &file : files)
        total += file.size();
    for (const QFileInfo &file : files) {
        if (total <= limitBytes)
            break;
        total -= file.size();
        QFile::remove(file.absoluteFilePath());
    }
}

Previews::Previews(QObject *parent) : QObject(parent) {}

Previews::~Previews() {
    cancel();
}

void Previews::cancel() {
    if (m_cancelled)
        *m_cancelled = true;
    m_cancelled.reset();
    ++m_generation;
}

void Previews::start(const QString &path, double duration, QSize videoSize) {
    cancel();
    const PreviewLayout layout = PreviewLayout::forVideo(duration, videoSize);
    const QString cachePath = previewCachePath(path);
    if (layout.count == 0 || cachePath.isEmpty())
        return;
    if (QFileInfo::exists(cachePath)) {
        // Touched, so pruning removes what hasn't been watched lately first.
        QFile file(cachePath);
        if (file.open(QIODevice::ReadWrite))
            file.setFileTime(QDateTime::currentDateTime(), QFileDevice::FileModificationTime);
        emit ready(cachePath, layout);
        return;
    }

    auto cancelled = std::make_shared<std::atomic_bool>(false);
    m_cancelled = cancelled;
    const quint64 generation = m_generation;
    QPointer<Previews> self(this);
    (void)QtConcurrent::run([self, generation, cancelled, path, layout, cachePath] {
        // The work finishes, or is cancelled, even if the window closes first.
        QEventLoopLocker keepRunning;
        const int rows = (layout.count + layout.columns - 1) / layout.columns;
        QImage atlas(layout.tileSize.width() * layout.columns, layout.tileSize.height() * rows, QImage::Format_RGB32);
        atlas.fill(Qt::black);
        QPainter painter(&atlas);
        const QString scale = QString("scale=%1:%2:force_original_aspect_ratio=decrease")
                                  .arg(layout.tileSize.width()).arg(layout.tileSize.height());
        int made = 0;
        for (int i = 0; i < layout.count; ++i) {
            if (*cancelled)
                return;
            // A file ffmpeg can't read at all fails on every tile; stop early
            // rather than spawning the rest.
            if (i == 3 && made == 0)
                return;
            // A fast seek to the keyframe before each time: good enough for a
            // thumbnail, and far cheaper than decoding the film.
            const QByteArray bytes = ffmpeg({"-skip_frame", "nokey", "-ss", seconds((i + 0.5) * layout.interval),
                                             "-i", path, "-map", "0:V:0", "-frames:v", "1", "-vf", scale,
                                             "-f", "image2pipe", "-c:v", "bmp", "-"},
                                            20000, nullptr, true, cancelled.get());
            const QImage tile = QImage::fromData(bytes, "BMP");
            if (tile.isNull())
                continue;
            ++made;
            const QPoint cell((i % layout.columns) * layout.tileSize.width(),
                              (i / layout.columns) * layout.tileSize.height());
            painter.drawImage(cell + QPoint((layout.tileSize.width() - tile.width()) / 2,
                                            (layout.tileSize.height() - tile.height()) / 2),
                              tile);
        }
        painter.end();
        // Never cache a blank atlas: the next open tries again.
        if (*cancelled || made == 0)
            return;
        QDir().mkpath(previewCacheDirectory());
        QSaveFile out(cachePath);
        out.setDirectWriteFallback(false);
        if (!out.open(QIODevice::WriteOnly) || !atlas.save(&out, "JPG", 80) || !out.commit())
            return;
        prunePreviewCache(previewCacheDirectory(), previewCacheLimit);
        QMetaObject::invokeMethod(
            qApp,
            [self, generation, cachePath, layout] {
                if (self && self->m_generation == generation)
                    emit self->ready(cachePath, layout);
            },
            Qt::QueuedConnection);
    });
}

}  // namespace frames

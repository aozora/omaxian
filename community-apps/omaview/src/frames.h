#pragma once

#include <QImage>
#include <QObject>
#include <QSize>
#include <QString>
#include <atomic>
#include <memory>

namespace frames {

// The exact frame at a time, at the video's own size, through ffmpeg. Runs a
// process synchronously, so call it off the GUI thread.
QImage extract(const QString &path, double seconds, QString *error = nullptr);

// Writes a PNG atomically, with the permissions a new file would have.
bool savePng(const QImage &image, const QString &path, QString *error = nullptr);

// Puts a PNG on the clipboard so it outlives Omaview: wl-copy on Wayland,
// else xclip on X11. False when neither tool works (caller can fall back to
// Qt's clipboard for the lifetime of the process).
bool copyWithWlCopy(const QByteArray &png);

// The scrub previews' layout: count tiles of tileSize in rows of columns,
// one every interval seconds, the first at interval / 2.
struct PreviewLayout {
    int count = 0;
    int columns = 10;
    QSize tileSize;
    double interval = 0;
    static PreviewLayout forVideo(double duration, QSize videoSize);
};

// A frame a few seconds in, 640 wide, for the grid's tile; cached beside
// the previews by the file's path, size and time. Runs ffmpeg
// synchronously, so call it off the GUI thread.
QImage poster(const QString &path, const std::atomic_bool *cancelled = nullptr);

// The grid's preview: frame n of filmstripFrames, spread evenly over the
// video, 320 wide. The whole strip is made on the first ask and cached as
// one image beside the previews. Synchronous, so off the GUI thread.
constexpr int filmstripFrames = 10;
QImage filmstripFrame(const QString &path, int n, const std::atomic_bool *cancelled = nullptr);
// The whole strip, made if it isn't cached yet; the grid starts it for each
// video as its tile shows, so it is ready by the time it is picked.
QImage makeFilmstrip(const QString &path, const std::atomic_bool *cancelled = nullptr);
// Whether its strip is cached already, or was tried and can't be made.
bool filmstripTried(const QString &path);

QString previewCacheDirectory();
// The previews, posters and strips together stay under this.
constexpr qint64 previewCacheLimit = 256LL * 1024 * 1024;
// The cached atlas for a file, if its path, size and time still match.
QString previewCachePath(const QString &videoPath);
// Keeps the cache under a size, removing the least recently used first.
void prunePreviewCache(const QString &directory, qint64 limitBytes);

// Builds a file's previews in the background, a fast seek per tile at low
// priority, and caches them. One at a time: starting another cancels it.
class Previews : public QObject {
    Q_OBJECT

public:
    explicit Previews(QObject *parent = nullptr);
    ~Previews() override;

    void start(const QString &path, double duration, QSize videoSize);
    void cancel();

signals:
    // The atlas as a file URL the window can load, and its layout.
    void ready(const QString &atlasPath, const frames::PreviewLayout &layout);

private:
    std::shared_ptr<std::atomic_bool> m_cancelled;
    quint64 m_generation = 0;
};

}  // namespace frames

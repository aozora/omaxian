#include "thumbnails.h"

#include <QImageReader>
#include <QRunnable>
#include <QThread>
#include <QUrl>

#include "frames.h"
#include "playlist.h"

namespace {

QThreadPool &filmstrips() {
    static QThreadPool *pool = [] {
        auto *created = new QThreadPool;
        created->setMaxThreadCount(2);
        return created;
    }();
    return *pool;
}

QImage picture(const QString &path, const QSize &requested) {
    QImageReader reader(path);
    reader.setAutoTransform(true);
    QSize size = reader.size();
    if (!size.isEmpty() && !requested.isEmpty()) {
        // Turned upright, the size it is shown at; decoded at just enough to
        // cover the tile, which JPEG does far faster than the whole picture.
        const bool turned = reader.transformation() & QImageIOHandler::TransformationRotate90;
        const QSize upright = turned ? size.transposed() : size;
        const double scale = std::max(double(requested.width()) / upright.width(),
                                      double(requested.height()) / upright.height());
        if (scale < 1)
            reader.setScaledSize(QSize(std::max(1, qRound(size.width() * scale)),
                                       std::max(1, qRound(size.height() * scale))));
    }
    return reader.read();
}

class Response : public QQuickImageResponse, public QRunnable {
public:
    Response(const QString &path, const QSize &requested, int frame, std::shared_ptr<std::atomic_bool> stopping)
        : m_path(path), m_requested(requested), m_frame(frame), m_stopping(std::move(stopping)) {
        setAutoDelete(false);
    }
    QQuickTextureFactory *textureFactory() const override {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }
    // A tile scrolled away before its turn came: nothing is decoded for it.
    void cancel() override { m_cancelled = true; }
    void run() override {
        if (m_cancelled) {
            emit finished();
            return;
        }
        if (m_frame >= 0) {
            m_image = frames::filmstripFrame(m_path, m_frame, m_stopping.get());
            emit finished();
            return;
        }
        switch (playlist::kind(m_path)) {
        case playlist::Kind::Picture:
            m_image = picture(m_path, m_requested);
            break;
        case playlist::Kind::Video:
            m_image = frames::poster(m_path, m_stopping.get());
            // Its preview frames are made behind it, a couple of videos at
            // a time, so they are there when it's picked.
            if (!frames::filmstripTried(m_path))
                filmstrips().start([path = m_path, stopping = m_stopping] {
                    if (!frames::filmstripTried(path))
                        frames::makeFilmstrip(path, stopping.get());
                });
            break;
        default:
            break;
        }
        emit finished();
    }

private:
    QString m_path;
    QSize m_requested;
    int m_frame = -1;
    std::shared_ptr<std::atomic_bool> m_stopping;
    std::atomic_bool m_cancelled{false};
    QImage m_image;
};

}  // namespace

ThumbnailProvider::ThumbnailProvider() {
    m_pool.setMaxThreadCount(std::max(4, QThread::idealThreadCount()));
}

ThumbnailProvider::~ThumbnailProvider() {
    // What hasn't started is dropped, and the ffmpegs running are stopped.
    m_pool.clear();
    filmstrips().clear();
    *m_stopping = true;
    m_pool.waitForDone();
    filmstrips().waitForDone();
}

QQuickImageResponse *ThumbnailProvider::requestImageResponse(const QString &id, const QSize &requestedSize) {
    int frame = -1;
    // [frame/<n>/]<when the file last changed>/<percent-encoded path>
    QString path = id;
    if (path.startsWith(QLatin1String("frame/"))) {
        frame = path.section('/', 1, 1).toInt();
        path = path.section('/', 2);
    }
    path = path.section('/', 1);
    auto *response = new Response(QUrl::fromPercentEncoding(path.toUtf8()), requestedSize, frame, m_stopping);
    m_pool.start(response);
    return response;
}

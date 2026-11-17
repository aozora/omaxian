#pragma once

#include <QQuickAsyncImageProvider>
#include <QThreadPool>
#include <atomic>
#include <memory>

// image://thumbnail/<stamp>/<percent-encoded path>: a picture decoded small,
// or a video's poster frame, for the grid; image://thumbnail/frame/<n>/
// <stamp>/<path>, a video's nth preview frame. The stamp is when the file
// last changed. Off the GUI thread, several at a time.
class ThumbnailProvider : public QQuickAsyncImageProvider {
public:
    ThumbnailProvider();
    ~ThumbnailProvider() override;
    QQuickImageResponse *requestImageResponse(const QString &id, const QSize &requestedSize) override;

private:
    QThreadPool m_pool;
    // Set as it goes, so the ffmpegs it started stop rather than outlive it.
    std::shared_ptr<std::atomic_bool> m_stopping = std::make_shared<std::atomic_bool>(false);
};

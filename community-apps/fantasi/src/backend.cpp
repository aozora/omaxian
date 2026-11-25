#include "backend.h"

#include <QClipboard>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFileInfo>
#include <QImageReader>
#include <QMimeData>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrl>
#include <cmath>
#include <utility>

#include "portalfilepicker.h"

Backend::Backend(const Places &places, FilePicker *picker, QObject *parent)
    : QObject(parent), m_models(places.engineState, places.engineKey, places.engineCommand),
      m_generator(&m_models, places.folder, places.music), m_history(m_generator.folder(), m_generator.musicFolder()),
      m_picker(picker ? picker : new PortalFilePicker(this)) {
    connect(&m_generator, &Generator::finished, this, [this] {
        if (m_waitingOpen.isEmpty())
            return;
        const QJsonObject request = std::exchange(m_waitingOpen, {});
        open(request.value("model").toString(), request.value("prompt").toString());
    });
    connect(m_picker, &FilePicker::failed, this, [this](const QString &message) {
        m_saving.clear();
        m_error = message;
        emit errorChanged();
    });
    connect(m_picker, &FilePicker::openSelected, this, [this](const QUrl &url) { emit pictureChosen(url.toString()); });
    connect(m_picker, &FilePicker::saveSelected, this, [this](const QUrl &target) {
        const QString source = std::exchange(m_saving, {});
        QFile in(source);
        QSaveFile out(target.toLocalFile());
        // Never truncate the file in place when its folder takes no
        // temporary file: the save fails instead.
        out.setDirectWriteFallback(false);
        const bool written = in.open(QIODevice::ReadOnly) && out.open(QIODevice::WriteOnly)
                          && out.write(in.readAll()) == in.size() && out.commit();
        m_error = written ? QString() : tr("Couldn't save the image as %1").arg(target.toLocalFile());
        emit errorChanged();
    });

    const QString hyprctl = !places.hyprctl.isEmpty() ? places.hyprctl
                          : !qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE")
                              ? QStandardPaths::findExecutable("hyprctl")
                              : QString();
    if (hyprctl.isEmpty())
        return;
    connect(&m_monitors, &QProcess::finished, this, [this] {
        for (const QJsonValue &value : QJsonDocument::fromJson(m_monitors.readAllStandardOutput()).array()) {
            const QJsonObject monitor = value.toObject();
            if (!monitor.value("focused").toBool())
                continue;
            // A monitor on its side is taller than it is wide.
            const bool turned = monitor.value("transform").toInt() % 2 == 1;
            const int width = monitor.value("width").toInt(), height = monitor.value("height").toInt();
            if (width > 0 && height > 0) {
                m_screenSize = turned ? Generator::fitMegapixel(height, width) : Generator::fitMegapixel(width, height);
                emit screenSizeChanged();
            }
        }
    });
    m_monitors.start(hyprctl, {"-j", "monitors"});
}

void Backend::open(const QString &model, const QString &prompt) {
    // A plain `fantasi` only brings the window to the front.
    if (model.isEmpty() && prompt.isEmpty())
        return;
    // Not in the middle of an image: it is seen to once that one is done.
    if (m_generator.busy()) {
        m_waitingOpen = {{"model", model}, {"prompt", prompt}};
        return;
    }
    if (!model.isEmpty()) {
        m_models.choose(model);
        emit modelRequested();
    }
    if (!prompt.isEmpty())
        emit promptRequested(prompt);
}

void Backend::copy(const QString &url) {
    QFile file(QUrl(url).toLocalFile());
    if (!file.open(QIODevice::ReadOnly))
        return;
    auto *data = new QMimeData;
    // A clip or a song goes on as a file, which chats and file managers
    // take; an image as its picture.
    if (const bool song = file.fileName().endsWith(".mp3"); song || file.fileName().endsWith(".webm")) {
        data->setUrls({QUrl::fromLocalFile(file.fileName())});
        data->setData(song ? "audio/mpeg" : "video/webm", file.readAll());
    } else {
        data->setData("image/png", file.readAll());
    }
    QGuiApplication::clipboard()->setMimeData(data);
}

void Backend::saveAs(const QString &url) {
    const QString path = QUrl(url).toLocalFile();
    if (path.isEmpty())
        return;
    m_saving = path;
    m_error.clear();
    emit errorChanged();
    // The picker starts in Pictures, or Music for a song, with the file's own name.
    const QString folder = QStandardPaths::writableLocation(path.endsWith(".mp3") ? QStandardPaths::MusicLocation
                                                                                  : QStandardPaths::PicturesLocation);
    m_picker->saveImage(QUrl::fromLocalFile(folder + "/" + QFileInfo(path).fileName()));
}

void Backend::openPicture() {
    m_error.clear();
    emit errorChanged();
    m_picker->openImage();
}

bool Backend::isPicture(const QString &url) const {
    const QUrl parsed(url);
    return parsed.isLocalFile() && QImageReader(parsed.toLocalFile()).canRead();
}

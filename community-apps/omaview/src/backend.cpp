#include "backend.h"

#include <QAudioOutput>
#include <QBuffer>
#include <QClipboard>
#include <QDir>
#include <QEventLoopLocker>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonObject>
#include <QLocale>
#include <QMediaMetaData>
#include <QMediaPlayer>
#include <QMutexLocker>
#include <QPointer>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QVideoSink>
#include <QtAudio>
#include <QtConcurrent>
#include <cmath>

#include "filepicker.h"
#include "playlist.h"
#include "portalfilepicker.h"
#include "texts.h"

namespace {

QString clock(qint64 ms) {
    const qint64 total = std::max<qint64>(0, ms / 1000);
    const qint64 hours = total / 3600, minutes = total / 60 % 60, seconds = total % 60;
    return hours > 0 ? QString("%1:%2:%3").arg(hours).arg(minutes, 2, 10, QChar('0')).arg(seconds, 2, 10, QChar('0'))
                     : QString("%1:%2").arg(minutes, 2, 10, QChar('0')).arg(seconds, 2, 10, QChar('0'));
}

// Codec names as people know them, rather than ffmpeg's identifiers.
QString codecName(const probe::Stream &stream) {
    static const QHash<QString, QString> names{
        {"h264", "H.264"}, {"hevc", "HEVC"}, {"av1", "AV1"}, {"vp9", "VP9"}, {"vp8", "VP8"},
        {"mpeg4", "MPEG-4"}, {"mpeg2video", "MPEG-2"}, {"mpeg1video", "MPEG-1"}, {"prores", "ProRes"},
        {"theora", "Theora"}, {"wmv3", "WMV"}, {"aac", "AAC"}, {"opus", "Opus"}, {"vorbis", "Vorbis"},
        {"mp3", "MP3"}, {"flac", "FLAC"}, {"ac3", "Dolby Digital"}, {"eac3", "Dolby Digital Plus"},
        {"truehd", "Dolby TrueHD"}, {"dts", "DTS"}, {"alac", "ALAC"}, {"pcm_s16le", "PCM"},
        {"pcm_s24le", "PCM"}, {"subrip", "SubRip"}, {"ass", "ASS"}, {"ssa", "SSA"}, {"webvtt", "WebVTT"},
        {"mov_text", "MP4 text"}, {"hdmv_pgs_subtitle", "PGS"}, {"dvd_subtitle", "VobSub"},
        {"dvb_subtitle", "DVB"}, {"mjpeg", "JPEG"}, {"png", "PNG"},
    };
    return names.value(stream.codec, stream.codec.toUpper());
}

QString channelName(const probe::Stream &stream) {
    const QString layout = stream.channelLayout.section('(', 0, 0);
    if (layout == "mono" || stream.channels == 1)
        return Texts::tr("mono");
    if (layout == "stereo" || stream.channels == 2)
        return Texts::tr("stereo");
    if (!layout.isEmpty() && layout.front().isDigit())
        return layout;
    return stream.channels > 0 ? QString::number(stream.channels) : QString();
}

QString languageOf(const QMediaMetaData &metadata) {
    const QVariant value = metadata.value(QMediaMetaData::Language);
    if (!value.isValid())
        return {};
    const auto language = value.value<QLocale::Language>();
    if (language == QLocale::AnyLanguage || language == QLocale::C)
        return {};
    return QLocale::languageToCode(language, QLocale::ISO639Part1);
}

QString join(const QStringList &parts) {
    QStringList kept;
    for (const QString &part : parts)
        if (!part.trimmed().isEmpty())
            kept << part.trimmed();
    return kept.join(QStringLiteral(" · "));
}

}  // namespace

Backend::Backend(QObject *parent) : Backend(Options{}, parent) {}

Backend::Backend(const Options &options, QObject *parent)
    : QObject(parent), m_options(options), m_positions(options.positionsPath) {
    if (m_options.picker) {
        m_picker = m_options.picker;
    } else {
        m_ownPicker = std::make_unique<PortalFilePicker>();
        m_picker = m_ownPicker.get();
    }
    connect(m_picker, &FilePicker::openSelected, this, &Backend::openUrls);
    // A frame held for a dialog that went away without saving is let go.
    connect(m_picker, &FilePicker::failed, this, [this](const QString &message) {
        m_pendingFrame = QVideoFrame();
        emit notice(message);
    });
    connect(m_picker, &FilePicker::cancelled, this, [this] { m_pendingFrame = QVideoFrame(); });
    connect(m_picker, &FilePicker::saveSelected, this, [this](const QUrl &url) {
        QVideoFrame frame = m_pendingFrame;
        m_pendingFrame = QVideoFrame();
        if (!frame.isValid())
            return;
        const QString path = url.toLocalFile();
        QPointer<Backend> self(this);
        (void)QtConcurrent::run([self, frame, path]() mutable {
            QEventLoopLocker keepRunning;
            // Converted here, not on the GUI thread: a 4K frame read back from
            // the GPU would stall the picture.
            const QImage image = frame.toImage();
            QString error = image.isNull() ? tr("Could not save this frame.") : QString();
            const bool saved = !image.isNull() && frames::savePng(image, path, &error);
            QMetaObject::invokeMethod(qApp, [self, saved, path, error] {
                if (!self)
                    return;
                emit self->notice(saved ? tr("Saved %1").arg(QFileInfo(path).fileName())
                                        : tr("Could not save the frame: %1").arg(error));
            }, Qt::QueuedConnection);
        });
    });

    // Preferences are read once and kept here; changes are written a moment
    // later on a thread of their own, in order, so a drag of the volume or
    // another window holding the file's lock never stalls the picture.
    m_writer.setMaxThreadCount(1);
    m_preferences = m_positions.preferences();
    if (!QStandardPaths::findExecutable("wpctl").isEmpty())
        m_maxVolume = 1.5;
    m_volume = std::clamp(m_preferences.value("volume").toDouble(1.0), 0.0, m_maxVolume);
    // A new stream starts at its own level, so a boost is set again once it
    // plays, and a drag of the volume asks PipeWire once it pauses.
    m_boostTimer.setSingleShot(true);
    connect(&m_boostTimer, &QTimer::timeout, this, &Backend::applyBoost);
    m_muted = m_preferences.value("muted").toBool(false);
    m_preferenceTimer.setSingleShot(true);
    m_preferenceTimer.setInterval(500);
    connect(&m_preferenceTimer, &QTimer::timeout, this, &Backend::writePreferences);

    // A picture changed on disk, as an editor saves it, is read again once
    // the writing has settled, so a half-written file is never shown.
    m_changedTimer.setSingleShot(true);
    m_changedTimer.setInterval(300);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString &path) {
        if (m_picture && path == filePath())
            m_changedTimer.start();
    });
    connect(&m_changedTimer, &QTimer::timeout, this, [this] {
        const QString path = filePath();
        if (!m_picture || !QFileInfo::exists(path))
            return;
        // Saving by renaming over the file ends the watch, so it is set again.
        if (!m_watcher.files().contains(path))
            m_watcher.addPath(path);
        ++m_revision;
        readPicture();
        emit pictureChanged();
    });

    m_previewTimer.setSingleShot(true);
    m_previewTimer.setInterval(m_options.previewDelayMs);
    connect(&m_previewTimer, &QTimer::timeout, this, &Backend::startPreviews);
    // The player tells what it knows about a file in its own order, so the
    // previews start when the last of what they need arrives.
    for (auto signal : {&Backend::seekableChanged, &Backend::hasVideoChanged, &Backend::durationChanged,
                        &Backend::videoSizeChanged, &Backend::infoChanged})
        connect(this, signal, this, [this] {
            if (m_previewsWanted && !m_previewTimer.isActive())
                m_previewTimer.start();
        });
    connect(&m_previews, &frames::Previews::ready, this,
            [this](const QString &path, const frames::PreviewLayout &layout) {
                m_previewSource = QUrl::fromLocalFile(path);
                m_previewLayout = layout;
                emit previewsChanged();
            });
}

Backend::~Backend() {
    m_previews.cancel();
    if (m_cancel)
        *m_cancel = true;
    flush();
    if (m_player) {
        // No frame may reach a backend that is going: detach the sink before
        // the decoder's thread can call into it again.
        m_sink->disconnect(this);
        m_player->disconnect(this);
        m_player->setVideoSink(nullptr);
        m_player->stop();
    }
}

void Backend::setLanguage(const QString &language) {
    m_language = language.section('-', 0, 0);
    // What C++ translated and kept is translated again.
    if (m_tracksChosen)
        labelTracks();
    if (hasMedia())
        buildInfo();
    emit tracksChanged();
    emit infoChanged();
    emit metadataChanged();
    emit errorChanged();
}

QString Backend::fileName() const {
    if (m_source.isEmpty())
        return {};
    return m_source.isLocalFile() ? QFileInfo(m_source.toLocalFile()).fileName() : m_source.toString();
}

QString Backend::title() const {
    return !m_title.isEmpty() ? m_title : fileName();
}

bool Backend::playing() const {
    return m_player && m_player->playbackState() == QMediaPlayer::PlayingState;
}

bool Backend::loading() const {
    return m_player && m_player->mediaStatus() == QMediaPlayer::LoadingMedia;
}

QString Backend::nextName() const {
    if (m_index < 0 || m_index + 1 >= m_playlist.size())
        return {};
    const QString next = m_playlist.at(m_index + 1);
    const QUrl url = QUrl::fromUserInput(next, QDir::currentPath(), QUrl::AssumeLocalFile);
    return url.isLocalFile() ? QFileInfo(url.toLocalFile()).fileName() : next;
}

bool Backend::canEdit() const {
    // Looked for once: bindings ask on every file.
    static const bool omasnap = !QStandardPaths::findExecutable("omasnap").isEmpty();
    static const bool omacut = !QStandardPaths::findExecutable("omacut").isEmpty();
    return m_source.isLocalFile() && (m_picture ? omasnap : omacut);
}

QUrl Backend::pictureSource() const {
    // A local picture waits for its header, so one Qt can't read is said so
    // in plain words rather than handed to the window to fail on.
    if (!m_picture || m_problem != Problem::None || (m_source.isLocalFile() && m_pictureInfo.format.isEmpty()))
        return {};
    // A fragment of its own makes Qt Quick read a changed file again rather
    // than show the copy it cached; a local file is read without it.
    QUrl url = m_source;
    if (m_revision > 0)
        url.setFragment(QStringLiteral("r%1").arg(m_revision));
    return url;
}

QString Backend::subtitleLabel() const {
    if (m_subtitleChoice < 0 || m_subtitleChoice >= m_subtitleChoices.size())
        return {};
    return m_subtitleChoices.at(m_subtitleChoice).label;
}

QString Backend::audioLabel() const {
    if (m_audioTrack < 0 || m_audioTrack >= m_audioLabels.size())
        return {};
    return m_audioLabels.at(m_audioTrack);
}

void Backend::ensurePlayer() {
    if (m_player)
        return;
    m_player = new QMediaPlayer(this);
    if (m_options.audio) {
        m_audio = new QAudioOutput(this);
        m_player->setAudioOutput(m_audio);
        applyVolume();
    }
    // The player draws into a sink of ours, which hands each frame on to the
    // window's and keeps the subtitle text, so the window draws embedded and
    // sidecar subtitles in one style and the frame on screen is at hand.
    m_sink = new QVideoSink(this);
    m_player->setVideoSink(m_sink);
    // Frames are handed on from the decoder's thread, as Qt's own player
    // hands them to a VideoOutput, so a busy GUI thread never makes the
    // picture stutter. The sink shares the window's GPU context (setRhi), so
    // a frame decoded on the GPU stays there.
    m_sink->setRhi(m_rhi.load());
    connect(
        m_sink, &QVideoSink::videoFrameChanged, this,
        [this](const QVideoFrame &frame) {
            // The player clears the sink at the end of a file; the last frame
            // stays on screen instead, and a new file clears it in load().
            if (!frame.isValid())
                return;
            QSize size;
            bool upright = false;
            quint64 generation;
            {
                QMutexLocker locker(&m_frameLock);
                generation = m_generation;
                m_frame = frame;
                if (frame.size() != m_frameSize) {
                    size = m_frameSize = frame.size();
                    // A phone's portrait clip is stored on its side, and turned
                    // as it's shown: its size is the turned one. Qt gives the
                    // turn on the frame, or in the file's metadata, which the
                    // GUI thread reads as it takes the size.
                    if (frame.rotation() == QtVideo::Rotation::Clockwise90
                        || frame.rotation() == QtVideo::Rotation::Clockwise270)
                        size.transpose();
                    else
                        upright = true;
                }
            }
            // Its own lock, never held with the frame's: the window's sink
            // may wait on the GUI thread, which takes the frame's lock to
            // read the frame on screen.
            {
                QMutexLocker locker(&m_outputLock);
                if (m_output)
                    m_output->setVideoFrame(frame);
            }
            if (size.isValid())
                QMetaObject::invokeMethod(this, [this, size, upright, generation]() mutable {
                    if (generation != m_generation)
                        return;
                    if (upright && m_videoTurned)
                        size.transpose();
                    if (size != m_videoSize) {
                        m_videoSize = size;
                        emit videoSizeChanged();
                    }
                }, Qt::QueuedConnection);
        },
        Qt::DirectConnection);
    connect(m_sink, &QVideoSink::subtitleTextChanged, this, [this](const QString &text) {
        m_embeddedText = text;
        updateSubtitleText();
    });

    connect(m_player, &QMediaPlayer::playbackStateChanged, this, [this] {
        if (playing() && m_heldBehindGrid) {
            m_heldBehindGrid = false;
            m_previewsWanted = m_options.previews && m_loaded;
            if (m_previewsWanted)
                m_previewTimer.start();
        }
        if (playing() && (m_boosted || m_volume > 1.0)) {
            m_boostAgain = true;
            m_boostTimer.start(250);
        }
        emit playingChanged();
    });
    connect(m_player, &QMediaPlayer::mediaStatusChanged, this, &Backend::onStatus);
    connect(m_player, &QMediaPlayer::positionChanged, this, [this](qint64 ms) {
        if (m_ended && m_player->mediaStatus() == QMediaPlayer::EndOfMedia)
            return;
        m_position = ms;
        emit positionChanged();
        updateSubtitleText();
        updateChapter();
    });
    connect(m_player, &QMediaPlayer::durationChanged, this, [this](qint64 ms) {
        m_duration = ms;
        emit durationChanged();
    });
    connect(m_player, &QMediaPlayer::seekableChanged, this, [this](bool seekable) {
        m_seekable = seekable;
        emit seekableChanged();
    });
    connect(m_player, &QMediaPlayer::hasVideoChanged, this, [this](bool video) {
        m_hasVideo = video;
        emit hasVideoChanged();
    });
    connect(m_player, &QMediaPlayer::tracksChanged, this, &Backend::onTracks);
    connect(m_player, &QMediaPlayer::metaDataChanged, this, &Backend::updateMetadata);
    // Qt's own messages are English and technical, so the window says it in
    // its own words; the detail goes to the log for whoever looks.
    connect(m_player, &QMediaPlayer::errorOccurred, this, [this](QMediaPlayer::Error error, const QString &message) {
        if (error == QMediaPlayer::NoError)
            return;
        qWarning("omaview: %s", qPrintable(message));
        setError(error == QMediaPlayer::FormatError          ? Problem::Format
                 : error == QMediaPlayer::AccessDeniedError  ? Problem::Access
                                                             : Problem::Unplayable);
    });
    // Omaxian: pitch compensation is Qt 6.10+. Pre-built binaries target
    // Excalibur's Qt 6.8, where sped-up playback changes pitch.
#if QT_VERSION >= QT_VERSION_CHECK(6, 10, 0)
    if (m_player->pitchCompensationAvailability() != QMediaPlayer::PitchCompensationAvailability::Unavailable)
        m_player->setPitchCompensation(true);
#endif
    emit playerReadyChanged();
}

void Backend::setVideoSink(QVideoSink *sink) {
    // The VideoOutput detaches itself as its destruction begins, before its
    // sink is torn down; the lock waits out a frame being handed over.
    const QVideoFrame frame = currentFrame();
    QMutexLocker locker(&m_outputLock);
    m_output = sink;
    if (m_output && frame.isValid())
        m_output->setVideoFrame(frame);
}

void Backend::setRhi(QRhi *rhi) {
    // Called on the render thread as the scene graph comes and goes, as Qt's
    // own VideoOutput sets its sink's.
    m_rhi = rhi;
    if (m_sink)
        m_sink->setRhi(rhi);
}

void Backend::open(const QStringList &arguments) {
    // Whatever was opened last wins over a folder still being listed.
    const quint64 list = ++m_listGeneration;
    // Files only: a URL is a stream, which is mpv's job.
    QStringList paths;
    bool folder = false;
    for (const QString &argument : arguments) {
        const QUrl url = QUrl::fromUserInput(argument, QDir::currentPath(), QUrl::AssumeLocalFile);
        if (!url.isLocalFile())
            continue;
        const QFileInfo file(url.toLocalFile());
        paths << file.absoluteFilePath();
        folder = folder || file.isDir();
    }
    if (!folder) {
        openItems(paths, false);
        return;
    }
    // A folder is its files, shown as the grid, and listed in the background
    // so a big or slow one never holds up the window.
    QPointer<Backend> self(this);
    (void)QtConcurrent::run([self, paths, list] {
        QEventLoopLocker keepRunning;
        QStringList items;
        for (const QString &path : paths)
            items << (QFileInfo(path).isDir() ? playlist::folder(path) : QStringList{path});
        QMetaObject::invokeMethod(qApp, [self, items, list] {
            if (self && self->m_listGeneration == list)
                self->openItems(items, true);
        }, Qt::QueuedConnection);
    });
}

void Backend::openItems(const QStringList &items, bool folder) {
    if (items.isEmpty()) {
        emit nothingToOpen();
        return;
    }
    rememberPosition();
    m_playlist = items;
    m_index = -1;
    m_holdPlayback = folder;
    load(0);
    if (folder)
        emit folderOpened();
    // One file brings its folder, which is listed in the background so a big
    // or slow folder never holds up the picture.
    if (items.size() == 1 && !folder && m_source.isLocalFile()) {
        const QString file = items.first();
        const quint64 list = ++m_listGeneration;
        QPointer<Backend> self(this);
        (void)QtConcurrent::run([self, file, list] {
            QEventLoopLocker keepRunning;
            const QStringList siblings = playlist::siblings(file);
            QMetaObject::invokeMethod(qApp, [self, file, list, siblings] {
                if (!self || self->m_listGeneration != list || self->m_playlist != QStringList{file})
                    return;
                self->m_playlist = siblings;
                self->m_index = std::max<int>(0, int(siblings.indexOf(file)));
                emit self->playlistChanged();
            }, Qt::QueuedConnection);
        });
    }
}

void Backend::openUrls(const QList<QUrl> &urls) {
    QStringList items;
    for (const QUrl &url : urls)
        if (url.isLocalFile())
            items << url.toLocalFile();
    open(items);
}

void Backend::openDialog() {
    m_picker->openMedia();
}

// What the last file left behind, cleared before the next one, whatever it
// is.
void Backend::resetFile() {
    m_previews.cancel();
    m_previewTimer.stop();
    m_previewsWanted = false;
    // Work for the last file stops: its ffprobe and subtitle extractions.
    if (m_cancel)
        *m_cancel = true;
    m_cancel = std::make_shared<std::atomic_bool>(false);
    m_title.clear();
    m_artist.clear();
    m_coverArt.clear();
    m_problem = Problem::None;
    m_stopped = false;
    m_position = 0;
    m_ended = false;
    m_loaded = false;
    // hasVideo stays as the player has it: Qt says only when it changes, so a
    // second video after a first would never say so again. onStatus() syncs
    // it once the new file has loaded.
    // Under the frame's lock, so a frame from the last file is measured as
    // the last file's, and its size, still on its way, is dropped.
    {
        QMutexLocker locker(&m_frameLock);
        ++m_generation;
        m_frame = QVideoFrame();
        m_frameSize = QSize();
    }
    // Omaxian: on Qt 6.8 (no KeepLastFrame) an empty frame clears the
    // picture. On 6.9+ KeepLastFrame ignores it, so the window clears it too.
    {
        QMutexLocker locker(&m_outputLock);
        if (m_output)
            m_output->setVideoFrame(QVideoFrame());
    }
    // KeepLastFrame ignores an empty frame, so the window clears it itself.
    emit pictureCleared();
    m_videoSize = QSize();
    m_videoTurned = false;
    m_probe = probe::Info();
    m_probed = false;
    m_tracksReady = false;
    m_tracksChosen = false;
    m_pendingResume = -1;
    m_resumedAt = -1;
    m_sidecars.clear();
    m_subtitleChoices.clear();
    m_subtitleChoice = -1;
    m_cues.clear();
    m_embeddedText.clear();
    m_subtitleText.clear();
    m_audioLabels.clear();
    m_audioLanguages.clear();
    m_audioTrack = -1;
    m_chapters.clear();
    m_chapterList.clear();
    m_chapterTitle.clear();
    m_info.clear();
    m_previewSource.clear();
    m_previewLayout = frames::PreviewLayout();
    m_picture = false;
    m_pictureInfo = picture::Info();
    m_rotation = 0;
    m_revision = 0;
    m_changedTimer.stop();
    if (!m_watcher.files().isEmpty())
        m_watcher.removePaths(m_watcher.files());
}

void Backend::load(int index) {
    if (index < 0 || index >= m_playlist.size())
        return;
    m_index = index;
    // Only the file a folder opens on waits; whatever loads first, picture
    // or video, uses the hold up.
    const bool hold = std::exchange(m_holdPlayback, false);
    const QString item = m_playlist.at(index);
    if (playlist::picture(item)) {
        loadPicture(item);
        return;
    }
    ensurePlayer();
    resetFile();
    m_source = QUrl::fromUserInput(item, QDir::currentPath(), QUrl::AssumeLocalFile);

    if (m_source.isLocalFile()) {
        const QString path = m_source.toLocalFile();
        if (!QFileInfo(path).isReadable()) {
            m_player->setSource(QUrl());
            m_problem = QFileInfo::exists(path) ? Problem::Unreadable : Problem::Missing;
            buildInfo();
            emitFileChanged();
            return;
        }
        m_pendingResume = m_positions.lookup(path);
        // ffprobe and the look for subtitle files beside it run beside the
        // player's own opening of the file, so chapters and track details
        // arrive without holding up the picture.
        const quint64 generation = m_generation;
        const auto cancelled = m_cancel;
        QPointer<Backend> self(this);
        (void)QtConcurrent::run([self, path, generation, cancelled] {
            QEventLoopLocker keepRunning;
            const probe::Info info = probe::run(path, 15000, cancelled.get());
            const QList<subtitles::Sidecar> sidecars = subtitles::find(path);
            QMetaObject::invokeMethod(qApp, [self, info, sidecars, generation] {
                if (self)
                    self->onProbed(info, sidecars, generation);
            }, Qt::QueuedConnection);
        });
    } else {
        m_probed = true;
    }

    // Setting the source the player already has does nothing, so reopening
    // the same file clears it first.
    if (m_player->source() == m_source)
        m_player->setSource(QUrl());
    m_player->setSource(m_source);
    m_player->setLoops(m_looping ? QMediaPlayer::Infinite : QMediaPlayer::Once);
    m_player->setPlaybackRate(m_rate);
    emitFileChanged();
    // A folder opens on its grid, so its first video waits, paused, until
    // it's picked.
    m_heldBehindGrid = hold;
    if (hold)
        m_player->pause();
    else
        m_player->play();
}

// A picture never starts the player: one already playing a video stops and
// lets the file go.
void Backend::loadPicture(const QString &item) {
    resetFile();
    m_source = QUrl::fromUserInput(item, QDir::currentPath(), QUrl::AssumeLocalFile);
    m_picture = true;
    if (m_player) {
        m_player->stop();
        m_player->setSource(QUrl());
    }
    // The player doesn't always say these went with its file; onStatus()
    // takes them from it again when the next video loads.
    m_duration = 0;
    m_seekable = false;
    m_hasVideo = false;
    if (m_source.isLocalFile()) {
        const QString path = m_source.toLocalFile();
        if (!QFileInfo(path).isReadable()) {
            m_problem = QFileInfo::exists(path) ? Problem::Unreadable : Problem::Missing;
        } else {
            m_watcher.addPath(path);
            readPicture();
        }
    }
    buildInfo();
    emitFileChanged();
}

void Backend::readPicture() {
    const QString path = filePath();
    const quint64 generation = m_generation;
    const int revision = m_revision;
    QPointer<Backend> self(this);
    (void)QtConcurrent::run([self, path, generation, revision] {
        QEventLoopLocker keepRunning;
        const picture::Info info = picture::read(path);
        QMetaObject::invokeMethod(qApp, [self, info, generation, revision] {
            if (self)
                self->onPictureRead(info, generation, revision);
        }, Qt::QueuedConnection);
    });
}

// Only the latest read of the latest save counts: two reads of a file an
// editor saved twice can finish in either order.
void Backend::onPictureRead(const picture::Info &info, quint64 generation, int revision) {
    if (generation != m_generation || revision != m_revision || !m_picture)
        return;
    m_pictureInfo = info;
    if (!info.ok())
        setError(Problem::PictureFormat);
    else if ((m_problem == Problem::PictureBroken || m_problem == Problem::PictureFormat) && m_revision > 0)
        setError(Problem::None);  // an editor has finished writing it
    buildInfo();
    emit pictureChanged();
    emit infoChanged();
    emit metadataChanged();
}

void Backend::pictureFailed() {
    if (m_picture && m_problem == Problem::None)
        setError(Problem::PictureBroken);
}

// Nothing open: the last file went to the Trash.
void Backend::clear() {
    resetFile();
    if (m_player) {
        m_player->stop();
        m_player->setSource(QUrl());
    }
    m_source = QUrl();
    m_playlist.clear();
    m_index = -1;
    emitFileChanged();
}

// Everything a new file changes, said once, whichever way load() ended.
void Backend::emitFileChanged() {
    emit mediaChanged();
    emit metadataChanged();
    emit errorChanged();
    emit positionChanged();
    emit durationChanged();
    emit seekableChanged();
    emit hasVideoChanged();
    emit statusChanged();
    emit playingChanged();
    emit subtitleTextChanged();
    emit tracksChanged();
    emit chapterChanged();
    emit infoChanged();
    emit playlistChanged();
    emit previewsChanged();
    emit pictureChanged();
    emit rotationChanged();
}

void Backend::setError(Problem problem) {
    if (m_problem == problem)
        return;
    m_problem = problem;
    emit errorChanged();
}

QString Backend::error() const {
    const QString name = fileName();
    switch (m_problem) {
    case Problem::None: return {};
    case Problem::Missing: return tr("%1 doesn't exist.").arg(name);
    case Problem::Unreadable: return tr("%1 can't be read.").arg(name);
    case Problem::Format: return tr("Its format or codec isn't one ffmpeg can play.");
    case Problem::Access: return tr("Permission to open it was denied.");
    case Problem::PictureFormat: return tr("Its format isn't one Omaview can show.");
    case Problem::PictureBroken: return tr("This picture could not be shown.");
    case Problem::Unplayable: break;
    }
    return tr("This file could not be played.");
}

void Backend::onStatus() {
    const auto status = m_player->mediaStatus();
    if (status == QMediaPlayer::LoadedMedia || status == QMediaPlayer::BufferedMedia) {
        if (!m_loaded) {
            m_loaded = true;
            if (m_hasVideo != m_player->hasVideo()) {
                m_hasVideo = m_player->hasVideo();
                emit hasVideoChanged();
            }
            // Nor do these when a picture came between two videos as long.
            if (m_duration != m_player->duration()) {
                m_duration = m_player->duration();
                emit durationChanged();
            }
            if (m_seekable != m_player->isSeekable()) {
                m_seekable = m_player->isSeekable();
                emit seekableChanged();
            }
            if (m_pendingResume > 0 && m_player->isSeekable()) {
                m_resumedAt = m_pendingResume;
                // A few seconds back, so the sentence that was interrupted
                // starts again.
                const qint64 target = std::max<qint64>(0, m_pendingResume - 3000);
                m_player->setPosition(target);
                emit seeked(target);
            }
            m_pendingResume = -1;
            // A folder's first video, waiting behind its grid, makes its
            // previews only once it is picked and plays.
            m_previewsWanted = m_options.previews && m_source.isLocalFile() && !m_heldBehindGrid;
            if (m_previewsWanted)
                m_previewTimer.start();
        }
    } else if (status == QMediaPlayer::EndOfMedia) {
        m_ended = true;
        m_position = m_duration;
        emit positionChanged();
        rememberPosition();
    } else if (status == QMediaPlayer::InvalidMedia) {
        if (m_problem == Problem::None)
            setError(Problem::Unplayable);
    }
    emit statusChanged();
}

void Backend::onProbed(const probe::Info &info, const QList<subtitles::Sidecar> &sidecars, quint64 generation) {
    if (generation != m_generation)
        return;
    m_probe = info;
    m_sidecars = sidecars;
    m_probed = true;
    // Without ffprobe the picture plays but chapters and subtitles can't be
    // offered, which the window says rather than quietly doing less.
    if (info.missingTool)
        emit notice(info.error);
    m_chapters.clear();
    m_chapterList.clear();
    for (const probe::Chapter &chapter : m_probe.chapters) {
        const qint64 start = qint64(chapter.start * 1000);
        m_chapters << QVariantMap{{"start", start}, {"title", chapter.title}};
        m_chapterList.push_back({start, chapter.title});
    }
    updateChapter();
    if (m_title.isEmpty() && !m_probe.title.isEmpty())
        m_title = m_probe.title;
    if (m_artist.isEmpty() && !m_probe.artist.isEmpty())
        m_artist = m_probe.artist;
    buildInfo();
    emit metadataChanged();
    emit infoChanged();
    chooseTracks();
}

void Backend::onTracks() {
    m_tracksReady = true;
    chooseTracks();
}

void Backend::chooseTracks() {
    if (!m_player || !m_tracksReady || !m_probed || m_tracksChosen)
        return;
    m_tracksChosen = true;

    // Subtitles: only text tracks, which Qt's subtitle path can show, then
    // the files beside the video.
    const QList<QMediaMetaData> embedded = m_player->subtitleTracks();
    const QList<probe::Stream> probedSubtitles = m_probe.ofType("subtitle");
    m_subtitleChoices.clear();
    for (int i = 0; i < embedded.size(); ++i) {
        // Without ffprobe's word on the codec, a bitmap track can't be ruled
        // out, so none are offered.
        if (i >= probedSubtitles.size() || !probedSubtitles.at(i).textSubtitle())
            continue;
        SubtitleChoice choice;
        choice.embedded = i;
        choice.language = languageOf(embedded.at(i));
        if (choice.language.isEmpty())
            choice.language = probe::shortLanguage(probedSubtitles.at(i).language);
        m_subtitleChoices << choice;
    }
    for (int i = 0; i < m_sidecars.size(); ++i) {
        SubtitleChoice choice;
        choice.sidecar = i;
        choice.language = probe::shortLanguage(m_sidecars.at(i).language);
        m_subtitleChoices << choice;
    }
    labelTracks();

    const QString audioPreference = m_preferences.value("audioLanguage").toString();
    int track = m_player->activeAudioTrack();
    for (const QString &wanted : {audioPreference, m_language}) {
        if (wanted.isEmpty())
            continue;
        const int found = int(m_audioLanguages.indexOf(wanted));
        if (found >= 0) {
            track = found;
            break;
        }
    }
    if (!m_audioLabels.isEmpty())
        applyAudio(std::clamp(track, 0, int(m_audioLabels.size()) - 1), false);

    // Subtitles start off, unless they were on last time in a language this
    // file has, or the film speaks another language and has the reader's.
    const QString subtitlePreference = m_preferences.value("subtitleLanguage").toString();
    int subtitle = -1;
    auto find = [&](const QString &language) {
        for (int i = 0; i < m_subtitleChoices.size(); ++i)
            if (m_subtitleChoices.at(i).language == language)
                return i;
        return -1;
    };
    if (!subtitlePreference.isEmpty() && subtitlePreference != "off") {
        subtitle = find(subtitlePreference);
    } else if (subtitlePreference.isEmpty()) {
        const QString spoken = m_audioTrack >= 0 ? m_audioLanguages.value(m_audioTrack) : QString();
        if (!spoken.isEmpty() && spoken != m_language)
            subtitle = find(m_language);
    }
    applySubtitle(subtitle, false);
    buildInfo();
    emit tracksChanged();
    emit infoChanged();
}

// The names the tracks are listed under, which a language switch redoes.
void Backend::labelTracks() {
    // Audio: Qt's tracks named by Qt's metadata, with ffprobe's details,
    // matched by order within the type.
    const QList<QMediaMetaData> audio = m_player->audioTracks();
    const QList<probe::Stream> probedAudio = m_probe.ofType("audio");
    m_audioLabels.clear();
    m_audioLanguages.clear();
    for (int i = 0; i < audio.size(); ++i) {
        QString language = languageOf(audio.at(i));
        QString title = audio.at(i).value(QMediaMetaData::Title).toString();
        QString channels;
        if (i < probedAudio.size()) {
            if (language.isEmpty())
                language = probe::shortLanguage(probedAudio.at(i).language);
            if (title.isEmpty())
                title = probedAudio.at(i).title;
            channels = channelName(probedAudio.at(i));
        }
        QString label = join({probe::languageName(language), title, channels});
        if (label.isEmpty())
            label = tr("Track %1").arg(i + 1);
        m_audioLabels << label;
        m_audioLanguages << language;
    }

    const QList<QMediaMetaData> embedded = m_player->subtitleTracks();
    const QList<probe::Stream> probedSubtitles = m_probe.ofType("subtitle");
    for (SubtitleChoice &choice : m_subtitleChoices) {
        if (choice.sidecar >= 0) {
            choice.label = m_sidecars.at(choice.sidecar).label;
            continue;
        }
        QString title = embedded.value(choice.embedded).value(QMediaMetaData::Title).toString();
        if (title.isEmpty() && choice.embedded < probedSubtitles.size())
            title = probedSubtitles.at(choice.embedded).title;
        choice.label = join({probe::languageName(choice.language), title});
        if (choice.label.isEmpty())
            choice.label = tr("Subtitles %1").arg(choice.embedded + 1);
    }
}

void Backend::applyAudio(int track, bool remember) {
    if (!m_player || track < 0 || track >= m_audioLabels.size())
        return;
    m_audioTrack = track;
    if (m_player->activeAudioTrack() != track)
        m_player->setActiveAudioTrack(track);
    if (remember && !m_audioLanguages.at(track).isEmpty())
        setPreference("audioLanguage", m_audioLanguages.at(track));
    emit tracksChanged();
}

void Backend::applySubtitle(int index, bool remember) {
    if (!m_player)
        return;
    m_subtitleChoice = index >= 0 && index < m_subtitleChoices.size() ? index : -1;
    m_cues.clear();
    m_embeddedText.clear();
    if (m_subtitleChoice < 0) {
        m_player->setActiveSubtitleTrack(-1);
        if (remember)
            setPreference("subtitleLanguage", "off");
    } else {
        const SubtitleChoice &choice = m_subtitleChoices.at(m_subtitleChoice);
        // An embedded track shows through Qt at once, which only shows a cue
        // when playback reaches its start; its cues are read out in the
        // background too, and once they are in, the window draws them itself,
        // so a seek into the middle of a line shows the line.
        m_player->setActiveSubtitleTrack(choice.embedded);
        loadCues(m_subtitleChoice);
        if (remember && !choice.language.isEmpty())
            setPreference("subtitleLanguage", choice.language);
    }
    updateSubtitleText();
    emit tracksChanged();
}

void Backend::loadCues(int index) {
    SubtitleChoice &choice = m_subtitleChoices[index];
    if (choice.cuesLoaded) {
        m_cues = choice.cues;
        if (choice.embedded >= 0)
            m_player->setActiveSubtitleTrack(-1);
        return;
    }
    if (choice.cuesLoading)
        return;
    const bool embedded = choice.embedded >= 0;
    const QString path = embedded ? m_source.toLocalFile() : m_sidecars.at(choice.sidecar).path;
    // ffmpeg's 0:s:N counts subtitle streams the way Qt numbers its tracks.
    const int stream = embedded ? choice.embedded : 0;
    if (path.isEmpty())
        return;
    choice.cuesLoading = true;
    const quint64 generation = m_generation;
    const auto cancelled = m_cancel;
    QPointer<Backend> self(this);
    (void)QtConcurrent::run([self, path, stream, generation, index, embedded, cancelled] {
        QEventLoopLocker keepRunning;
        QString error;
        const QList<subtitles::Cue> cues = subtitles::load(path, stream, &error, cancelled.get());
        QMetaObject::invokeMethod(qApp, [self, cues, error, generation, index, embedded] {
            if (!self || self->m_generation != generation || index >= self->m_subtitleChoices.size())
                return;
            SubtitleChoice &choice = self->m_subtitleChoices[index];
            choice.cuesLoading = false;
            // An embedded track whose cues couldn't be read stays with Qt.
            if (embedded && cues.isEmpty())
                return;
            choice.cues = cues;
            choice.cuesLoaded = true;
            if (self->m_subtitleChoice != index)
                return;
            self->m_cues = cues;
            if (embedded)
                self->m_player->setActiveSubtitleTrack(-1);
            if (cues.isEmpty() && !error.isEmpty())
                emit self->notice(error);
            self->updateSubtitleText();
        }, Qt::QueuedConnection);
    });
}


void Backend::updateSubtitleText() {
    QString text;
    if (m_subtitleChoice >= 0 && m_subtitleChoice < m_subtitleChoices.size()) {
        const SubtitleChoice &choice = m_subtitleChoices.at(m_subtitleChoice);
        text = choice.sidecar >= 0 || choice.cuesLoaded ? subtitles::at(m_cues, m_position) : m_embeddedText;
    }
    if (text != m_subtitleText) {
        m_subtitleText = text;
        emit subtitleTextChanged();
    }
}

void Backend::updateChapter() {
    const QString title = chapterAt(m_position);
    if (title != m_chapterTitle) {
        m_chapterTitle = title;
        emit chapterChanged();
    }
}

QString Backend::chapterAt(qint64 ms) const {
    // Asked on every position update, so it walks plain values.
    QString title;
    for (const auto &[start, name] : m_chapterList) {
        if (start > ms)
            break;
        title = name;
    }
    return title;
}

void Backend::updateMetadata() {
    if (!m_player)
        return;
    const QMediaMetaData metadata = m_player->metaData();
    const QString title = metadata.stringValue(QMediaMetaData::Title);
    if (!title.isEmpty())
        m_title = title;
    QString artist = metadata.stringValue(QMediaMetaData::ContributingArtist);
    if (artist.isEmpty())
        artist = metadata.stringValue(QMediaMetaData::AlbumArtist);
    if (!artist.isEmpty())
        m_artist = artist;
    QImage cover = metadata.value(QMediaMetaData::CoverArtImage).value<QImage>();
    // Omaxian: Qt 6.8's FFmpeg backend gives an attached picture as the
    // thumbnail instead.
    if (cover.isNull())
        cover = metadata.value(QMediaMetaData::ThumbnailImage).value<QImage>();
    if (!cover.isNull()) {
        // Small enough to hand QML as a data URL, which needs no provider
        // whose lifetime has to outlast the engine's.
        if (cover.width() > 1024 || cover.height() > 1024)
            cover = cover.scaled(1024, 1024, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        QByteArray bytes;
        QBuffer buffer(&bytes);
        buffer.open(QIODevice::WriteOnly);
        cover.save(&buffer, "JPG", 90);
        m_coverArt = "data:image/jpeg;base64," + QString::fromLatin1(bytes.toBase64());
    }
    QSize resolution = metadata.value(QMediaMetaData::Resolution).toSize();
    m_videoTurned = std::abs(metadata.value(QMediaMetaData::Orientation).toInt()) % 180 == 90;
    if (m_videoTurned) {
        // A frame that came first was measured before the turn was known.
        if (!m_videoSize.isEmpty() && m_videoSize == resolution) {
            m_videoSize.transpose();
            emit videoSizeChanged();
        }
        resolution.transpose();
    }
    if (resolution.isValid() && m_videoSize.isEmpty() && m_player->hasVideo()) {
        m_videoSize = resolution;
        emit videoSizeChanged();
    }
    emit metadataChanged();
}

void Backend::buildInfo() {
    m_info.clear();
    auto row = [this](const QString &label, const QString &value) {
        if (!value.isEmpty())
            m_info << QVariantMap{{"label", label}, {"value", value}};
    };
    const QLocale locale;
    row(tr("File"), fileName());
    if (m_picture) {
        buildPictureInfo(row);
        return;
    }
    if (!m_probe.ok()) {
        row(tr("Problem"), m_probe.error);
        return;
    }
    row(tr("Title"), m_probe.title);
    row(tr("Container"), m_probe.format);
    if (m_probe.duration > 0)
        row(tr("Duration"), clock(qint64(m_probe.duration * 1000)));
    if (m_probe.size > 0)
        row(tr("Size"), locale.formattedDataSize(m_probe.size));
    if (m_probe.bitRate > 0)
        row(tr("Bit rate"), tr("%1 kb/s").arg(locale.toString(m_probe.bitRate / 1000)));

    int audioIndex = 0, subtitleIndex = 0;
    for (const probe::Stream &stream : m_probe.streams) {
        if (stream.type == "video" && !stream.attachedPicture) {
            QStringList parts{codecName(stream)};
            if (stream.width > 0)
                parts << QString("%1 × %2").arg(stream.width).arg(stream.height);
            if (stream.frameRate > 0)
                parts << tr("%1 fps").arg(locale.toString(stream.frameRate, 'f', stream.frameRate == std::floor(stream.frameRate) ? 0 : 3));
            row(tr("Video"), join(parts));
        } else if (stream.type == "audio") {
            ++audioIndex;
            row(tr("Audio %1").arg(audioIndex),
                join({probe::languageName(stream.language), stream.title, codecName(stream), channelName(stream)}));
        } else if (stream.type == "subtitle") {
            ++subtitleIndex;
            row(tr("Subtitles %1").arg(subtitleIndex),
                join({probe::languageName(stream.language), stream.title, codecName(stream),
                      stream.textSubtitle() ? QString() : tr("not supported")}));
        }
    }
    for (const subtitles::Sidecar &sidecar : m_sidecars)
        row(tr("Subtitle file"), QFileInfo(sidecar.path).fileName());
    if (!m_probe.chapters.isEmpty())
        row(tr("Chapters"), QString::number(m_probe.chapters.size()));
}

template <typename Row>
void Backend::buildPictureInfo(Row row) {
    const picture::Info &info = m_pictureInfo;
    if (info.format.isEmpty())
        return;
    const QLocale locale;
    const QString dimensions = QString("%1 × %2").arg(info.size.width()).arg(info.size.height());
    const double megapixels = double(info.size.width()) * info.size.height() / 1e6;
    row(tr("Format"), info.format);
    row(tr("Dimensions"), info.vector || megapixels < 0.1
                              ? dimensions
                              : join({dimensions, tr("%1 MP").arg(locale.toString(megapixels, 'f', 1))}));
    if (info.bytes > 0)
        row(tr("Size"), locale.formattedDataSize(info.bytes));
    if (info.animated)
        row(tr("Frames"), locale.toString(info.frames));
    const exif::Tags &exif = info.exif;
    if (exif.taken.isValid())
        row(tr("Taken"), join({locale.toString(exif.taken.date(), QLocale::LongFormat),
                               locale.toString(exif.taken.time(), QLocale::ShortFormat)}));
    row(tr("Camera"), exif.camera());
    row(tr("Lens"), exif.lens);
    QStringList exposure;
    if (exif.exposure > 0)
        exposure << tr("%1 s").arg(exif.exposure >= 1 ? locale.toString(exif.exposure, 'g', 3)
                                                       : QString("1/%1").arg(qRound(1 / exif.exposure)));
    if (exif.aperture > 0)
        exposure << "f/" + locale.toString(exif.aperture, 'f', exif.aperture < 10 ? 1 : 0);
    if (exif.iso > 0)
        exposure << "ISO " + locale.toString(exif.iso);
    // What a phone's tiny lens is as a 35 mm camera's, which people compare.
    if (exif.focal35 > 0)
        exposure << tr("%1 mm").arg(locale.toString(exif.focal35));
    else if (exif.focalLength > 0)
        exposure << tr("%1 mm").arg(locale.toString(exif.focalLength, 'f', 0));
    row(tr("Exposure"), join(exposure));
}

void Backend::applyVolume() {
    if (!m_audio)
        return;
    // Steps that sound even: the slider is perceptual, the output linear.
    m_audio->setVolume(float(QtAudio::convertVolume(std::min(m_volume, 1.0), QtAudio::LogarithmicVolumeScale,
                                                    QtAudio::LinearVolumeScale)));
    m_audio->setMuted(m_muted);
    if (m_volume > 1.0 || m_boosted)
        m_boostTimer.start(250);
}

// Qt's output stops at the file's own level. Past it, the stream's volume in
// PipeWire is raised, as a mixer would, and set back once it isn't needed.
// Just after playing starts the stream may not be there yet, so it's set
// once more a moment later.
void Backend::applyBoost() {
    if (!m_audio)
        return;
    // One wpctl at a time, and the latest volume last: two left running
    // could finish in either order.
    if (m_boostRunning) {
        m_boostPending = true;
        return;
    }
    const double gain = std::max(1.0, m_volume);
    m_boostRunning = true;
    auto *wpctl = new QProcess(this);
    auto done = [this, wpctl] {
        wpctl->deleteLater();
        m_boostRunning = false;
        if (std::exchange(m_boostPending, false))
            applyBoost();
    };
    connect(wpctl, &QProcess::finished, this, done);
    connect(wpctl, &QProcess::errorOccurred, this, [done](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            done();
    });
    wpctl->start("wpctl", {"set-volume", "-p", QString::number(QCoreApplication::applicationPid()),
                           QString::number(gain, 'f', 2)});
    if (m_boostAgain) {
        m_boostAgain = false;
        m_boostTimer.start(1500);
        return;
    }
    m_boosted = gain > 1.0;
}

void Backend::togglePlay() {
    if (!m_player)
        return;
    if (playing())
        pause();
    else
        play();
}

void Backend::play() {
    if (!m_player || m_picture)
        return;
    m_stopped = false;
    if (m_ended) {
        m_ended = false;
        emit statusChanged();
        m_player->setPosition(0);
    }
    m_player->play();
}

void Backend::pause() {
    if (m_player)
        m_player->pause();
}

void Backend::stop() {
    if (!m_player)
        return;
    rememberPosition();
    m_stopped = true;
    m_player->pause();
    setPosition(0);
    emit playingChanged();
}

void Backend::setPosition(qint64 ms) {
    if (!m_player || !m_seekable)
        return;
    const qint64 limit = m_duration > 0 ? m_duration : ms;
    ms = std::clamp<qint64>(ms, 0, limit);
    if (m_ended && ms < m_duration) {
        m_ended = false;
        emit statusChanged();
    }
    m_player->setPosition(ms);
    m_position = ms;
    emit positionChanged();
    emit seeked(ms);
    updateSubtitleText();
    updateChapter();
}

void Backend::seek(qint64 ms) {
    setPosition(ms);
}

void Backend::seekBy(qint64 ms) {
    setPosition(m_position + ms);
}

void Backend::seekFraction(double fraction) {
    if (m_duration > 0)
        setPosition(qint64(std::clamp(fraction, 0.0, 1.0) * m_duration));
}

void Backend::startOver() {
    setPosition(0);
    m_resumedAt = -1;
}

void Backend::stepFrame(int direction) {
    if (!m_player || !m_seekable || !m_hasVideo)
        return;
    pause();
    // Qt has no frame step, so this seeks by the shown frame's own
    // timestamps: just past its end, or just before its start, which is right
    // for variable frame rates too.
    const QVideoFrame frame = currentFrame();
    if (frame.isValid() && frame.startTime() >= 0 && frame.endTime() > frame.startTime()) {
        if (direction > 0)
            setPosition(frame.endTime() / 1000 + 1);
        else
            setPosition(std::max<qint64>(0, frame.startTime() / 1000 - 1));
        return;
    }
    const probe::Stream *video = m_probe.video();
    const qint64 frameMs = video && video->frameRate > 0 ? qint64(std::ceil(1000.0 / video->frameRate)) : 40;
    setPosition(m_position + direction * frameMs);
}

void Backend::changeRate(double delta) {
    m_rate = std::clamp(std::round((m_rate + delta) * 4) / 4, 0.25, 4.0);
    if (m_player)
        m_player->setPlaybackRate(m_rate);
    emit rateChanged();
}

void Backend::resetRate() {
    m_rate = 1.0;
    if (m_player)
        m_player->setPlaybackRate(m_rate);
    emit rateChanged();
}

void Backend::setVolume(double volume) {
    m_volume = std::clamp(volume, 0.0, m_maxVolume);
    if (m_muted && m_volume > 0)
        m_muted = false;
    applyVolume();
    setPreference("volume", std::round(m_volume * 100) / 100);
    setPreference("muted", m_muted);
    emit volumeChanged();
}

void Backend::changeVolume(double delta) {
    setVolume(std::round((m_volume + delta) * 100) / 100);
}

void Backend::toggleLoop() {
    m_looping = !m_looping;
    if (m_player)
        m_player->setLoops(m_looping ? QMediaPlayer::Infinite : QMediaPlayer::Once);
    emit loopingChanged();
}

void Backend::toggleMute() {
    m_muted = !m_muted;
    applyVolume();
    setPreference("muted", m_muted);
    emit volumeChanged();
}

void Backend::cycleSubtitles() {
    if (m_subtitleChoices.isEmpty())
        return;
    // Off, then each choice, then off again.
    const int next = m_subtitleChoice + 1 >= m_subtitleChoices.size() ? -1 : m_subtitleChoice + 1;
    applySubtitle(next, true);
}

void Backend::cycleAudio() {
    if (m_audioLabels.size() < 2)
        return;
    applyAudio((m_audioTrack + 1) % int(m_audioLabels.size()), true);
}

bool Backend::next() {
    return go(m_index + 1);
}

bool Backend::previous() {
    return go(m_index - 1);
}

QString Backend::kindOf(const QString &path) const {
    switch (playlist::kind(path)) {
    case playlist::Kind::Picture: return QStringLiteral("picture");
    case playlist::Kind::Video: return QStringLiteral("video");
    case playlist::Kind::Audio: return QStringLiteral("audio");
    default: return {};
    }
}

QString Backend::fileStamp(const QString &path) const {
    return QString::number(QFileInfo(path).lastModified().toMSecsSinceEpoch());
}

bool Backend::go(int index) {
    if (index < 0 || index >= m_playlist.size() || index == m_index)
        return false;
    rememberPosition();
    ++m_listGeneration;
    load(index);
    return true;
}

void Backend::jumpChapter(int direction) {
    if (m_chapterList.empty())
        return;
    qint64 target = -1;
    if (direction > 0) {
        for (const auto &chapter : m_chapterList) {
            if (chapter.first > m_position + 500) {
                target = chapter.first;
                break;
            }
        }
    } else {
        // Back to the start of this chapter, or the one before when already
        // within its first few seconds, as a CD player's previous does.
        for (auto it = m_chapterList.crbegin(); it != m_chapterList.crend(); ++it) {
            if (it->first < m_position - 3000) {
                target = it->first;
                break;
            }
        }
        if (target < 0)
            target = 0;
    }
    if (target >= 0)
        setPosition(target);
}

void Backend::copyFrame() {
    // The frame on screen now, latched before anything else can move it, and
    // converted in a worker: a 4K frame read back from the GPU would stall
    // the picture.
    const QVideoFrame frame = currentFrame();
    if (!frame.isValid())
        return;
    const QString at = clock(m_position);
    QPointer<Backend> self(this);
    (void)QtConcurrent::run([self, frame, at]() mutable {
        QEventLoopLocker keepRunning;
        const QImage image = frame.toImage();
        if (image.isNull()) {
            QMetaObject::invokeMethod(qApp, [self] {
                if (self)
                    emit self->notice(tr("Could not copy this frame."));
            }, Qt::QueuedConnection);
            return;
        }
        QByteArray png;
        QBuffer buffer(&png);
        buffer.open(QIODevice::WriteOnly);
        image.save(&buffer, "PNG");
        const bool copied = frames::copyWithWlCopy(png);
        QMetaObject::invokeMethod(qApp, [self, image, copied, at] {
            // Without wl-copy/xclip, Qt's clipboard holds it while the app runs.
            if (!copied)
                QGuiApplication::clipboard()->setImage(image);
            if (self)
                emit self->notice(tr("Copied the frame at %1").arg(at));
        }, Qt::QueuedConnection);
    });
}

void Backend::saveFrame() {
    const QVideoFrame frame = currentFrame();
    if (!frame.isValid())
        return;
    m_pendingFrame = frame;
    QString folder = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    if (!QDir(folder).exists())
        folder = QDir::homePath();
    const QString base = m_source.isLocalFile() ? QFileInfo(m_source.toLocalFile()).completeBaseName() : "omaview";
    const QString name = QString("%1-%2.png").arg(base, clock(m_position).replace(':', '-'));
    m_picker->saveImage(QUrl::fromLocalFile(folder + "/" + name));
}

void Backend::edit() {
    // Cutting is Omacut's job and drawing on a picture Omasnap's: the file is
    // handed over rather than either grown in here.
    const QString name = m_picture ? QStringLiteral("Omasnap") : QStringLiteral("Omacut");
    const QString tool = QStandardPaths::findExecutable(name.toLower());
    if (tool.isEmpty() || !m_source.isLocalFile())
        return;
    pause();
    if (QProcess::startDetached(tool, {m_source.toLocalFile()}))
        emit notice(tr("Opened in %1").arg(name));
    else
        emit notice(tr("%1 could not be started.").arg(name));
}

void Backend::rotate(int degrees) {
    if (!m_picture)
        return;
    m_rotation = ((m_rotation + degrees) % 360 + 360) % 360;
    emit rotationChanged();
}

void Backend::copy() {
    if (!m_picture) {
        copyFrame();
        return;
    }
    if (!m_source.isLocalFile() || m_problem != Problem::None)
        return;
    // Decoded and encoded in a worker: a large photo takes a moment.
    const QString path = m_source.toLocalFile();
    const int rotation = m_rotation;
    QPointer<Backend> self(this);
    (void)QtConcurrent::run([self, path, rotation] {
        QEventLoopLocker keepRunning;
        const QImage image = picture::load(path, rotation);
        QByteArray png;
        if (!image.isNull()) {
            QBuffer buffer(&png);
            buffer.open(QIODevice::WriteOnly);
            image.save(&buffer, "PNG");
        }
        const bool copied = !png.isEmpty() && frames::copyWithWlCopy(png);
        QMetaObject::invokeMethod(qApp, [self, image, copied] {
            if (!copied && !image.isNull())
                QGuiApplication::clipboard()->setImage(image);
            if (self)
                emit self->notice(image.isNull() ? tr("Could not copy this picture.") : tr("Copied the picture"));
        }, Qt::QueuedConnection);
    });
}

void Backend::print() {
    if (!m_picture || !m_source.isLocalFile() || m_problem != Problem::None)
        return;
    const QString lp = QStandardPaths::findExecutable("lp");
    if (lp.isEmpty()) {
        emit notice(tr("Printing needs lp, from CUPS."));
        return;
    }
    // Straight to the default printer, as Omarchy's imv binding did. A turned
    // picture prints as it shows, from a copy that goes once lp has queued it.
    const QString path = m_source.toLocalFile(), name = fileName();
    const int rotation = m_rotation;
    QPointer<Backend> self(this);
    (void)QtConcurrent::run([self, lp, path, name, rotation] {
        QEventLoopLocker keepRunning;
        QString file = path, message;
        QTemporaryFile turned(QDir::tempPath() + "/omaview-print-XXXXXX.png");
        if (rotation != 0) {
            const QImage image = picture::load(path, rotation, &message);
            if (image.isNull() || !turned.open() || !image.save(&turned, "PNG"))
                file.clear();
            else
                file = turned.fileName();
            turned.close();
        }
        bool sent = false;
        if (!file.isEmpty()) {
            QProcess process;
            process.start(lp, {file});
            sent = process.waitForFinished(60000) && process.exitStatus() == QProcess::NormalExit
                   && process.exitCode() == 0;
            message = QString::fromLocal8Bit(process.readAllStandardError()).trimmed();
        }
        QMetaObject::invokeMethod(qApp, [self, sent, name, message] {
            if (self)
                emit self->notice(sent ? tr("Sent %1 to the printer").arg(name) : tr("Could not print: %1").arg(message));
        }, Qt::QueuedConnection);
    });
}

bool Backend::trash() {
    if (!m_source.isLocalFile() || m_index < 0 || m_index >= m_playlist.size())
        return false;
    // Renamed into the Trash while the player may still read it, which Linux
    // allows, so a failure leaves the video playing.
    const QString path = m_source.toLocalFile();
    QString inTrash;
    if (!QFile::moveToTrash(path, &inTrash)) {
        emit notice(tr("Could not move %1 to the Trash.").arg(fileName()));
        return false;
    }
    m_trashed.append({path, inTrash, m_index});
    m_loaded = false;  // nothing to remember about a file that's gone
    m_playlist.removeAt(m_index);
    ++m_listGeneration;
    if (m_playlist.isEmpty())
        clear();
    else
        load(std::min(m_index, int(m_playlist.size()) - 1));
    return true;
}

bool Backend::undoTrash() {
    if (m_trashed.isEmpty())
        return false;
    // Kept until it's back, so another try works once what was in its way
    // has gone.
    const Trashed item = m_trashed.last();
    const QString name = QFileInfo(item.path).fileName();
    if (QFileInfo::exists(item.path) || !QFile::rename(item.inTrash, item.path)) {
        emit notice(tr("Could not put %1 back.").arg(name));
        return false;
    }
    m_trashed.removeLast();
    // The Trash's record of it, in info/ beside files/, goes too.
    const QFileInfo trashed(item.inTrash);
    QFile::remove(trashed.absolutePath() + "/../info/" + trashed.fileName() + ".trashinfo");
    rememberPosition();
    const int at = std::clamp(item.index, 0, int(m_playlist.size()));
    m_playlist.insert(at, item.path);
    ++m_listGeneration;
    load(at);
    return true;
}

void Backend::rememberPosition() {
    if (!m_player || m_picture || !m_source.isLocalFile() || !m_loaded || m_problem != Problem::None)
        return;
    const QString file = m_source.toLocalFile();
    const qint64 position = m_ended ? m_duration : m_position, duration = m_duration;
    Positions positions = m_positions;
    m_writer.start([positions, file, position, duration]() mutable {
        positions.update(file, position, duration);
    });
}

void Backend::setPreference(const QString &key, const QJsonValue &value) {
    if (m_preferences.value(key) == value)
        return;
    m_preferences.insert(key, value);
    m_changedPreferences.insert(key);
    m_preferenceTimer.start();
}

void Backend::writePreferences() {
    m_preferenceTimer.stop();
    if (m_changedPreferences.isEmpty())
        return;
    QJsonObject changed;
    for (const QString &key : std::as_const(m_changedPreferences))
        changed.insert(key, m_preferences.value(key));
    m_changedPreferences.clear();
    Positions positions = m_positions;
    m_writer.start([positions, changed]() mutable { positions.setPreferences(changed); });
}

void Backend::flush() {
    writePreferences();
    m_writer.waitForDone();
}

void Backend::close() {
    // Once: the window's closing and the application's quitting both ask,
    // and stopping the player moves it back to the start.
    rememberPosition();
    m_loaded = false;
    m_previews.cancel();
    m_previewTimer.stop();
    if (m_cancel)
        *m_cancel = true;
    if (m_player)
        m_player->stop();
    flush();
}

void Backend::startPreviews() {
    if (!m_previewsWanted || !m_source.isLocalFile() || !m_seekable || !m_hasVideo || m_duration <= 0)
        return;
    QSize size = m_videoSize;
    if (const probe::Stream *video = m_probe.video(); size.isEmpty() && video) {
        size = QSize(video->width, video->height);
        if (std::abs(video->rotation) % 180 == 90)
            size.transpose();
    }
    if (size.isEmpty())
        return;
    m_previewsWanted = false;
    m_previews.start(m_source.toLocalFile(), m_duration / 1000.0, size);
}

#pragma once

#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QMutex>
#include <QObject>
#include <QSet>
#include <QSize>
#include <QStringList>
#include <QThreadPool>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <QVideoFrame>
#include <atomic>
#include <memory>
#include <utility>
#include <vector>

#include "frames.h"
#include "hyprland.h"
#include "picture.h"
#include "positions.h"
#include "probe.h"
#include "subtitles.h"

class FilePicker;
class QAudioOutput;
class QMediaPlayer;
class QRhi;
class QVideoSink;

// What the window talks to. It owns the player, created with the first video
// or song so a window with nothing to play, or only pictures, never starts Qt
// Multimedia's FFmpeg backend, and everything that is a decision or touches
// the disk: the playlist, track choice, resume positions, subtitles beside
// the file, the scrub previews, frames and pictures out, and the Trash. The
// window decodes a picture itself, through Qt Quick's Image.
class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool playerReady READ playerReady NOTIFY playerReadyChanged)
    Q_PROPERTY(bool hasMedia READ hasMedia NOTIFY mediaChanged)
    Q_PROPERTY(bool isPicture READ isPicture NOTIFY mediaChanged)
    Q_PROPERTY(QUrl pictureSource READ pictureSource NOTIFY pictureChanged)
    Q_PROPERTY(QSize pictureSize READ pictureSize NOTIFY pictureChanged)
    Q_PROPERTY(bool animated READ animated NOTIFY pictureChanged)
    Q_PROPERTY(bool vector READ vector NOTIFY pictureChanged)
    Q_PROPERTY(bool transparent READ transparent NOTIFY pictureChanged)
    Q_PROPERTY(int rotation READ rotation NOTIFY rotationChanged)
    Q_PROPERTY(QString fileName READ fileName NOTIFY mediaChanged)
    Q_PROPERTY(QString title READ title NOTIFY metadataChanged)
    Q_PROPERTY(QString artist READ artist NOTIFY metadataChanged)
    Q_PROPERTY(QString coverArt READ coverArt NOTIFY metadataChanged)
    Q_PROPERTY(bool playing READ playing NOTIFY playingChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY statusChanged)
    Q_PROPERTY(bool ended READ ended NOTIFY statusChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool seekable READ seekable NOTIFY seekableChanged)
    Q_PROPERTY(bool hasVideo READ hasVideo NOTIFY hasVideoChanged)
    Q_PROPERTY(QSize videoSize READ videoSize NOTIFY videoSizeChanged)
    Q_PROPERTY(double volume READ volume NOTIFY volumeChanged)
    Q_PROPERTY(bool muted READ muted NOTIFY volumeChanged)
    // 1 is the file's own level; above it, up to 1.5, is a boost, where
    // PipeWire's wpctl is at hand to raise the stream past what Qt allows.
    Q_PROPERTY(double maxVolume READ maxVolume CONSTANT)
    Q_PROPERTY(bool looping READ looping NOTIFY loopingChanged)
    Q_PROPERTY(double rate READ rate NOTIFY rateChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(bool stopped READ stopped NOTIFY playingChanged)
    Q_PROPERTY(QString subtitleText READ subtitleText NOTIFY subtitleTextChanged)
    Q_PROPERTY(QString subtitleLabel READ subtitleLabel NOTIFY tracksChanged)
    Q_PROPERTY(int subtitleChoices READ subtitleChoices NOTIFY tracksChanged)
    Q_PROPERTY(QString audioLabel READ audioLabel NOTIFY tracksChanged)
    Q_PROPERTY(int audioTracks READ audioTracks NOTIFY tracksChanged)
    Q_PROPERTY(QVariantList chapters READ chapters NOTIFY infoChanged)
    Q_PROPERTY(QString chapterTitle READ chapterTitle NOTIFY chapterChanged)
    Q_PROPERTY(QVariantList info READ info NOTIFY infoChanged)
    Q_PROPERTY(int playlistIndex READ playlistIndex NOTIFY playlistChanged)
    Q_PROPERTY(int playlistCount READ playlistCount NOTIFY playlistChanged)
    Q_PROPERTY(QStringList playlist READ playlist NOTIFY playlistChanged)
    Q_PROPERTY(QString nextName READ nextName NOTIFY playlistChanged)
    Q_PROPERTY(bool canEdit READ canEdit NOTIFY mediaChanged)
    Q_PROPERTY(QUrl previewSource READ previewSource NOTIFY previewsChanged)
    Q_PROPERTY(int previewCount READ previewCount NOTIFY previewsChanged)
    Q_PROPERTY(int previewColumns READ previewColumns NOTIFY previewsChanged)
    Q_PROPERTY(QSize previewTileSize READ previewTileSize NOTIFY previewsChanged)
    Q_PROPERTY(double previewInterval READ previewInterval NOTIFY previewsChanged)

public:
    struct Options {
        QString positionsPath;        // tests pass a temp file
        bool audio = true;            // tests play without an audio device
        FilePicker *picker = nullptr; // tests answer the dialogs; null is the portal
        bool previews = true;
        int previewDelayMs = 3000;
    };

    explicit Backend(QObject *parent = nullptr);
    Backend(const Options &options, QObject *parent = nullptr);
    ~Backend() override;

    bool playerReady() const { return m_player != nullptr; }
    bool hasMedia() const { return !m_source.isEmpty(); }
    bool isPicture() const { return m_picture; }
    QUrl pictureSource() const;
    QSize pictureSize() const { return m_pictureInfo.size; }
    bool animated() const { return m_pictureInfo.animated; }
    bool vector() const { return m_pictureInfo.vector; }
    bool transparent() const { return m_pictureInfo.transparent; }
    int rotation() const { return m_rotation; }
    QString fileName() const;
    QString filePath() const { return m_source.isLocalFile() ? m_source.toLocalFile() : QString(); }
    QUrl source() const { return m_source; }
    QString title() const;
    QString artist() const { return m_artist; }
    QString coverArt() const { return m_coverArt; }
    bool playing() const;
    bool loading() const;
    bool ended() const { return m_ended; }
    qint64 position() const { return m_position; }
    qint64 duration() const { return m_duration; }
    bool seekable() const { return m_seekable; }
    bool hasVideo() const { return m_hasVideo; }
    QSize videoSize() const { return m_videoSize; }
    double volume() const { return m_volume; }
    double maxVolume() const { return m_maxVolume; }
    bool looping() const { return m_looping; }
    bool muted() const { return m_muted; }
    double rate() const { return m_rate; }
    // Translated when read, so a language switch re-renders it.
    QString error() const;
    bool stopped() const { return m_stopped; }
    QString subtitleText() const { return m_subtitleText; }
    QString subtitleLabel() const;
    int subtitleChoices() const { return int(m_subtitleChoices.size()); }
    QString audioLabel() const;
    int audioTracks() const { return int(m_audioLabels.size()); }
    QVariantList chapters() const { return m_chapters; }
    QString chapterTitle() const { return m_chapterTitle; }
    QVariantList info() const { return m_info; }
    qint64 resumedAt() const { return m_resumedAt; }
    int playlistIndex() const { return m_index; }
    int playlistCount() const { return int(m_playlist.size()); }
    QString nextName() const;
    // Omasnap for a picture, Omacut for a video, when it is installed.
    bool canEdit() const;
    QUrl previewSource() const { return m_previewSource; }
    int previewCount() const { return m_previewLayout.count; }
    int previewColumns() const { return m_previewLayout.columns; }
    QSize previewTileSize() const { return m_previewLayout.tileSize; }
    double previewInterval() const { return m_previewLayout.interval; }
    QStringList playlist() const { return m_playlist; }

    // The Omarchy language, for choosing audio and subtitle tracks.
    void setLanguage(const QString &language);

    // Paths or URLs as a command line gives them: several are the playlist,
    // one local file brings its folder.
    Q_INVOKABLE void open(const QStringList &arguments);
    Q_INVOKABLE void openUrls(const QList<QUrl> &urls);
    Q_INVOKABLE void openDialog();
    // Asks the compositor to give the window this size; false when it can't.
    Q_INVOKABLE bool reshapeWindow(QSize size) { return hyprland::reshape(size); }
    Q_INVOKABLE void togglePlay();
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void seek(qint64 ms);
    Q_INVOKABLE void seekBy(qint64 ms);
    Q_INVOKABLE void seekFraction(double fraction);
    Q_INVOKABLE void startOver();
    Q_INVOKABLE void stepFrame(int direction);
    Q_INVOKABLE void changeRate(double delta);
    Q_INVOKABLE void resetRate();
    Q_INVOKABLE void setVolume(double volume);
    Q_INVOKABLE void changeVolume(double delta);
    Q_INVOKABLE void toggleMute();
    // Plays the file over and over, and every file after it, until turned off.
    Q_INVOKABLE void toggleLoop();
    Q_INVOKABLE void cycleSubtitles();
    Q_INVOKABLE void cycleAudio();
    Q_INVOKABLE bool next();
    Q_INVOKABLE bool previous();
    // Any file in the playlist, for the first and the last.
    Q_INVOKABLE bool go(int index);
    // "picture", "video" or "audio", for the grid's tiles.
    Q_INVOKABLE QString kindOf(const QString &path) const;
    // When the file last changed, for the grid's tiles.
    Q_INVOKABLE QString fileStamp(const QString &path) const;
    Q_INVOKABLE void jumpChapter(int direction);
    Q_INVOKABLE QString chapterAt(qint64 ms) const;
    // The picture, turned as it shows, or the video's frame on screen.
    Q_INVOKABLE void copy();
    Q_INVOKABLE void saveFrame();
    Q_INVOKABLE void edit();
    // Turns the picture as it shows, by quarter turns; the file is never
    // changed.
    Q_INVOKABLE void rotate(int degrees);
    // Sends the picture, turned as it shows, to the default printer.
    Q_INVOKABLE void print();
    // Moves the file shown to the Trash and shows the next; undoTrash() puts
    // the last one back where it was.
    Q_INVOKABLE bool trash();
    Q_INVOKABLE bool undoTrash();
    // The window couldn't decode the picture.
    Q_INVOKABLE void pictureFailed();
    // The window's VideoOutput, once its Loader has made it, and null as it
    // goes.
    Q_INVOKABLE void setVideoSink(QVideoSink *sink);
    // The window's GPU context, from the render thread as the scene graph
    // starts and stops, so decoded frames stay on the GPU.
    void setRhi(QRhi *rhi);
    // Remembers where the open file was left and stops; the window calls it
    // on close, and the application again as it quits, which does nothing.
    Q_INVOKABLE void close();
    // Writes remembered choices now, and waits for every write to finish.
    void flush();

    // The frame on screen now, latched for Copy and Save.
    QVideoFrame currentFrame() const {
        QMutexLocker locker(&m_frameLock);
        return m_frame;
    }

signals:
    void playerReadyChanged();
    void mediaChanged();
    void metadataChanged();
    void playingChanged();
    void statusChanged();
    void positionChanged();
    void durationChanged();
    void seekableChanged();
    void hasVideoChanged();
    void videoSizeChanged();
    void volumeChanged();
    // A folder was opened: the window shows it as the grid.
    void folderOpened();
    // Nothing given could be opened, as an empty folder: the window stops
    // waiting for a file.
    void nothingToOpen();
    void loopingChanged();
    void rateChanged();
    void errorChanged();
    void subtitleTextChanged();
    void tracksChanged();
    void chapterChanged();
    void infoChanged();
    void playlistChanged();
    void previewsChanged();
    void pictureChanged();
    void rotationChanged();
    // A short message for the on-screen display: what an action did.
    void notice(const QString &text);
    // Media keys and the bar asked for the window to come forward.
    void raiseRequested();
    // MPRIS: a seek the player did on its own terms.
    void seeked(qint64 ms);
    // A new file: the window clears the last one's picture.
    void pictureCleared();

private:
    struct SubtitleChoice {
        int embedded = -1;  // Qt's subtitle track index
        int sidecar = -1;   // index into m_sidecars
        QString label;
        QString language;   // two-letter where known
        QList<subtitles::Cue> cues;
        bool cuesLoaded = false;
        bool cuesLoading = false;
    };

    void ensurePlayer();
    void load(int index);
    void loadPicture(const QString &item);
    void readPicture();
    void onPictureRead(const picture::Info &info, quint64 generation, int revision);
    void clear();
    void resetFile();
    void copyFrame();
    void rememberPosition();
    enum class Problem { None, Missing, Unreadable, Unplayable, Format, Access, PictureFormat, PictureBroken };
    void setError(Problem problem);
    void labelTracks();
    void emitFileChanged();
    void setPosition(qint64 ms);
    void onStatus();
    void onTracks();
    void onProbed(const probe::Info &info, const QList<subtitles::Sidecar> &sidecars, quint64 generation);
    void setPreference(const QString &key, const QJsonValue &value);
    void writePreferences();
    void chooseTracks();
    void applySubtitle(int choice, bool remember);
    void applyAudio(int track, bool remember);
    void loadCues(int choice);
    void updateSubtitleText();
    void updateChapter();
    void updateMetadata();
    void buildInfo();
    template <typename Row>
    void buildPictureInfo(Row row);
    void applyVolume();
    // Opens what open() found, a folder's files already listed.
    void openItems(const QStringList &items, bool folder);
    void applyBoost();
    void startPreviews();

    Options m_options;
    std::unique_ptr<FilePicker> m_ownPicker;
    FilePicker *m_picker = nullptr;
    Positions m_positions;
    QString m_language = "en";

    QMediaPlayer *m_player = nullptr;
    QAudioOutput *m_audio = nullptr;
    QVideoSink *m_sink = nullptr;              // the player's, which forwards
    // Shared with the decoder's thread, which hands frames on. The two locks
    // are never held together.
    mutable QMutex m_frameLock;
    QVideoFrame m_frame;
    QSize m_frameSize;
    QMutex m_outputLock;
    QVideoSink *m_output = nullptr;  // the window's
    QVideoFrame m_pendingFrame;  // latched by Save frame while the dialog is up
    std::atomic<QRhi *> m_rhi{nullptr};

    QStringList m_playlist;
    int m_index = -1;
    QUrl m_source;
    quint64 m_generation = 0;      // which file async work belongs to
    quint64 m_listGeneration = 0;  // which open a folder listing belongs to
    // Set when the file changes or the window closes; its ffprobe and
    // subtitle extractions check it and stop.
    std::shared_ptr<std::atomic_bool> m_cancel;

    QJsonObject m_preferences;
    QSet<QString> m_changedPreferences;
    QTimer m_preferenceTimer;
    QThreadPool m_writer;  // one thread, so writes land in order

    QString m_title;
    QString m_artist;
    QString m_coverArt;
    Problem m_problem = Problem::None;
    bool m_stopped = false;  // MPRIS Stop: back at the start, not merely paused
    qint64 m_position = 0;
    qint64 m_duration = 0;
    bool m_seekable = false;
    bool m_hasVideo = false;
    bool m_ended = false;
    bool m_loaded = false;
    QSize m_videoSize;
    // The file's metadata turns its frames a quarter, as a phone's does.
    bool m_videoTurned = false;
    double m_volume = 1.0;  // perceptual, 0 to maxVolume
    double m_maxVolume = 1.0;
    // The stream's own volume may be raised. True at first, since WirePlumber
    // gives a new stream the volume it last had, a boost included.
    bool m_boosted = true;
    bool m_boostAgain = false;
    bool m_boostRunning = false;
    bool m_boostPending = false;
    QTimer m_boostTimer;
    bool m_looping = false;
    bool m_holdPlayback = false;
    bool m_heldBehindGrid = false;
    bool m_muted = false;
    double m_rate = 1.0;

    probe::Info m_probe;
    bool m_probed = false;
    bool m_tracksReady = false;
    bool m_tracksChosen = false;
    qint64 m_pendingResume = -1;
    qint64 m_resumedAt = -1;

    QList<subtitles::Sidecar> m_sidecars;
    QList<SubtitleChoice> m_subtitleChoices;
    int m_subtitleChoice = -1;
    QList<subtitles::Cue> m_cues;
    QString m_embeddedText;
    QString m_subtitleText;
    QStringList m_audioLabels;
    QStringList m_audioLanguages;
    int m_audioTrack = -1;

    QVariantList m_chapters;
    std::vector<std::pair<qint64, QString>> m_chapterList;
    QString m_chapterTitle;
    QVariantList m_info;

    bool m_picture = false;
    picture::Info m_pictureInfo;
    int m_rotation = 0;
    int m_revision = 0;  // a picture changed on disk, so the window reads it again
    QFileSystemWatcher m_watcher;
    QTimer m_changedTimer;

    struct Trashed {
        QString path;
        QString inTrash;
        int index = 0;
    };
    QList<Trashed> m_trashed;

    frames::Previews m_previews;
    QTimer m_previewTimer;
    bool m_previewsWanted = false;
    QUrl m_previewSource;
    frames::PreviewLayout m_previewLayout;
};

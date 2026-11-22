#pragma once

#include <QByteArray>
#include <QElapsedTimer>
#include <QEventLoopLocker>
#include <QImage>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QSize>
#include <QStringList>
#include <QTimer>
#include <memory>

class Models;
class QNetworkReply;

// Makes one image at a time on the ready model's stable-diffusion.cpp server:
// submits a job, follows it with its previews step by step, and saves the
// finished image to the output folder.
class Generator : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    // "", queued, conditioning, sampling, decoding, saving
    Q_PROPERTY(QString stage READ stage NOTIFY changed)
    Q_PROPERTY(int step READ step NOTIFY changed)
    Q_PROPERTY(int totalSteps READ totalSteps NOTIFY changed)
    // One preview per step as a data URL; an empty one is a step the
    // server moved past before it was asked.
    Q_PROPERTY(QStringList previews READ previews NOTIFY changed)
    // What the center shows: the newest preview, or the finished file.
    Q_PROPERTY(QString image READ image NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool unsaved READ unsaved NOTIFY changed)
    Q_PROPERTY(int defaultSteps READ defaultSteps NOTIFY defaultsChanged)
    // About how many seconds the job in hand has left, or -1 while that
    // can't be told yet. From how long the last one like it took, or else
    // from how fast its steps go.
    Q_PROPERTY(int remainingSeconds READ remainingSeconds NOTIFY remainingChanged)
    // How much of the job in hand has gone by, 0 to just short of 1, from
    // how long the last one like it took; -1 with nothing to go by.
    Q_PROPERTY(double timeProgress READ timeProgress NOTIFY remainingChanged)

public:
    // Images and clips are kept in `folder`, songs in `musicFolder` with
    // their posters in `folder`; empty ones are Generated in the user's
    // Pictures and Music.
    explicit Generator(Models *models, const QString &folder = {}, const QString &musicFolder = {}, QObject *parent = nullptr);
    ~Generator() override;

    bool busy() const { return !m_job.isEmpty() || m_submitting; }
    QString stage() const { return m_stage; }
    int step() const { return m_step; }
    int totalSteps() const { return m_totalSteps; }
    QStringList previews() const { return m_previews; }
    QString image() const { return m_image; }
    QString error() const { return m_error; }
    bool unsaved() const { return !m_pending.isEmpty() || !m_unposted.isEmpty(); }
    int defaultSteps() const;
    int remainingSeconds() const;
    double timeProgress() const;
    QString folder() const { return m_folder; }
    QString musicFolder() const { return m_musicFolder; }

    // A seed below zero asks the server for a random one; steps of zero take
    // the model's own default. With base images the new one is a change of
    // them, at the first one's size: an edit model, the one in use or another
    // running, takes them all as references and the prompt as the instruction
    // (put this from the first into the second); without one, the model
    // starts from the one image and redraws it as the prompt describes.
    Q_INVOKABLE void generate(const QString &prompt, int width, int height, int steps = 0, qint64 seed = -1,
                              const QStringList &baseUrls = {}, bool edit = false);
    // The most pictures an edit model is given at once.
    static constexpr int maxBases = 4;

    // How far a redrawn image may move from its base: far enough that a change
    // asked for shows, near enough that the picture stays the same picture.
    static constexpr double baseStrength = 0.7;

    // A size near a megapixel in the shape of `width` by `height`, in the
    // steps of 64 the models work in.
    static QSize fitMegapixel(int width, int height);

    // A picture ready to start from: its PNG, at a size the model works in.
    struct Base {
        QByteArray png;
        QSize size;
    };
    static Base prepareBase(const QString &path);

    // Makes a short clip with its sound on the running video model, from the
    // prompt alone or with `firstFrameUrl` as its first frame, about the
    // size the model is fastest at in the shape of `width` by `height`.
    Q_INVOKABLE void makeVideo(const QString &prompt, int width, int height, const QString &firstFrameUrl = {},
                               int seconds = defaultSeconds);
    // A clip is 5 seconds at 24 frames a second unless asked for another
    // length, as long as its model makes here; a minute at most.
    static constexpr int defaultSeconds = 5;
    static constexpr int maxClipSeconds = 60;
    static constexpr int videoFps = 24;
    // About 0.4 megapixels in the shape of `width` by `height`, in steps of 32.
    static QSize fitVideo(int width, int height);

    // Makes a song on the music model in use. Its language model writes the
    // song out first (how it's played, and the lyrics in `language` unless
    // they're given; `[Instrumental]` for lyrics leaves the words out), then
    // it's rendered to an MP3 about `seconds` long.
    Q_INVOKABLE void makeSong(const QString &prompt, const QString &lyrics = {}, int seconds = defaultSongSeconds,
                              const QString &language = "en");
    static constexpr int defaultSongSeconds = 60;
    // What a song goes by in the history: its chorus's first line, else its
    // first line, else what was asked for.
    static QString songTitle(const QString &lyrics, const QString &prompt);
    // A song's shape: how loud each part of it is from start to end, as
    // `waveBars` levels from 0 to 255, out of its sound as 16-bit mono samples.
    static QByteArray songWave(const QByteArray &samples);
    static constexpr int waveBars = 96;

    Q_INVOKABLE void cancel();
    // Writes a finished image the folder refused last time, or a song's poster.
    Q_INVOKABLE void retrySave();
    // Shows an image from the history in the center.
    Q_INVOKABLE void show(const QString &url);

    // A new name in `folder` for an image made from `prompt` at `when`, which
    // no existing file has: the time, then the prompt's first words.
    static QString fileName(const QString &prompt, const QDateTime &when);

signals:
    void changed();
    void defaultsChanged();
    void saved(const QString &path);
    // A clip's poster is written beside it, a moment after the clip; a
    // song's with it.
    void posterSaved(const QString &clip);
    void remainingChanged();
    void posterFailed(const QString &error);
    // A job has ended: made and saved, cancelled, or failed with `error`.
    void finished(const QString &error);

private:
    // To the selected model's server; a job's own requests go where the job runs.
    QNetworkReply *send(const QString &method, const QString &path, const QJsonObject &body = {});
    QNetworkReply *sendJob(const QString &method, const QString &path, const QJsonObject &body = {});
    // Hands the job to its server and follows it from there.
    void submit(const QString &path, const QJsonObject &body);
    // Writes the poster a clip or a song shows by in the history, holding
    // its prompt, and a song's title.
    bool writePoster(const QString &media, const QImage &frame, const QString &prompt, const QString &title = {},
                     const QByteArray &wave = {});
    // Reads the finished song's shape without holding up the window, then
    // saves the song and its poster and ends the job.
    void shapeSong();
    // Writes the saved song's poster, and only then says the song is saved.
    bool posterSong();
    // The job in hand on its server: itself, or its `cancel` or `result`.
    QString jobPath(const QString &action = {}) const;
    void followSong(const QString &status);
    QNetworkReply *request(const QString &origin, const QByteArray &key, const QString &method, const QString &path, const QJsonObject &body);
    void fetchDefaults();
    void poll();
    void follow(const QJsonObject &job);
    void finish(const QString &error = {});
    bool save();

    Models *m_models;
    QString m_folder;
    QString m_musicFolder;
    QNetworkAccessManager m_network;
    QTimer m_poll;
    // When the job in hand started, what it's called among the durations
    // remembered, and how long the last one like it took.
    QElapsedTimer m_clock;
    QString m_durationKey;
    double m_expected = 0;
    QTimer m_tick;
    void startClock(const QString &key);
    QJsonObject m_defaults;
    QString m_origin;
    // The server the job in hand runs on, when a change goes to a running
    // edit model rather than the one in use.
    QString m_jobOrigin;
    QByteArray m_jobKey;
    QByteArray m_key;

    QString m_job;
    bool m_submitting = false;
    // The job in hand makes a clip, and the picture it starts from, if any.
    bool m_video = false;
    QImage m_firstFrame;
    // The job in hand makes a song: written first, then rendered.
    bool m_song = false;
    bool m_rendering = false;
    QString m_lyrics;
    // A song that's saved but has no poster yet, so the history can't list it.
    QString m_unposted;
    QByteArray m_wave;
    bool m_cancelling = false;
    QString m_stage;
    int m_step = 0;
    int m_totalSteps = 0;
    QStringList m_previews;
    QString m_image;
    QString m_error;
    QString m_prompt;
    QByteArray m_pending;
    // The app keeps running until a started image is saved, even when its
    // window closes.
    std::unique_ptr<QEventLoopLocker> m_locker;
};

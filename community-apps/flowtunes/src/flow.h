#pragma once

#include <QDateTime>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QVariantList>
#include <functional>

class Models;
class QNetworkReply;

// An endless run of tunes in one genre. While a genre is picked, it has the
// music model make one tune after another, always keeping two ready behind
// the one playing, so the music never has to wait for the model. Every tune
// is saved in the genre's own folder in the user's music, and a genre that
// has tunes from before plays those first, in any order, before new ones.
class Flow : public QObject {
    Q_OBJECT
    Q_PROPERTY(QStringList genres READ genres CONSTANT)
    // The genre playing, empty when none is, and the one played last time.
    Q_PROPERTY(QString genre READ genre NOTIFY changed)
    Q_PROPERTY(QString lastGenre READ lastGenre NOTIFY changed)
    // The tune to play now: empty while the first one, or the next one after
    // a skip, is still being made.
    Q_PROPERTY(QUrl track READ track NOTIFY changed)
    // Its shape, how loud it is from start to end, as levels from 0 to 1.
    Q_PROPERTY(QVariantList wave READ wave NOTIFY changed)
    Q_PROPERTY(int bpm READ bpm NOTIFY changed)
    Q_PROPERTY(QString key READ key NOTIFY changed)
    // Its name: a sung tune's hook, or two words of its genre for one nobody
    // sings in, kept in the MP3's ID3 tag, where a tune of the user's own
    // has its name too.
    Q_PROPERTY(QString title READ title NOTIFY changed)
    // Which tune of this flow it is, from 1.
    Q_PROPERTY(int number READ number NOTIFY changed)
    Q_PROPERTY(bool composing READ composing NOTIFY changed)
    // Whether the tunes are sung, with lyrics the model writes, or only played.
    Q_PROPERTY(bool lyrics READ lyrics WRITE setLyrics NOTIFY changed)
    // The language they're sung in.
    Q_PROPERTY(QString language MEMBER m_language)
    // Why there's nothing to play. While a tune plays, trouble making the
    // next one is tried again quietly, and said only once the music runs out.
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    // Each genre's tunes are in a folder of its name in `musicFolder`; an
    // empty one is the user's Music.
    explicit Flow(Models *models, const QString &musicFolder = {}, QObject *parent = nullptr);

    QStringList genres() const;
    QString genre() const { return m_genre; }
    QString lastGenre() const;
    QUrl track() const { return m_current.path.isEmpty() ? QUrl() : QUrl::fromLocalFile(m_current.path); }
    QVariantList wave() const { return m_current.wave; }
    int bpm() const { return m_current.bpm; }
    QString key() const { return m_current.key; }
    QString title() const { return m_current.title; }
    int number() const { return m_number; }
    bool composing() const { return m_composing; }
    bool lyrics() const { return m_lyrics; }
    // Changes what the flow plays from the next tune on: the one playing
    // stays, and those ready behind it give way to the other kind.
    void setLyrics(bool lyrics);
    QString error() const { return m_error; }
    // Where a genre's tunes are.
    QString folder(const QString &genre) const;

    // Starts a flow of this genre in place of the one playing, starting the
    // music model first when it's set up but stopped.
    Q_INVOKABLE void play(const QString &genre);
    Q_INVOKABLE void stop();
    // On to the next tune: the one playing has ended, or is skipped.
    Q_INVOKABLE void next();
    Q_INVOKABLE void retry();
    // The tune couldn't be played. One that can't is passed over; when tune
    // after tune can't, the flow stops rather than have the model make more
    // that nobody hears.
    Q_INVOKABLE void playbackFailed(const QString &why);

    // A tune's length. Longer tunes mean fewer breaks in the music and less
    // of the model's time; this is as long as it stays good.
    static constexpr int trackSeconds = 180;
    // How many finished tunes wait behind the one playing.
    static constexpr int tunesAhead = 2;
    // A tune that fails is tried once more by itself after this long, since
    // a model that was just restarted or swapped out is soon back.
    int retryDelayMs = 3000;
    // A model asked to start that is still stopped after this long didn't start.
    int startGraceMs = 20000;
    // A tune's shape: how loud each part of it is from start to end, as
    // `waveBars` levels from 0 to 1, out of its sound as 16-bit mono samples.
    static QVariantList shapeOf(const QByteArray &samples);
    static constexpr int waveBars = 96;
    // A tune's file name: when it was made, then its tempo and key when the
    // model said them, which is where they're read back from, and
    // `-instrumental` at its end when nobody sings in it. A file without
    // that ending, whoever made it, counts as sung.
    static QString fileName(const QDateTime &when, int bpm, const QString &key, bool lyrics = false);
    static bool sungOf(const QString &fileName);
    // How many lines of a written-out song are words to sing, rather than
    // its parts' names in brackets.
    static int sungLines(const QString &lyrics);
    // The model asked for lyrics doesn't always write any, so it's asked
    // again, this many times at most for one tune.
    static constexpr int lyricsTries = 6;
    // A sung tune's name: the line its lyrics sing most, the first of them
    // when none comes back, cut to a title's length.
    static QString hookOf(const QString &lyrics);
    // An MP3 with its ID3 tag, if it had one, swapped for one naming it.
    static QByteArray titled(const QByteArray &mp3, const QString &title);
    // The name in an MP3's ID3 tag, empty when it has none.
    static QString titleOf(const QString &path);
    static int bpmOf(const QString &fileName);
    static QString keyOf(const QString &fileName);

signals:
    void changed();

private:
    struct Track {
        QString path;
        QVariantList wave;
        int bpm = 0;
        QString key;
        QString title;
        // Made by this flow, rather than found in the genre's folder.
        bool made = false;
    };
    using Done = std::function<void(const QByteArray &result)>;

    QNetworkReply *send(const QString &method, const QString &path, const QJsonObject &body = {});
    // Makes another tune when one is wanted and the model is ready, starting
    // the model when it's set up but stopped, whether it never ran or stopped
    // in the middle of the flow. `again` tries a start that failed.
    void pump(bool again = false);
    void compose();
    // Hands the model a job, follows it until it's done, and gives its result to `done`.
    void submit(const QString &path, const QJsonObject &body, Done done);
    void poll();
    void cancelJob(const QString &id);
    // Reads a tune's shape with ffmpeg, then queues it.
    void shape(Track track);
    void enqueue(const Track &track);
    void advance();
    void fail(const QString &error);
    // Drops everything of the flow in hand: its job, its queue, its error.
    void reset();
    // Finds the genre's tunes from before, of the kind being played.
    void gather();

    Models *m_models;
    QString m_musicFolder;
    QNetworkAccessManager m_network;
    QTimer m_poll;
    QTimer m_again;
    QTimer m_patience;
    // Tunes that couldn't be made in a row, and why the last one couldn't.
    int m_failures = 0;
    QString m_trouble;
    // Tunes that couldn't be played in a row.
    int m_unplayed = 0;
    // Times in a row the model wrote a tune with no words when asked for some.
    int m_unsung = 0;
    // The model was asked to start and stayed stopped.
    bool m_stalled = false;

    QString m_genre;
    bool m_lyrics = false;
    QString m_language = "en";
    Track m_current;
    QList<Track> m_queue;
    // The genre's tunes from before that this flow hasn't played yet.
    QStringList m_library;
    int m_number = 0;
    // The model is making a tune.
    bool m_composing = false;
    // A tune is on its way into the queue: being made, or having its shape read.
    bool m_filling = false;
    // The model has been asked to start for this flow, which is asked once.
    bool m_asked = false;
    QString m_error;
    QString m_job;
    Done m_done;
    // Which flow is in hand: answers to an earlier one's requests are dropped.
    int m_run = 0;
};

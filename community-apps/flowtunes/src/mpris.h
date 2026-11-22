#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantMap>

class Flow;

// Flowtunes as the desktop sees a music player, over MPRIS on the session
// bus: the media keys, playerctl and the bar play, pause and skip it, and
// show the tune that's playing. Next goes straight to the flow; the rest is
// the window's, which hears it as these signals and says how it's playing
// through the properties.
class Mpris : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool paused READ paused WRITE setPaused NOTIFY changed)
    // Where the player is in the tune, and how long it is, in milliseconds.
    // The bus asks for the position when it wants it, so it's never announced.
    Q_PROPERTY(qint64 position READ position WRITE setPosition)
    Q_PROPERTY(qint64 duration READ duration WRITE setDuration NOTIFY changed)

public:
    explicit Mpris(Flow *flow, QObject *parent = nullptr);

    // Takes org.mpris.MediaPlayer2.<name>, or a name of its own for this
    // run when another Flowtunes has that, as the spec has it.
    bool publish(const QString &name = "flowtunes");

    bool paused() const { return m_paused; }
    void setPaused(bool paused);
    qint64 position() const { return m_position; }
    void setPosition(qint64 position);
    qint64 duration() const { return m_duration; }
    void setDuration(qint64 duration);

    // What the bus is told.
    QString playbackStatus() const;
    QVariantMap metadata() const;
    bool hasTune() const;

    // What it's asked. Previous plays the tune from its start: the flow only
    // goes on. Stop pauses it at its start, which is where Play goes on from.
    void play() { emit pauseAsked(false); }
    void pause() { emit pauseAsked(true); }
    void playPause() { emit pauseAsked(hasTune() && !m_paused); }
    void stop();
    void next();
    void previous() { seekTo(0); }
    // From where it is, or to a point, in microseconds.
    void seek(qint64 offset) { seekTo(m_position * 1000 + offset); }
    void seekTo(qint64 microseconds);
    // Only a seek in the tune playing now, which this names, to a point in it.
    void seekTo(const QString &tune, qint64 microseconds);
    QString tuneId() const;

    // The window's player moved in the tune, to here in milliseconds.
    Q_INVOKABLE void moved(qint64 position) { emit seeked(position * 1000); }

signals:
    void changed();
    void pauseAsked(bool paused);
    void seekAsked(qint64 position);
    void raiseAsked();
    void quitAsked();
    // A move in the tune, in microseconds, which the bus is told of.
    void seeked(qint64 position);

private:
    // Tells the bus what has changed since it was last told.
    void announce();

    Flow *m_flow;
    bool m_paused = false;
    bool m_stopped = false;
    qint64 m_position = 0;
    qint64 m_duration = 0;
    QVariantMap m_told;
    bool m_published = false;
    // Every tune played this run counts one up, so no two share an ID.
    QUrl m_tune;
    int m_tunes = 0;
};

#include "mpris.h"

#include <QCoreApplication>
#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>

#include "flow.h"
#include "genres.h"

namespace {

const QString path = "/org/mpris/MediaPlayer2";

// org.mpris.MediaPlayer2: the app itself.
class Root : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2")
    Q_PROPERTY(bool CanQuit READ yes)
    Q_PROPERTY(bool CanRaise READ yes)
    Q_PROPERTY(bool HasTrackList READ no)
    Q_PROPERTY(QString Identity READ identity)
    Q_PROPERTY(QString DesktopEntry READ desktopEntry)
    Q_PROPERTY(QStringList SupportedUriSchemes READ none)
    Q_PROPERTY(QStringList SupportedMimeTypes READ none)

public:
    explicit Root(Mpris *mpris) : QDBusAbstractAdaptor(mpris), m_mpris(mpris) {}
    bool yes() const { return true; }
    bool no() const { return false; }
    QString identity() const { return "Flowtunes"; }
    QString desktopEntry() const { return "flowtunes"; }
    QStringList none() const { return {}; }

public slots:
    void Raise() { emit m_mpris->raiseAsked(); }
    void Quit() { emit m_mpris->quitAsked(); }

private:
    Mpris *m_mpris;
};

// org.mpris.MediaPlayer2.Player: the tune playing, and what's done with it.
class Player : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.mpris.MediaPlayer2.Player")
    Q_PROPERTY(QString PlaybackStatus READ playbackStatus)
    Q_PROPERTY(double Rate READ one)
    Q_PROPERTY(double MinimumRate READ one)
    Q_PROPERTY(double MaximumRate READ one)
    Q_PROPERTY(double Volume READ one)
    Q_PROPERTY(QVariantMap Metadata READ metadata)
    Q_PROPERTY(qlonglong Position READ position)
    Q_PROPERTY(bool CanGoNext READ hasTune)
    Q_PROPERTY(bool CanGoPrevious READ hasTune)
    Q_PROPERTY(bool CanPlay READ yes)
    Q_PROPERTY(bool CanPause READ hasTune)
    Q_PROPERTY(bool CanSeek READ hasTune)
    Q_PROPERTY(bool CanControl READ yes)

public:
    explicit Player(Mpris *mpris) : QDBusAbstractAdaptor(mpris), m_mpris(mpris) {
        connect(mpris, &Mpris::seeked, this, &Player::Seeked);
    }
    QString playbackStatus() const { return m_mpris->playbackStatus(); }
    double one() const { return 1; }
    QVariantMap metadata() const { return m_mpris->metadata(); }
    qlonglong position() const { return m_mpris->position() * 1000; }
    bool hasTune() const { return m_mpris->hasTune(); }
    bool yes() const { return true; }

public slots:
    void Play() { m_mpris->play(); }
    void Pause() { m_mpris->pause(); }
    void PlayPause() { m_mpris->playPause(); }
    void Stop() { m_mpris->stop(); }
    void Next() { m_mpris->next(); }
    void Previous() { m_mpris->previous(); }
    void Seek(qlonglong offset) { m_mpris->seek(offset); }
    void SetPosition(const QDBusObjectPath &tune, qlonglong position) { m_mpris->seekTo(tune.path(), position); }
    void OpenUri(const QString &) {}

signals:
    void Seeked(qlonglong position);

private:
    Mpris *m_mpris;
};

} // namespace

Mpris::Mpris(Flow *flow, QObject *parent) : QObject(parent), m_flow(flow) {
    new Root(this);
    new Player(this);
    connect(m_flow, &Flow::changed, this, [this] {
        if (m_flow->track() != m_tune) {
            m_tune = m_flow->track();
            ++m_tunes;
        }
        announce();
    });
    connect(this, &Mpris::changed, this, &Mpris::announce);
}

bool Mpris::publish(const QString &name) {
    QDBusConnection bus = QDBusConnection::sessionBus();
    const QString service = "org.mpris.MediaPlayer2." + name;
    m_published = bus.registerObject(path, this, QDBusConnection::ExportAdaptors)
                  && (bus.registerService(service)
                      || bus.registerService(service + ".instance" + QString::number(QCoreApplication::applicationPid())));
    m_told = {};
    announce();
    return m_published;
}

void Mpris::setPaused(bool paused) {
    if (paused == m_paused)
        return;
    m_paused = paused;
    if (!paused)
        m_stopped = false;
    emit changed();
}

void Mpris::setPosition(qint64 position) {
    m_position = position;
}

void Mpris::setDuration(qint64 duration) {
    if (duration == m_duration)
        return;
    m_duration = duration;
    emit changed();
}

bool Mpris::hasTune() const { return !m_flow->track().isEmpty(); }

QString Mpris::playbackStatus() const { return !hasTune() || m_stopped ? "Stopped" : m_paused ? "Paused" : "Playing"; }

QString Mpris::tuneId() const {
    return hasTune() ? QString("/org/flowtunes/tune/%1").arg(m_tunes) : "/org/mpris/MediaPlayer2/TrackList/NoTrack";
}

QVariantMap Mpris::metadata() const {
    if (!hasTune())
        return {{"mpris:trackid", QVariant::fromValue(QDBusObjectPath(tuneId()))}};
    QVariantMap tune{
        {"mpris:trackid", QVariant::fromValue(QDBusObjectPath(tuneId()))},
        {"xesam:title", m_flow->title()},
        {"xesam:artist", QStringList{"Flowtunes"}},
        {"xesam:album", Genres::name(m_flow->genre())},
        {"xesam:genre", QStringList{Genres::name(m_flow->genre())}},
        {"xesam:url", m_flow->track().toString()},
    };
    if (m_flow->bpm() > 0)
        tune["xesam:audioBPM"] = m_flow->bpm();
    if (m_duration > 0)
        tune["mpris:length"] = m_duration * 1000;
    return tune;
}

void Mpris::next() {
    if (hasTune())
        m_flow->next();
}

void Mpris::seekTo(qint64 microseconds) {
    if (hasTune())
        emit seekAsked(qBound<qint64>(0, microseconds / 1000, m_duration));
}

void Mpris::seekTo(const QString &tune, qint64 microseconds) {
    // A point outside the tune is left alone, as the spec has it.
    if (tune == tuneId() && microseconds >= 0 && microseconds <= m_duration * 1000)
        seekTo(microseconds);
}

void Mpris::stop() {
    if (!hasTune())
        return;
    emit pauseAsked(true);
    seekTo(0);
    m_stopped = true;
    emit changed();
}

void Mpris::announce() {
    if (!m_published)
        return;
    // Position isn't among them: it's asked for when it's wanted.
    const QVariantMap now{{"PlaybackStatus", playbackStatus()}, {"Metadata", metadata()},
                          {"CanGoNext", hasTune()}, {"CanGoPrevious", hasTune()},
                          {"CanPause", hasTune()}, {"CanSeek", hasTune()}};
    QVariantMap news;
    for (auto it = now.begin(); it != now.end(); ++it)
        if (m_told.value(it.key()) != it.value())
            news[it.key()] = it.value();
    if (news.isEmpty())
        return;
    m_told = now;
    QDBusMessage signal = QDBusMessage::createSignal(path, "org.freedesktop.DBus.Properties", "PropertiesChanged");
    signal << "org.mpris.MediaPlayer2.Player" << news << QStringList();
    QDBusConnection::sessionBus().send(signal);
}

#include "mpris.moc"

#include "mpris.h"

#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusMessage>

#include "backend.h"

namespace {
const QString objectPath = QStringLiteral("/org/mpris/MediaPlayer2");
const QString playerInterface = QStringLiteral("org.mpris.MediaPlayer2.Player");
}

Mpris::Mpris(Backend *backend, QObject *parent, const QDBusConnection &bus)
    : QObject(parent), m_backend(backend), m_bus(bus) {
    new MprisRoot(this);
    new MprisPlayer(this);

    // Only once a video or song has played: a window showing photos isn't a
    // player, and would take the media keys from the one that is.
    if (backend->playerReady())
        start();
    else
        connect(backend, &Backend::playerReadyChanged, this, &Mpris::start, Qt::SingleShotConnection);
}

void Mpris::start() {
    Backend *backend = m_backend;
    auto *player = findChild<MprisPlayer *>();
    if (!m_bus.isConnected() || !m_service.isEmpty())
        return;
    const QString name = QStringLiteral("org.mpris.MediaPlayer2.omaview.instance%1").arg(QCoreApplication::applicationPid());
    if (!m_bus.registerObject(objectPath, this))
        return;
    if (!m_bus.registerService(name)) {
        m_bus.unregisterObject(objectPath);
        return;
    }
    m_service = name;

    // Clients cache properties and listen for these rather than polling.
    connect(backend, &Backend::playingChanged, this,
            [this] { propertiesChanged(playerInterface, {{"PlaybackStatus", playbackStatus()}}); });
    connect(backend, &Backend::statusChanged, this,
            [this] { propertiesChanged(playerInterface, {{"PlaybackStatus", playbackStatus()}}); });
    auto media = [this] {
        const bool playable = m_backend->hasMedia() && !m_backend->isPicture();
        propertiesChanged(playerInterface, {{"Metadata", metadata()},
                                            {"PlaybackStatus", playbackStatus()},
                                            {"CanGoNext", m_backend->playlistIndex() + 1 < m_backend->playlistCount()},
                                            {"CanGoPrevious", m_backend->playlistIndex() > 0},
                                            {"CanPlay", playable},
                                            {"CanPause", playable},
                                            {"CanSeek", m_backend->seekable()}});
    };
    connect(backend, &Backend::mediaChanged, this, media);
    connect(backend, &Backend::metadataChanged, this, media);
    connect(backend, &Backend::durationChanged, this, media);
    connect(backend, &Backend::playlistChanged, this, media);
    connect(backend, &Backend::seekableChanged, this, media);
    connect(backend, &Backend::volumeChanged, this, [this] {
        propertiesChanged(playerInterface, {{"Volume", m_backend->muted() ? 0.0 : m_backend->volume()}});
    });
    connect(backend, &Backend::rateChanged, this, [this] { propertiesChanged(playerInterface, {{"Rate", m_backend->rate()}}); });
    connect(backend, &Backend::seeked, player, [player](qint64 ms) { emit player->Seeked(ms * 1000); });
}

Mpris::~Mpris() {
    if (m_service.isEmpty())
        return;
    m_bus.unregisterService(m_service);
    m_bus.unregisterObject(objectPath);
}

QString Mpris::playbackStatus() const {
    if (!m_backend->hasMedia() || m_backend->isPicture() || m_backend->ended() || m_backend->stopped())
        return QStringLiteral("Stopped");
    return m_backend->playing() ? QStringLiteral("Playing") : QStringLiteral("Paused");
}

QVariantMap Mpris::metadata() const {
    if (!m_backend->hasMedia())
        return {};
    // A track id that changes with the file, so clients see a new track.
    const QString id = QStringLiteral("/org/mpris/MediaPlayer2/omaview/track/t%1")
                           .arg(qHash(m_backend->source().toString()), 0, 16);
    QVariantMap map{{"mpris:trackid", QVariant::fromValue(QDBusObjectPath(id))},
                    {"xesam:title", m_backend->title()},
                    {"xesam:url", m_backend->source().toString()}};
    if (m_backend->duration() > 0)
        map.insert("mpris:length", qlonglong(m_backend->duration() * 1000));
    if (!m_backend->artist().isEmpty())
        map.insert("xesam:artist", QStringList{m_backend->artist()});
    return map;
}

void Mpris::propertiesChanged(const QString &interface, const QVariantMap &changed) {
    QDBusMessage signal = QDBusMessage::createSignal(objectPath, QStringLiteral("org.freedesktop.DBus.Properties"),
                                                     QStringLiteral("PropertiesChanged"));
    signal << interface << changed << QStringList();
    m_bus.send(signal);
}

MprisRoot::MprisRoot(Mpris *parent) : QDBusAbstractAdaptor(parent), m_mpris(parent) {}

void MprisRoot::Raise() {
    emit m_mpris->backend()->raiseRequested();
}

void MprisRoot::Quit() {
    m_mpris->backend()->close();
    QCoreApplication::quit();
}

MprisPlayer::MprisPlayer(Mpris *parent) : QDBusAbstractAdaptor(parent), m_mpris(parent) {}

QString MprisPlayer::playbackStatus() const { return m_mpris->playbackStatus(); }
double MprisPlayer::rate() const { return m_mpris->backend()->rate(); }
void MprisPlayer::setRate(double rate) { m_mpris->backend()->changeRate(rate - m_mpris->backend()->rate()); }
QVariantMap MprisPlayer::metadata() const { return m_mpris->metadata(); }
double MprisPlayer::volume() const { return m_mpris->backend()->muted() ? 0.0 : m_mpris->backend()->volume(); }
void MprisPlayer::setVolume(double volume) { m_mpris->backend()->setVolume(volume); }
qlonglong MprisPlayer::position() const { return m_mpris->backend()->position() * 1000; }
bool MprisPlayer::canGoNext() const { return m_mpris->backend()->playlistIndex() + 1 < m_mpris->backend()->playlistCount(); }
bool MprisPlayer::canGoPrevious() const { return m_mpris->backend()->playlistIndex() > 0; }
bool MprisPlayer::canPlay() const { return m_mpris->backend()->hasMedia() && !m_mpris->backend()->isPicture(); }
bool MprisPlayer::canPause() const { return m_mpris->backend()->hasMedia() && !m_mpris->backend()->isPicture(); }
bool MprisPlayer::canSeek() const { return m_mpris->backend()->seekable(); }

void MprisPlayer::Next() { m_mpris->backend()->next(); }
void MprisPlayer::Previous() { m_mpris->backend()->previous(); }
void MprisPlayer::Pause() { m_mpris->backend()->pause(); }
void MprisPlayer::PlayPause() { m_mpris->backend()->togglePlay(); }
void MprisPlayer::Stop() { m_mpris->backend()->stop(); }
void MprisPlayer::Play() { m_mpris->backend()->play(); }
void MprisPlayer::Seek(qlonglong offset) { m_mpris->backend()->seekBy(offset / 1000); }

void MprisPlayer::SetPosition(const QDBusObjectPath &track, qlonglong position) {
    // The specification ignores a position for a track that isn't current.
    if (track.path() != m_mpris->metadata().value("mpris:trackid").value<QDBusObjectPath>().path())
        return;
    if (position < 0 || (m_mpris->backend()->duration() > 0 && position / 1000 > m_mpris->backend()->duration()))
        return;
    m_mpris->backend()->seek(position / 1000);
}

void MprisPlayer::OpenUri(const QString &uri) {
    m_mpris->backend()->open({uri});
}

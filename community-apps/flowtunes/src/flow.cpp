#include "flow.h"

#include <QDateTime>
#include <QDir>
#include <QEventLoopLocker>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QProcess>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QStringDecoder>
#include <QtEndian>
#include <algorithm>
#include <memory>

#include "genres.h"
#include "models.h"

namespace {

QJsonObject parse(const QByteArray &body) { return QJsonDocument::fromJson(body).object(); }

// Keeps the app running for as long as the request it's given to is out,
// even when its window has closed.
struct Stay : QObject {
    using QObject::QObject;
    QEventLoopLocker locker;
};

} // namespace

Flow::Flow(Models *models, const QString &musicFolder, QObject *parent)
    : QObject(parent),
      m_models(models),
      m_musicFolder(!musicFolder.isEmpty() ? musicFolder : QStandardPaths::writableLocation(QStandardPaths::MusicLocation)) {
    // The model's server says how a job is going only when asked.
    m_poll.setSingleShot(true);
    m_poll.setInterval(500);
    connect(&m_poll, &QTimer::timeout, this, &Flow::poll);
    m_again.setSingleShot(true);
    connect(&m_again, &QTimer::timeout, this, [this] { pump(); });
    m_lastVocals = m_models->vocals();
    connect(m_models, &Models::changed, this, [this] {
        const bool vocals = m_models->vocals();
        if (vocals != m_lastVocals) {
            m_lastVocals = vocals;
            if (!m_genre.isEmpty() && m_lyrics) {
                const Track playing = m_current;
                const int number = m_number;
                reset();
                m_current = playing;
                m_number = number;
                gather();
                emit changed();
            }
        }
        pump();
    });
    m_lyrics = QSettings().value("lyrics", false).toBool();
    // A model that takes its start and then stays stopped says nothing more,
    // so it's given a while and then called what it is.
    m_patience.setSingleShot(true);
    connect(&m_patience, &QTimer::timeout, this, [this] {
        if (m_genre.isEmpty() || !m_asked)
            return;
        const QString state = m_models->state();
        if (m_models->working() || state == "starting") {
            m_patience.start(startGraceMs);
        } else if (state == "installed") {
            m_stalled = true;
            pump();
        }
    });
}

QStringList Flow::genres() const { return Genres::ids(); }

QString Flow::lastGenre() const {
    const QString last = QSettings().value("genre").toString();
    return Genres::has(last) ? last : QString();
}

void Flow::play(const QString &genre) {
    if (!Genres::has(genre) || (genre == m_genre && m_error.isEmpty()))
        return;
    reset();
    m_genre = genre;
    QSettings().setValue("genre", genre);
    gather();
    emit changed();
    pump();
}

bool Flow::effectiveLyrics() const { return m_lyrics && m_models->vocals(); }

void Flow::gather() {
    // The tunes made before play first, in a new order every time: with
    // lyrics on (and a vocal model), every file but those named as instrumental,
    // and otherwise only those.
    const bool sung = effectiveLyrics();
    const QDir tunes(folder(m_genre));
    for (const QString &tune : tunes.entryList({"*.mp3"}, QDir::Files))
        if (sungOf(tune) == sung && tunes.filePath(tune) != m_current.path)
            m_library << tunes.filePath(tune);
    std::shuffle(m_library.begin(), m_library.end(), *QRandomGenerator::global());
}

void Flow::setLyrics(bool lyrics) {
    if (lyrics == m_lyrics)
        return;
    m_lyrics = lyrics;
    QSettings().setValue("lyrics", lyrics);
    if (!m_genre.isEmpty()) {
        const Track playing = m_current;
        const int number = m_number;
        reset();
        m_current = playing;
        m_number = number;
        gather();
    }
    emit changed();
    pump();
}

void Flow::stop() {
    if (m_genre.isEmpty())
        return;
    reset();
    m_genre.clear();
    emit changed();
}

void Flow::next() {
    if (m_genre.isEmpty())
        return;
    m_unplayed = 0;
    advance();
}

QString Flow::folder(const QString &genre) const { return m_musicFolder + "/" + Genres::name(genre); }

QString Flow::fileName(const QDateTime &when, int bpm, const QString &key, bool lyrics) {
    QString name = when.toString("yyyyMMdd-HHmmss");
    if (bpm > 0)
        name += QString("-%1bpm").arg(bpm);
    // A key as the model says it, "F# minor", with nothing a file name can't hold.
    static const QRegularExpression unfit("[^A-Za-z0-9#]+");
    const QString plain = QString(key).replace(unfit, "-");
    if (!plain.isEmpty() && plain != "-")
        name += "-" + plain;
    return name + (lyrics ? "" : "-instrumental") + ".mp3";
}

int Flow::bpmOf(const QString &fileName) {
    static const QRegularExpression tempo("^\\d{8}-\\d{6}-(\\d+)bpm");
    return tempo.match(fileName).captured(1).toInt();
}

QString Flow::keyOf(const QString &fileName) {
    static const QRegularExpression key("^\\d{8}-\\d{6}(?:-\\d+bpm)?-([A-G][A-Za-z0-9#-]*?)(?:-instrumental)?(?:_\\d+)?\\.mp3$");
    return key.match(fileName).captured(1).replace('-', ' ');
}

int Flow::sungLines(const QString &lyrics) {
    int sung = 0;
    for (const QString &line : lyrics.split('\n'))
        if (!line.trimmed().isEmpty() && !line.trimmed().startsWith('['))
            ++sung;
    return sung;
}

QString Flow::hookOf(const QString &lyrics) {
    static const QRegularExpression loose("^[\\s\"'“”‘’(]+|[\\s\"'“”‘’),.;:!?…–—-]+$");
    QStringList sung;
    QHash<QString, int> times;
    for (const QString &line : lyrics.split('\n')) {
        const QString words = QString(line).remove(loose);
        if (words.isEmpty() || line.trimmed().startsWith('['))
            continue;
        sung << words;
        ++times[words.toCaseFolded()];
    }
    QString hook;
    for (const QString &line : sung)
        if (hook.isEmpty() || times.value(line.toCaseFolded()) > times.value(hook.toCaseFolded()))
            hook = line;
    // A long line is cut between words where it has them.
    constexpr int longest = 40;
    if (hook.size() > longest) {
        const qsizetype space = hook.lastIndexOf(' ', longest);
        hook = hook.left(space > longest / 3 ? space : longest).remove(loose);
    }
    return hook;
}

namespace {

// An ID3v2 size: 28 bits, seven to a byte.
quint32 syncsafe(const char *bytes) {
    quint32 size = 0;
    for (int i = 0; i < 4; ++i)
        size = size << 7 | (bytes[i] & 0x7f);
    return size;
}

QByteArray syncsafe(quint32 size) {
    QByteArray bytes(4, 0);
    for (int i = 0; i < 4; ++i)
        bytes[3 - i] = char(size >> (7 * i) & 0x7f);
    return bytes;
}

} // namespace

QByteArray Flow::titled(const QByteArray &mp3, const QString &title) {
    qsizetype sound = 0;
    if (mp3.startsWith("ID3") && mp3.size() >= 10)
        sound = 10 + syncsafe(mp3.constData() + 6) + (mp3[5] & 0x10 ? 10 : 0);
    // ID3v2.4, with the name as UTF-8.
    const QByteArray text = '\x03' + title.toUtf8();
    const QByteArray frame = "TIT2" + syncsafe(text.size()) + QByteArray(2, 0) + text;
    return "ID3" + QByteArray("\x04\x00\x00", 3) + syncsafe(frame.size()) + frame + mp3.mid(sound);
}

QString Flow::titleOf(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const QByteArray head = file.read(10);
    // ID3v2.3 and 2.4; 2.2 names its frames differently, and is long gone.
    if (head.size() < 10 || !head.startsWith("ID3") || head[3] < 3)
        return {};
    const bool four = head[3] >= 4;
    QByteArray tag = file.read(qMin<quint32>(syncsafe(head.constData() + 6), 1 << 20));
    // A whole tag of 2.3 written unsynchronised has a nought after every 0xff.
    const auto restore = [](QByteArray bytes) { return bytes.replace(QByteArray("\xff\x00", 2), "\xff"); };
    if (!four && head[5] & 0x80)
        tag = restore(tag);
    qsizetype at = 0;
    if (head[5] & 0x40 && tag.size() >= 4)
        at = four ? syncsafe(tag.constData()) : 4 + qFromBigEndian<quint32>(tag.constData());
    while (at >= 0 && at + 10 <= tag.size() && tag[at] != 0) {
        const char *size = tag.constData() + at + 4;
        const qsizetype length = four ? syncsafe(size) : qFromBigEndian<quint32>(size);
        QByteArray body = tag.mid(at + 10, length);
        // 2.4 marks it frame by frame, and may put the frame's length ahead of its text.
        const char format = tag[at + 9];
        if (four && (format & 0x02 || head[5] & 0x80))
            body = restore(body);
        if (four && format & 0x01)
            body.remove(0, 4);
        if (tag.mid(at, 4) == "TIT2" && body.size() > 1) {
            const QByteArray text = body.mid(1);
            QString title;
            switch (body[0]) {
            case 0: title = QString::fromLatin1(text); break;
            case 1: // UTF-16 behind its byte order mark
                title = QStringDecoder(text.startsWith("\xff\xfe") ? QStringConverter::Utf16LE : QStringConverter::Utf16BE)(text.mid(2));
                break;
            case 2: title = QStringDecoder(QStringConverter::Utf16BE)(text); break;
            default: title = QString::fromUtf8(text);
            }
            // A frame may hold several, each ended by a nought: the first is the name.
            return title.section(QChar(0), 0, 0).trimmed();
        }
        at += 10 + length;
    }
    return {};
}

bool Flow::sungOf(const QString &fileName) {
    static const QRegularExpression played("-instrumental(?:_\\d+)?\\.mp3$");
    return !played.match(fileName).hasMatch();
}

void Flow::retry() {
    if (m_error.isEmpty())
        return;
    m_error.clear();
    m_failures = 0;
    m_unplayed = 0;
    m_trouble.clear();
    emit changed();
    if (m_current.path.isEmpty() && !m_queue.isEmpty())
        advance();
    else
        pump(true);
}

void Flow::playbackFailed(const QString &why) {
    if (m_current.path.isEmpty())
        return;
    // A file that's broken or gone is one tune; three in a row is the sound itself.
    if (++m_unplayed < 3) {
        advance();
        return;
    }
    m_current = {};
    m_error = tr("The tune couldn't be played: %1").arg(why);
    emit changed();
}

QNetworkReply *Flow::send(const QString &method, const QString &path, const QJsonObject &body) {
    QNetworkRequest request(QUrl(m_models->origin() + path));
    request.setRawHeader("Authorization", "Bearer " + m_models->key());
    // A server that has stopped answering fails the tune rather than hanging the flow.
    request.setTransferTimeout(30000);
    if (method == "GET")
        return m_network.get(request);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    return m_network.post(request, QJsonDocument(body).toJson(QJsonDocument::Compact));
}

void Flow::pump(bool again) {
    // Two tunes ready behind the one playing: a skip never has to wait, and
    // the model makes a tune many times faster than it plays.
    if (m_genre.isEmpty() || m_filling || m_again.isActive() || !m_error.isEmpty() || m_queue.size() >= tunesAhead)
        return;
    // A tune made before needs no model, only its shape read.
    if (!m_library.isEmpty()) {
        Track track;
        track.path = m_library.takeFirst();
        const QString name = QFileInfo(track.path).fileName();
        track.bpm = bpmOf(name);
        track.key = keyOf(name);
        // One without a name of its own is named for its file, the same every time.
        track.title = titleOf(track.path);
        if (track.title.isEmpty()) {
            QRandomGenerator named(quint32(qHash(name, 0)));
            track.title = Genres::title(m_genre, named);
        }
        m_filling = true;
        shape(track);
        return;
    }
    const QString state = m_models->state();
    if (state == "ready") {
        compose();
    } else if (state == "installed" && !m_models->working()) {
        if (!m_asked || again) {
            m_asked = true;
            m_stalled = false;
            m_patience.start(startGraceMs);
            m_models->start();
        } else if ((m_stalled || !m_models->error().isEmpty()) && m_current.path.isEmpty()) {
            m_error = !m_models->error().isEmpty() ? m_models->error() : tr("%1 didn't start").arg(m_models->name());
            emit changed();
        }
    }
    // A blocked model waits for the user: the window offers to stop the
    // models in its way, which is theirs to decide.
}

void Flow::compose() {
    m_composing = true;
    m_filling = true;
    emit changed();
    // An instrumental-only model has no lyric-writing stage: render straight from the caption.
    if (!m_models->vocals()) {
        Track track;
        track.made = true;
        track.title = Genres::title(m_genre, *QRandomGenerator::global());
        render(track, {{"caption", Genres::caption(m_genre, *QRandomGenerator::global(), false)}, {"duration", trackSeconds}}, false);
        return;
    }
    // The model's language model writes the tune out first: how it sounds,
    // its tempo and key, and its notes, which go back to be rendered as they are.
    // Left without lyrics it writes its own, in the language asked for.
    const bool sung = effectiveLyrics();
    submit("/lm", {{"caption", Genres::caption(m_genre, *QRandomGenerator::global(), sung)},
                   {"lyrics", sung ? "" : "[Instrumental]"}, {"duration", trackSeconds},
                   {"vocal_language", m_language.isEmpty() ? QString("en") : m_language.section('-', 0, 0)}},
           [this, sung](const QByteArray &written) {
        const QJsonObject song = QJsonDocument::fromJson(written).array().first().toObject();
        if (song.isEmpty()) {
            fail(tr("The tune couldn't be made"));
            return;
        }
        // Whether a tune is sung is the model's to decide, whatever it's
        // asked, so one written without words is written again.
        if (sung && sungLines(song.value("lyrics").toString()) < 2) {
            if (++m_unsung < lyricsTries)
                compose();
            else
                fail(tr("The model wrote no lyrics"));
            return;
        }
        m_unsung = 0;
        Track track;
        track.made = true;
        track.bpm = song.value("bpm").toInt();
        track.key = song.value("keyscale").toString();
        track.title = sung ? hookOf(song.value("lyrics").toString()) : QString();
        if (track.title.isEmpty())
            track.title = Genres::title(m_genre, *QRandomGenerator::global());
        render(track, song, sung);
    });
}

void Flow::render(Track track, const QJsonObject &body, bool sung) {
    submit("/synth", body, [this, track, sung](const QByteArray &rendered) mutable {
        // Parts between lines of a boundary, which the first line is:
        // the MP3 is the first part's body.
        const QByteArray boundary = "\r\n" + rendered.left(rendered.indexOf("\r\n"));
        const qsizetype start = rendered.indexOf("\r\n\r\n") + 4;
        const QByteArray sound = start < 4 ? QByteArray() : rendered.mid(start, rendered.indexOf(boundary, start) - start);
        if (sound.isEmpty()) {
            fail(tr("The tune couldn't be made"));
            return;
        }
        const QByteArray named = titled(sound, track.title);
        // Among the genre's tunes, under a name none of them has, and
        // whole or not at all.
        const QString tunes = folder(m_genre);
        QString name = fileName(QDateTime::currentDateTime(), track.bpm, track.key, sung);
        for (int copy = 2; QFile::exists(tunes + "/" + name); ++copy)
            name = name.section('.', 0, -2).section('_', 0, 0) + QString("_%1.mp3").arg(copy);
        track.path = tunes + "/" + name;
        QSaveFile file(track.path);
        file.setDirectWriteFallback(false);
        if (!QDir().mkpath(tunes) || !file.open(QIODevice::WriteOnly) || file.write(named) != named.size() || !file.commit()) {
            fail(tr("Couldn't save the tune in %1").arg(tunes));
            return;
        }
        shape(track);
    });
}

void Flow::submit(const QString &path, const QJsonObject &body, Done done) {
    m_done = std::move(done);
    QNetworkReply *reply = send("POST", path, body);
    // The app stays until the job has a name, so one handed over as the
    // window closes can still be called off.
    new Stay(reply);
    connect(reply, &QNetworkReply::finished, this, [this, reply, run = m_run] {
        reply->deleteLater();
        const QString id = parse(reply->readAll()).value("id").toString();
        if (run != m_run) {
            // The flow moved on while the job was being handed over.
            if (!id.isEmpty())
                cancelJob(id);
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            fail(tr("The music model didn't answer: %1").arg(reply->errorString()));
        } else if (id.isEmpty()) {
            fail(tr("The tune couldn't be made"));
        } else {
            m_job = id;
            m_poll.start();
        }
    });
}

void Flow::poll() {
    if (m_job.isEmpty())
        return;
    QNetworkReply *reply = send("GET", "/job?id=" + m_job);
    connect(reply, &QNetworkReply::finished, this, [this, reply, run = m_run] {
        reply->deleteLater();
        if (run != m_run)
            return;
        if (reply->error() != QNetworkReply::NoError) {
            fail(tr("The music model stopped answering: %1").arg(reply->errorString()));
            return;
        }
        const QString status = parse(reply->readAll()).value("status").toString();
        if (status == "failed" || status == "cancelled") {
            fail(tr("The tune couldn't be made"));
        } else if (status != "done") {
            m_poll.start();
        } else {
            QNetworkReply *result = send("GET", "/job?id=" + m_job + "&result=1");
            connect(result, &QNetworkReply::finished, this, [this, result, run] {
                result->deleteLater();
                if (run != m_run)
                    return;
                if (result->error() != QNetworkReply::NoError) {
                    fail(tr("The music model stopped answering: %1").arg(result->errorString()));
                    return;
                }
                m_job.clear();
                const Done done = std::move(m_done);
                done(result->readAll());
            });
        }
    });
}

void Flow::cancelJob(const QString &id) {
    // The app stays until the model has heard, even when its window closes,
    // so a tune nobody will hear doesn't keep the GPU busy.
    QNetworkReply *reply = send("POST", "/job?id=" + id + "&cancel=1");
    new Stay(reply);
    connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
}

QVariantList Flow::shapeOf(const QByteArray &samples) {
    // Each bar is how loud its share of the tune is on the whole, against
    // the loudest of them: a tune's peaks are all alike, its parts are not.
    const qsizetype count = samples.size() / 2;
    QList<qint64> sums(waveBars, 0), shares(waveBars, 0);
    for (qsizetype i = 0; i < count; ++i) {
        sums[i * waveBars / count] += std::abs(int(qFromLittleEndian<qint16>(samples.constData() + i * 2)));
        ++shares[i * waveBars / count];
    }
    QList<double> levels(waveBars, 0);
    for (int i = 0; i < waveBars; ++i)
        levels[i] = shares[i] > 0 ? double(sums[i]) / shares[i] : 0;
    const double loudest = *std::max_element(levels.begin(), levels.end());
    QVariantList wave;
    for (int i = 0; loudest > 0 && i < waveBars; ++i)
        wave << levels[i] / loudest;
    return wave;
}

void Flow::shape(Track track) {
    auto *sound = new QProcess(this);
    // The sound is boiled down as it arrives, a hundredth of a second to a
    // level, so a file hours long takes no more memory than a tune.
    auto levels = std::make_shared<QByteArray>();
    auto rest = std::make_shared<QByteArray>();
    const auto take = [sound, levels, rest] {
        constexpr qsizetype window = 80;
        *rest += sound->readAllStandardOutput();
        qsizetype at = 0;
        for (; at + window * 2 <= rest->size(); at += window * 2) {
            qint64 sum = 0;
            for (qsizetype i = 0; i < window; ++i)
                sum += std::abs(int(qFromLittleEndian<qint16>(rest->constData() + at + i * 2)));
            const qint16 level = qToLittleEndian<qint16>(qint16(sum / window));
            levels->append(reinterpret_cast<const char *>(&level), 2);
        }
        rest->remove(0, at);
    };
    connect(sound, &QProcess::readyReadStandardOutput, this, take);
    connect(sound, &QProcess::finished, this, [this, sound, track, take, levels, run = m_run](int code) mutable {
        sound->deleteLater();
        if (run != m_run)
            return;
        take();
        // A file from the folder that holds no sound, or is gone, is passed over.
        if (!track.made && (code != 0 || levels->isEmpty())) {
            m_filling = false;
            pump();
            return;
        }
        track.wave = shapeOf(*levels);
        enqueue(track);
    });
    // Without ffmpeg the tune still plays, with no shape to show.
    connect(sound, &QProcess::errorOccurred, this, [this, sound, track, run = m_run](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        sound->deleteLater();
        if (run == m_run)
            enqueue(track);
    });
    sound->setStandardErrorFile(QProcess::nullDevice());
    sound->start("ffmpeg", {"-loglevel", "error", "-i", track.path, "-ac", "1", "-ar", "8000", "-f", "s16le", "-"});
}

void Flow::enqueue(const Track &track) {
    // The model made a tune, so it's well; should it stop later, it's started again.
    if (m_composing) {
        m_failures = 0;
        m_trouble.clear();
        m_asked = false;
    }
    m_composing = false;
    m_filling = false;
    m_queue << track;
    // Nothing starts playing under an error: that waits to be asked again.
    if (m_current.path.isEmpty() && m_error.isEmpty()) {
        advance();
    } else {
        emit changed();
        pump();
    }
}

void Flow::advance() {
    m_current = {};
    if (!m_queue.isEmpty()) {
        m_current = m_queue.takeFirst();
        ++m_number;
    } else if (m_failures >= 2 && !m_filling && m_error.isEmpty()) {
        // The music has run out while the next tune kept failing.
        m_again.stop();
        m_error = m_trouble;
    }
    emit changed();
    pump();
}

void Flow::fail(const QString &error) {
    m_composing = false;
    m_filling = false;
    // A job that's given up on, one that timed out say, isn't left running.
    if (!m_job.isEmpty())
        cancelJob(m_job);
    m_job.clear();
    m_poll.stop();
    m_unsung = 0;
    m_trouble = error;
    // Once more by itself, starting the model again if it has stopped. A
    // second failure in a row is the user's to see, unless a tune is
    // playing: then it's tried again every so often, with nothing said.
    if (++m_failures < 2) {
        m_asked = false;
        m_again.start(retryDelayMs);
    } else if (m_current.path.isEmpty()) {
        m_error = error;
    } else {
        m_asked = false;
        m_again.start(retryDelayMs * 10);
    }
    emit changed();
}

void Flow::reset() {
    ++m_run;
    m_poll.stop();
    m_again.stop();
    m_patience.stop();
    m_failures = 0;
    m_unplayed = 0;
    m_unsung = 0;
    m_stalled = false;
    m_trouble.clear();
    if (!m_job.isEmpty())
        cancelJob(m_job);
    m_job.clear();
    m_done = nullptr;
    m_current = {};
    m_queue.clear();
    m_library.clear();
    m_number = 0;
    m_composing = false;
    m_filling = false;
    m_asked = false;
    m_error.clear();
}

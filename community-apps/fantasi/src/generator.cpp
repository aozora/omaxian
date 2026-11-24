#include "generator.h"
#include <QSettings>
#include <algorithm>
#include <memory>
#include <QSaveFile>
#include <QProcess>

#include "models.h"

#include <QBuffer>
#include <QDateTime>
#include <QImage>
#include <cmath>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImageReader>
#include <QPainter>
#include <QtEndian>
#include <sys/stat.h>
#include <utility>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QTemporaryFile>
#include <QUrl>

namespace {

QJsonObject parse(QNetworkReply *reply) { return QJsonDocument::fromJson(reply->readAll()).object(); }

// The server's error text: a string, or an object with a message.
QString errorText(const QJsonObject &body) {
    const QJsonValue error = body.value("error");
    return error.isObject() ? error.toObject().value("message").toString() : error.toString();
}

// The server's stages, named the way the window says them.
QString stageFor(const QString &server) {
    if (server == "sampling")
        return "sampling";
    if (server == "vae_decode" || server == "encoding" || server == "upscaling" || server == "adetailer")
        return "decoding";
    if (server == "queued" || server == "waiting")
        return "queued";
    return "conditioning";
}

// What a file the user makes may be read by: everyone their umask lets.
QFile::Permissions newFilePermissions() {
    const mode_t mask = ::umask(0);
    ::umask(mask);
    QFile::Permissions permissions = QFile::ReadOwner | QFile::WriteOwner;
    if (!(mask & S_IRGRP))
        permissions |= QFile::ReadGroup;
    if (!(mask & S_IROTH))
        permissions |= QFile::ReadOther;
    return permissions;
}

} // namespace

Generator::Generator(Models *models, const QString &folder, const QString &musicFolder, QObject *parent)
    : QObject(parent), m_models(models),
      m_folder(!folder.isEmpty() ? folder
                                 : QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + "/Generated"),
      m_musicFolder(!musicFolder.isEmpty() ? musicFolder
                                           : QStandardPaths::writableLocation(QStandardPaths::MusicLocation) + "/Generated") {
    // A job has no change signal of its own, so it is asked about while it
    // runs, and only then: a request at a time, half a second apart.
    // Often enough for a progress filled by time to move smoothly.
    m_tick.setInterval(250);
    connect(&m_tick, &QTimer::timeout, this, &Generator::remainingChanged);
    m_poll.setSingleShot(true);
    m_poll.setInterval(500);
    connect(&m_poll, &QTimer::timeout, this, &Generator::poll);

    // The server's defaults are the model's own steps, size and guidance.
    auto follow = [this] {
        const QString origin = m_models->state() == "ready" ? m_models->origin() : QString();
        if (origin == m_origin)
            return;
        m_origin = origin;
        m_key = m_models->key();
        m_defaults = {};
        emit defaultsChanged();
        if (!m_origin.isEmpty())
            fetchDefaults();
    };
    connect(m_models, &Models::changed, this, follow);
    follow();
}

Generator::~Generator() { m_poll.stop(); }

int Generator::defaultSteps() const {
    return m_defaults.value("sample_params").toObject().value("sample_steps").toInt(8);
}

QNetworkReply *Generator::send(const QString &method, const QString &path, const QJsonObject &body) {
    return request(m_origin, m_key, method, path, body);
}

QNetworkReply *Generator::sendJob(const QString &method, const QString &path, const QJsonObject &body) {
    return m_jobOrigin.isEmpty() ? send(method, path, body) : request(m_jobOrigin, m_jobKey, method, path, body);
}

QNetworkReply *Generator::request(const QString &origin, const QByteArray &key, const QString &method, const QString &path,
                                  const QJsonObject &body) {
    QNetworkRequest outgoing(QUrl(origin + path));
    outgoing.setRawHeader("Authorization", "Bearer " + key);
    outgoing.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    outgoing.setTransferTimeout(15000);
    if (method == "POST")
        return m_network.post(outgoing, QJsonDocument(body).toJson(QJsonDocument::Compact));
    return m_network.get(outgoing);
}

void Generator::fetchDefaults() {
    QNetworkReply *reply = send("GET", "/sdcpp/v1/capabilities");
    connect(reply, &QNetworkReply::finished, this, [this, reply, origin = m_origin] {
        reply->deleteLater();
        if (origin != m_origin || reply->error() != QNetworkReply::NoError)
            return;
        const QJsonObject capabilities = parse(reply);
        const QJsonObject byMode = capabilities.value("defaults_by_mode").toObject().value("img_gen").toObject();
        m_defaults = !byMode.isEmpty() ? byMode : capabilities.value("defaults").toObject();
        emit defaultsChanged();
    });
}

QSize Generator::fitMegapixel(int width, int height) {
    const double area = 1024.0 * 1024.0, aspect = double(width) / height;
    const int w = std::max(1, int(std::lround(std::sqrt(area * aspect) / 64))) * 64;
    const int h = std::max(1, int(std::lround(area / w / 64))) * 64;
    return {w, h};
}

Generator::Base Generator::prepareBase(const QString &path) {
    QImageReader reader(path);
    // A camera's picture stands the way it was taken.
    reader.setAutoTransform(true);
    const QSize size = reader.size();
    if (!size.isValid())
        return {};
    // A size the model works in, near a megapixel, goes as it is: Fantasi's
    // own images, which a change keeps pixel for pixel.
    const bool fits = size.width() % 64 == 0 && size.height() % 64 == 0
                   && double(size.width()) * size.height() <= 1.6 * 1024 * 1024
                   && double(size.width()) * size.height() >= 0.4 * 1024 * 1024;
    if (fits && reader.format() == "png" && reader.transformation() == QImageIOHandler::TransformationNone) {
        QFile file(path);
        if (file.open(QIODevice::ReadOnly))
            return {file.readAll(), size};
    }
    // Anything else is scaled to cover the nearest size in its own shape,
    // then cut to it from the middle.
    const QImage image = reader.read();
    if (image.isNull())
        return {};
    const QSize target = fitMegapixel(image.width(), image.height());
    const QImage scaled = image.scaled(target, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
    const QImage cropped = scaled.copy((scaled.width() - target.width()) / 2, (scaled.height() - target.height()) / 2,
                                       target.width(), target.height());
    QByteArray png;
    QBuffer buffer(&png);
    if (!buffer.open(QIODevice::WriteOnly) || !cropped.convertToFormat(QImage::Format_RGB32).save(&buffer, "PNG"))
        return {};
    return {png, target};
}

void Generator::generate(const QString &prompt, int width, int height, int steps, qint64 seed, const QStringList &baseUrls, bool edit) {
    if (busy() || prompt.trimmed().isEmpty())
        return;
    if (m_origin.isEmpty()) {
        m_error = tr("No image model is running");
        emit changed();
        return;
    }

    // The model's defaults, with what the window sets on top. A change goes
    // to a running edit model when the one in use isn't one, with that
    // server's own defaults.
    QJsonObject body = m_defaults;
    QString jobOrigin;
    if (!baseUrls.isEmpty() && !edit && !m_models->editOrigin().isEmpty()) {
        jobOrigin = m_models->editOrigin();
        body = {};
        edit = true;
    }
    if (baseUrls.size() > 1 && !edit) {
        m_error = tr("Only a model that edits can combine pictures");
        emit changed();
        return;
    }
    if (!baseUrls.isEmpty()) {
        QJsonArray pictures;
        QSize size;
        for (const QString &url : baseUrls.mid(0, maxBases)) {
            const Base base = prepareBase(QUrl(url).isLocalFile() ? QUrl(url).toLocalFile() : url);
            if (base.png.isEmpty()) {
                m_error = tr("Couldn't read the image to start from");
                emit changed();
                return;
            }
            pictures << QString::fromLatin1(base.png.toBase64());
            if (size.isEmpty())
                size = base.size;
        }
        if (edit) {
            body.insert("ref_images", pictures);
        } else {
            body.insert("init_image", pictures.first());
            body.insert("strength", baseStrength);
        }
        width = size.width();
        height = size.height();
    }
    QJsonObject sample = body.value("sample_params").toObject();
    if (steps > 0)
        sample.insert("sample_steps", steps);
    body.insert("sample_params", sample);
    // Only now, with the pictures read, does the job go to the edit model.
    // The job stays with the server it's sent to, though the model in use may
    // change while it runs.
    m_jobOrigin = jobOrigin.isEmpty() ? m_origin : jobOrigin;
    m_jobKey = jobOrigin.isEmpty() ? m_key : m_models->editKey();
    body.insert("prompt", prompt.trimmed());
    body.insert("width", width);
    body.insert("height", height);
    body.insert("seed", seed);
    body.insert("batch_count", 1);
    body.insert("preview", "proj");
    body.insert("preview_interval", 1);
    body.insert("output_format", "png");
    // The settings travel inside the PNG, which is how the history knows
    // each image's prompt and seed.
    body.insert("embed_image_metadata", true);

    m_prompt = prompt.trimmed();
    m_pending.clear();
    m_unposted.clear();
    m_error.clear();
    m_submitting = true;
    m_cancelling = false;
    m_stage = "queued";
    m_step = 0;
    m_totalSteps = sample.value("sample_steps").toInt(defaultSteps());
    m_previews = QStringList(m_totalSteps, QString());
    m_image.clear();
    m_locker = std::make_unique<QEventLoopLocker>();
    startClock(QString("%1/image/%2x%3").arg(m_models->modelId()).arg(width).arg(height));
    emit changed();

    m_video = false;
    m_song = false;
    submit("/sdcpp/v1/img_gen", body);
}

void Generator::submit(const QString &path, const QJsonObject &body) {
    QNetworkReply *reply = sendJob("POST", path, body);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        const QJsonObject answer = parse(reply);
        m_submitting = false;
        if (reply->error() != QNetworkReply::NoError || answer.value("id").toString().isEmpty()) {
            const QString said = errorText(answer);
            finish(!said.isEmpty() ? said
                                   : (m_song ? tr("The music model didn't answer: %1") : tr("The image model didn't answer: %1"))
                                         .arg(reply->errorString()));
            return;
        }
        m_job = answer.value("id").toString();
        // Cancelled while the job was being submitted.
        if (m_cancelling)
            sendJob("POST", jobPath("cancel"))->deleteLater();
        emit changed();
        m_poll.start();
    });
}

QSize Generator::fitVideo(int width, int height) {
    if (width <= 0 || height <= 0)
        return {864, 480};
    const double scale = std::sqrt(864.0 * 480.0 / (double(width) * height));
    auto step = [](double v) { return std::max(256, int(std::lround(v / 32.0)) * 32); };
    return {step(width * scale), step(height * scale)};
}

void Generator::makeVideo(const QString &prompt, int width, int height, const QString &firstFrameUrl, int seconds) {
    if (busy() || prompt.trimmed().isEmpty())
        return;
    const QString origin = m_models->videoOrigin();
    if (origin.isEmpty()) {
        m_error = tr("No video model is running");
        emit changed();
        return;
    }
    QJsonObject body;
    QSize size = fitVideo(width, height);
    m_firstFrame = {};
    if (!firstFrameUrl.isEmpty()) {
        const QString path = QUrl(firstFrameUrl).isLocalFile() ? QUrl(firstFrameUrl).toLocalFile() : firstFrameUrl;
        QImage picture(path);
        if (picture.isNull()) {
            m_error = tr("Couldn't read the image to start from");
            emit changed();
            return;
        }
        size = fitVideo(picture.width(), picture.height());
        // Filled to the clip's size and cut from the middle.
        const QImage scaled = picture.scaled(size, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
        picture = scaled.copy((scaled.width() - size.width()) / 2, (scaled.height() - size.height()) / 2, size.width(), size.height());
        QByteArray png;
        QBuffer buffer(&png);
        buffer.open(QIODevice::WriteOnly);
        picture.save(&buffer, "PNG");
        body.insert("init_image", QString::fromLatin1(png.toBase64()));
        m_firstFrame = picture;
    }
    body.insert("prompt", prompt.trimmed());
    body.insert("width", size.width());
    body.insert("height", size.height());
    body.insert("video_frames", std::clamp(seconds, 1, maxClipSeconds) * videoFps);
    body.insert("fps", videoFps);
    body.insert("seed", -1);
    body.insert("output_format", "webm");
    body.insert("vae_tiling_params", QJsonObject{{"enabled", true}});

    m_jobOrigin = origin;
    m_jobKey = m_models->videoKey();
    m_video = true;
    m_song = false;
    m_prompt = prompt.trimmed();
    m_pending.clear();
    m_unposted.clear();
    m_error.clear();
    m_submitting = true;
    m_cancelling = false;
    m_stage = "queued";
    m_step = 0;
    m_totalSteps = 0;
    m_previews.clear();
    m_image.clear();
    m_locker = std::make_unique<QEventLoopLocker>();
    startClock(QString("%1/clip/%2/%3x%4").arg(m_models->modelId()).arg(std::clamp(seconds, 1, maxClipSeconds)).arg(size.width()).arg(size.height()));
    emit changed();

    // The LoRAs the server lists are the ones the model is meant to run with,
    // like MiniMax H3's few-step one.
    QNetworkReply *reply = sendJob("GET", "/sdcpp/v1/capabilities");
    connect(reply, &QNetworkReply::finished, this, [this, reply, body]() mutable {
        reply->deleteLater();
        QJsonArray loras;
        for (const QJsonValue &lora : parse(reply).value("loras").toArray())
            loras << QJsonObject{{"path", lora.toObject().value("path").toString()}, {"multiplier", 1.0}};
        body.insert("lora", loras);
        if (m_cancelling) {
            finish();
            return;
        }
        submit("/sdcpp/v1/vid_gen", body);
    });
}

void Generator::makeSong(const QString &prompt, const QString &lyrics, int seconds, const QString &language) {
    if (busy() || prompt.trimmed().isEmpty())
        return;
    if (m_origin.isEmpty() || !m_models->music()) {
        m_error = tr("No music model is running");
        emit changed();
        return;
    }
    m_jobOrigin = m_origin;
    m_jobKey = m_key;
    m_video = false;
    m_song = true;
    const bool vocals = m_models->vocals();
    m_rendering = !vocals;
    m_lyrics.clear();
    m_prompt = prompt.trimmed();
    m_pending.clear();
    m_unposted.clear();
    m_error.clear();
    m_submitting = true;
    m_cancelling = false;
    // Vocal models write lyrics first, then render; instrumental models render directly.
    m_stage = vocals ? "conditioning" : "sampling";
    m_step = 0;
    m_totalSteps = vocals ? 2 : 1;
    m_previews.clear();
    m_image.clear();
    m_locker = std::make_unique<QEventLoopLocker>();
    emit changed();

    startClock(QString("%1/song/%2").arg(m_models->modelId()).arg(seconds));
    if (vocals) {
        // The model takes a language by its plain code: pt, not pt-BR.
        submit("/lm", {{"caption", m_prompt}, {"lyrics", lyrics.trimmed()}, {"duration", seconds},
                       {"vocal_language", language.section('-', 0, 0)}});
    } else {
        submit("/synth", {{"caption", m_prompt}, {"duration", seconds}});
    }
}

QString Generator::jobPath(const QString &action) const {
    if (m_song)
        return "/job?id=" + m_job + (action.isEmpty() ? QString() : "&" + action + "=1");
    return "/sdcpp/v1/jobs/" + m_job + (action.isEmpty() ? QString() : "/" + action);
}

void Generator::followSong(const QString &status) {
    if (status == "failed") {
        finish(tr("The song couldn't be made"));
    } else if (status == "cancelled") {
        finish();
    } else if (status != "done") {
        m_poll.start();
    } else {
        QNetworkReply *reply = sendJob("GET", jobPath("result"));
        connect(reply, &QNetworkReply::finished, this, [this, reply] {
            reply->deleteLater();
            const QByteArray body = reply->readAll();
            if (reply->error() != QNetworkReply::NoError) {
                finish(tr("The music model stopped answering: %1").arg(reply->errorString()));
            } else if (m_cancelling) {
                finish();
            } else if (!m_rendering) {
                // The song written out: its lyrics, tempo, key and notes,
                // which go back to be rendered as they are.
                const QJsonObject song = QJsonDocument::fromJson(body).array().first().toObject();
                if (song.isEmpty()) {
                    finish(tr("The song couldn't be made"));
                    return;
                }
                m_lyrics = song.value("lyrics").toString();
                m_rendering = true;
                m_job.clear();
                m_submitting = true;
                m_stage = "sampling";
                m_step = 1;
                emit changed();
                submit("/synth", song);
            } else {
                // Parts between lines of a boundary, which the first line
                // is: the MP3 is the first part's body.
                const QByteArray boundary = "\r\n" + body.left(body.indexOf("\r\n"));
                const qsizetype start = body.indexOf("\r\n\r\n") + 4;
                m_pending = start < 4 ? QByteArray() : body.mid(start, body.indexOf(boundary, start) - start);
                if (m_pending.isEmpty()) {
                    finish(tr("The song couldn't be made"));
                    return;
                }
                m_step = m_totalSteps;
                m_stage = "saving";
                // Remembered, so the next one as long knows from the start.
                QSettings().setValue("durations/" + m_durationKey, m_clock.elapsed() / 1000.0);
                emit changed();
                shapeSong();
            }
        });
    }
}

QString Generator::songTitle(const QString &lyrics, const QString &prompt) {
    QString first, chorus;
    bool inChorus = false;
    for (const QString &line : lyrics.split('\n')) {
        const QString words = line.trimmed();
        // A line in brackets names a part or how it's played, and isn't sung.
        if (words.startsWith('[')) {
            // Not a pre-chorus, which leads up to one.
            inChorus = words.startsWith("[chorus", Qt::CaseInsensitive);
        } else if (!words.isEmpty()) {
            if (first.isEmpty())
                first = words;
            if (inChorus) {
                chorus = words;
                break;
            }
        }
    }
    // Without words, what was asked for, up to its first comma or full stop.
    static const QRegularExpression pause("[,.;:\\n]");
    QString title = !chorus.isEmpty() ? chorus : !first.isEmpty() ? first : prompt.section(pause, 0, 0).simplified();
    static const QRegularExpression trailing("[\\s,.;:!?…-]+$");
    title.remove(trailing);
    return title.size() > 48 ? title.left(47).trimmed() + "…" : title;
}

QByteArray Generator::songWave(const QByteArray &samples) {
    // Each bar is how loud its share of the song is on the whole, against
    // the loudest of them: a song's peaks are all alike, its parts are not.
    // Without a sound to read (no ffmpeg), it lies flat.
    QByteArray wave(waveBars, '\0');
    const qsizetype count = samples.size() / 2;
    QList<qint64> sums(waveBars, 0);
    for (qsizetype i = 0; i < count; ++i)
        sums[i * waveBars / count] += std::abs(int(qFromLittleEndian<qint16>(samples.constData() + i * 2)));
    const qint64 loudest = *std::max_element(sums.begin(), sums.end());
    for (int i = 0; loudest > 0 && i < waveBars; ++i)
        wave[i] = char(sums[i] * 255 / loudest);
    return wave;
}

void Generator::cancel() {
    if (!busy() || m_cancelling)
        return;
    m_cancelling = true;
    // The server stops at its next checkpoint; the job is followed until it
    // says it has, since it may finish first.
    if (!m_job.isEmpty()) {
        QNetworkReply *reply = sendJob("POST", jobPath("cancel"));
        connect(reply, &QNetworkReply::finished, reply, &QObject::deleteLater);
    }
    emit changed();
}

void Generator::poll() {
    if (m_job.isEmpty())
        return;
    QNetworkReply *reply = sendJob("GET", jobPath());
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            const QString said = errorText(parse(reply));
            finish(!said.isEmpty() ? said
                                   : (m_song ? tr("The music model stopped answering: %1") : tr("The image model stopped answering: %1"))
                                         .arg(reply->errorString()));
            return;
        }
        if (m_song)
            followSong(parse(reply).value("status").toString());
        else
            follow(parse(reply));
    });
}

void Generator::follow(const QJsonObject &job) {
    const QString status = job.value("status").toString();
    const QJsonObject progress = job.value("progress").toObject();
    m_stage = stageFor(progress.value("stage").toString(status));
    if (progress.value("unit").toString() == "steps") {
        m_step = progress.value("completed").toInt(m_step);
        const int total = progress.value("total").toInt(m_totalSteps);
        if (total > 0 && total != m_totalSteps) {
            m_totalSteps = total;
            m_previews.resize(total);
        }
    }
    const QJsonObject preview = job.value("preview").toObject();
    const int previewStep = preview.value("step").toInt();
    if (previewStep >= 1 && previewStep <= m_previews.size() && !preview.value("b64_json").toString().isEmpty()) {
        m_previews[previewStep - 1] = "data:image/png;base64," + preview.value("b64_json").toString();
        m_image = m_previews[previewStep - 1];
    }

    if (status == "completed") {
        const QJsonObject result = job.value("result").toObject();
        const QJsonArray images = result.value("images").toArray();
        m_pending = QByteArray::fromBase64((m_video ? result.value("b64_json") : images.first().toObject().value("b64_json")).toString().toLatin1());
        if (m_pending.isEmpty()) {
            finish(tr("The image model finished without an image"));
            return;
        }
        m_step = m_totalSteps;
        m_stage = "saving";
        // Remembered, so the next one like it knows from the start.
        if (!m_durationKey.isEmpty())
            QSettings().setValue("durations/" + m_durationKey, m_clock.elapsed() / 1000.0);
        emit changed();
        finish(save() ? QString() : m_error);
    } else if (status == "failed") {
        finish(errorText(job).isEmpty() ? tr("The image couldn't be made") : errorText(job));
    } else if (status == "cancelled") {
        finish();
    } else {
        emit changed();
        m_poll.start();
    }
}

void Generator::startClock(const QString &key) {
    m_durationKey = key;
    m_expected = QSettings().value("durations/" + key, 0.0).toDouble();
    m_clock.start();
    m_tick.start();
    emit remainingChanged();
}

int Generator::remainingSeconds() const {
    if (!busy() || !m_clock.isValid())
        return -1;
    const double elapsed = m_clock.elapsed() / 1000.0;
    // The last one like it is the best guess, from the start.
    if (m_expected > 0)
        return std::max(0, int(std::lround(m_expected - elapsed)));
    // Otherwise the pace of the steps so far, and a share more for what
    // follows them (decoding, and a clip's sound).
    if (m_step > 0 && m_totalSteps > 0)
        return std::max(0, int(std::lround(elapsed / m_step * m_totalSteps * 1.25 - elapsed)));
    return -1;
}

double Generator::timeProgress() const {
    if (!busy() || !m_clock.isValid() || m_expected <= 0)
        return -1;
    // Held short of whole: only the result says it's done.
    return std::min(0.97, m_clock.elapsed() / 1000.0 / m_expected);
}

void Generator::finish(const QString &error) {
    m_poll.stop();
    m_tick.stop();
    m_clock.invalidate();
    m_job.clear();
    m_submitting = false;
    m_cancelling = false;
    m_stage.clear();
    m_jobOrigin.clear();
    m_error = error;
    m_locker.reset();
    emit changed();
    emit finished(error);
}

QString Generator::fileName(const QString &prompt, const QDateTime &when) {
    static const QRegularExpression word("[a-z0-9]+");
    QStringList words;
    for (auto it = word.globalMatch(prompt.toLower()); it.hasNext() && words.size() < 6;)
        words << it.next().captured();
    QString name = when.toString("yyyyMMdd-HHmmss");
    if (!words.isEmpty())
        name += "-" + words.join('-').left(48);
    return name;
}

bool Generator::save() {
    // A song goes with the user's music, its poster with the images.
    const QString folder = m_song ? m_musicFolder : m_folder;
    for (const QString &needed : {folder, m_folder}) {
        if (!QDir().mkpath(needed)) {
            m_error = tr("Couldn't make the folder %1").arg(needed);
            return false;
        }
    }
    // Written beside its final name, then renamed into place: the history
    // never sees half a file, and a rename never replaces another image the
    // app or the command line saved in the same second.
    const QString extension = m_song ? ".mp3" : m_video ? ".webm" : ".png";
    QTemporaryFile temporary(folder + "/.fantasi-XXXXXX" + extension);
    if (!temporary.open() || temporary.write(m_pending) != m_pending.size() || !temporary.flush()) {
        m_error = tr("Couldn't save the image in %1").arg(folder);
        return false;
    }
    // A temporary file is private; the image is as readable as a new file.
    temporary.setPermissions(newFilePermissions());
    const QString base = fileName(m_prompt, QDateTime::currentDateTime());
    for (int n = 1; n < 1000; ++n) {
        const QString stem = base + (n == 1 ? QString() : "-" + QString::number(n));
        const QString path = folder + "/" + stem + extension;
        // A clip's or a song's poster takes the same name among the images, so both must be free.
        if (!QFileInfo::exists(path) && !(extension != ".png" && QFileInfo::exists(m_folder + "/" + stem + ".png"))
            && temporary.rename(path)) {
            temporary.setAutoRemove(false);
            m_pending.clear();
            m_image = QUrl::fromLocalFile(path).toString();
            if (m_song) {
                // Not saved, as far as anyone is told, until its poster is too.
                m_unposted = path;
                return posterSong();
            } else if (m_video) {
                if (!m_firstFrame.isNull()) {
                    writePoster(path, m_firstFrame, m_prompt);
                } else {
                    // A clip from a prompt alone shows by its first frame,
                    // which ffmpeg takes out without holding up the window.
                    auto *frame = new QProcess(this);
                    auto locker = std::make_shared<QEventLoopLocker>();
                    connect(frame, &QProcess::finished, this, [this, frame, path, locker, prompt = m_prompt] {
                        frame->deleteLater();
                        writePoster(path, QImage::fromData(frame->readAllStandardOutput(), "PNG"), prompt);
                    });
                    frame->start("ffmpeg", {"-loglevel", "error", "-i", path, "-frames:v", "1", "-f", "image2pipe", "-vcodec", "png", "-"});
                }
            }
            emit saved(path);
            return true;
        }
    }
    m_error = tr("Couldn't save the image in %1").arg(folder);
    return false;
}

void Generator::shapeSong() {
    // A song shows by its own shape, taken from its sound as ffmpeg plays it
    // out, before anything is saved: the song and its poster then take their
    // names one right after the other.
    auto *sound = new QProcess(this);
    auto done = [this, sound] {
        sound->deleteLater();
        m_wave = songWave(sound->readAllStandardOutput());
        finish(save() ? QString() : m_error);
    };
    // Without ffmpeg the song still gets its poster, flat.
    connect(sound, &QProcess::finished, this, done);
    connect(sound, &QProcess::errorOccurred, this, [sound, done](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            done();
    });
    sound->start("ffmpeg", {"-loglevel", "error", "-f", "mp3", "-i", "pipe:0", "-ac", "1", "-ar", "8000", "-f", "s16le", "-"});
    sound->write(m_pending);
    sound->closeWriteChannel();
}

bool Generator::posterSong() {
    // Drawn as the window draws it, for a file manager to show.
    QImage shape(1200, 400, QImage::Format_ARGB32);
    shape.fill(Qt::transparent);
    QPainter painter(&shape);
    const double slot = double(shape.width()) / waveBars;
    for (int i = 0; i < m_wave.size(); ++i) {
        const double height = std::max(4.0, uchar(m_wave[i]) / 255.0 * shape.height());
        painter.fillRect(QRectF(i * slot + slot * 0.2, (shape.height() - height) / 2, slot * 0.6, height), QColor(128, 128, 128));
    }
    painter.end();
    // Without its poster the history can't list the song, so it stays
    // unsaved, to try again.
    if (!writePoster(m_unposted, shape, m_prompt, songTitle(m_lyrics, m_prompt), m_wave))
        return false;
    emit saved(std::exchange(m_unposted, {}));
    return true;
}

bool Generator::writePoster(const QString &media, const QImage &frame, const QString &prompt, const QString &title,
                            const QByteArray &wave) {
    const QFileInfo info(media);
    const bool song = info.suffix() == "mp3";
    QImage poster = frame.isNull() ? QImage(864, 480, QImage::Format_RGB32) : frame;
    if (frame.isNull())
        poster.fill(Qt::black);
    // The history reads a prompt from here, and finds the clip or the song it
    // stands for.
    poster.setText("parameters", prompt);
    poster.setText(song ? "fantasi-audio" : "fantasi-video", info.fileName());
    if (song) {
        poster.setText("fantasi-title", title);
        poster.setText("fantasi-wave", QString::fromLatin1(wave.toHex()));
    }
    // A clip's poster is beside it; a song's is among the images, where it
    // is renamed into place so it never replaces an image of the same name.
    const QString target = m_folder + "/" + info.completeBaseName() + ".png";
    bool written = false;
    if (song) {
        QTemporaryFile temporary(m_folder + "/.fantasi-XXXXXX.png");
        written = temporary.open() && poster.save(&temporary, "PNG") && temporary.flush()
               && temporary.setPermissions(newFilePermissions())
               && temporary.rename(target);
        temporary.setAutoRemove(!written);
    } else {
        QSaveFile file(target);
        file.setDirectWriteFallback(false);
        written = file.open(QIODevice::WriteOnly) && poster.save(&file, "PNG") && file.commit();
    }
    if (written) {
        m_error.clear();
        emit posterSaved(media);
        return true;
    }
    m_error = song ? tr("Couldn't save the image in %1").arg(m_folder) : tr("Couldn't save the clip's poster in %1").arg(m_folder);
    emit changed();
    emit posterFailed(m_error);
    return false;
}

void Generator::retrySave() {
    if (!unsaved() || busy())
        return;
    m_error.clear();
    if (m_unposted.isEmpty())
        save();
    else
        posterSong();
    emit changed();
}

void Generator::show(const QString &url) {
    if (busy())
        return;
    m_image = url;
    m_previews.clear();
    m_step = 0;
    m_totalSteps = 0;
    emit changed();
}

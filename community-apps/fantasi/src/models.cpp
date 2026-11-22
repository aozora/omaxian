#include "models.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSettings>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>

namespace {

QJsonDocument readJson(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(file.readAll()) : QJsonDocument();
}

bool isImage(const QJsonObject &row) { return row.value("kind").toString() == "image"; }

// What Fantasi makes things with: a video or music model is chosen like an
// image one, and what it makes is clips or songs.
bool isMaker(const QJsonObject &row) {
    const QString kind = row.value("kind").toString();
    return kind == "image" || kind == "video" || kind == "music";
}

} // namespace

Models::Models(const QString &stateDirectory, const QString &keyPath, const QString &command, QObject *parent)
    : QObject(parent),
      m_directory(!stateDirectory.isEmpty() ? stateDirectory : QDir::homePath() + "/.local/state/omarchy/agent-local"),
      m_keyPath(!keyPath.isEmpty() ? keyPath : QDir::homePath() + "/.config/omarchy/agent-local/key"),
      m_command(!command.isEmpty() ? command : QStandardPaths::findExecutable("omarchy-models")) {
    // The engine replaces its files whole, which drops a file watch, so the
    // watch is armed again after every change.
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(80);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
    connect(&m_debounce, &QTimer::timeout, this, &Models::reload);

    connect(&m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        if (code != 0 || status != QProcess::NormalExit) {
            // The engine says what went wrong on a line of its own.
            const QStringList lines = QString::fromUtf8(m_process.readAllStandardError() + m_process.readAllStandardOutput())
                                          .split('\n', Qt::SkipEmptyParts);
            const auto said = std::find_if(lines.rbegin(), lines.rend(), [](const QString &l) { return l.startsWith("Error: "); });
            m_error = said != lines.rend() ? said->mid(7).trimmed() : tr("The model couldn't be started");
            m_queue.clear();
            m_chosen.clear();
            emit changed();
            return;
        }
        // Only a model that started becomes the one to use.
        if (m_queue.isEmpty() && !m_chosen.isEmpty()) {
            QSettings().setValue("model", m_chosen);
            m_chosen.clear();
            reload();
        }
        runNext();
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        m_error = tr("omarchy-models couldn't be run");
        m_queue.clear();
        m_chosen.clear();
        emit changed();
    });

    reload();
    // The engine's list is rewritten after package updates; refreshing once
    // here means a newly installed engine's models show without a restart.
    // Its result arrives through the watched files, and a refresh that fails
    // is nothing to tell the user about.
    if (!m_command.isEmpty()) {
        QProcess refresh;
        refresh.setProgram(m_command);
        refresh.setArguments({"refresh", "--quiet"});
        refresh.setStandardOutputFile(QProcess::nullDevice());
        refresh.setStandardErrorFile(QProcess::nullDevice());
        refresh.startDetached();
    }
}

Models::Discovery Models::discover(const QJsonObject &status, const QJsonArray &list, bool engine,
                                   const QString &preferred) {
    Discovery found;
    if (!engine && status.isEmpty() && list.isEmpty()) {
        found.state = "noEngine";
        return found;
    }

    // The set-up models, preferring the one used last, then by name.
    const QJsonObject models = status.value("models").toObject();
    QList<QJsonObject> images;
    QStringList runningText, runningTextIds;
    for (auto it = models.begin(); it != models.end(); ++it) {
        QJsonObject row = it.value().toObject();
        row.insert("id", it.key());
        if (isMaker(row))
            images << row;
        else if (row.value("unit").toString() == "active") {
            runningText << row.value("name").toString(it.key());
            runningTextIds << it.key();
        }
    }
    // This machine's own first, then a paired host's, each by name.
    std::sort(images.begin(), images.end(), [](const QJsonObject &a, const QJsonObject &b) {
        const bool aRemote = a.contains("host"), bRemote = b.contains("host");
        if (aRemote != bRemote)
            return bRemote;
        return a.value("name").toString() < b.value("name").toString();
    });
    // Only what's set up is a choice: a model still downloading isn't one yet.
    for (const QJsonObject &row : images)
        if (row.value("unit").toString() != "installing")
            found.choices << QVariantMap{{"id", row.value("id").toString()}, {"name", row.value("name").toString(row.value("id").toString())},
                                         {"running", row.value("unit").toString() == "active"},
                                         {"fits", row.value("fits").toBool(true)},
                                         {"video", row.value("kind").toString() == "video"},
                                         {"music", row.value("kind").toString() == "music"},
                                         {"vendor", row.value("vendor").toString()}};
    for (const QJsonObject &row : images)
        if (row.value("unit").toString() == "active" && row.value("edit").toBool() && found.editEndpoint.isEmpty()) {
            found.editEndpoint = row.value("endpoint").toString();
            found.editId = row.value("id").toString();
        }
    std::stable_sort(images.begin(), images.end(), [&](const QJsonObject &a, const QJsonObject &b) {
        return a.value("id").toString() == preferred && b.value("id").toString() != preferred;
    });

    // A running model wins, then one on its way, then one that's set up.
    for (const char *unit : {"active", "activating", "installing"}) {
        for (const QJsonObject &row : images) {
            if (row.value("unit").toString() != unit)
                continue;
            found.id = row.value("id").toString();
            found.name = row.value("name").toString(found.id);
            found.endpoint = row.value("endpoint").toString();
            found.edits = row.value("edit").toBool();
            found.video = row.value("kind").toString() == "video";
            found.music = row.value("kind").toString() == "music";
            found.maxSeconds = row.value("max_seconds").toInt(-1);
            found.state = QString(unit) == "active" ? "ready" : QString(unit) == "activating" ? "starting" : "installing";
            // What a setup screen shows: the download's progress, then the
            // start, timed against how long the catalog measured one to take.
            found.startedMs = row.value("since_ms").toInteger();
            found.loadSeconds = row.value("expected_load_seconds").toDouble();
            if (found.state == "installing") {
                const QJsonObject install = row.value("install").toObject();
                found.doneBytes = install.value("done_bytes").toInteger();
                found.totalBytes = install.value("total_bytes").toInteger();
                found.rateBytes = install.value("rate_bytes_s").toInteger();
                const QString error = row.value("error").toString();
                found.setupPhase = !error.isEmpty() ? "failed" : install.value("phase").toString("waiting");
                found.reason = error;
            } else if (found.state == "starting") {
                found.setupPhase = "starting";
                found.firstStart = row.value("observed").isNull() || row.value("observed").isUndefined();
            }
            return found;
        }
    }
    if (!images.isEmpty()) {
        const QJsonObject &row = images.first();
        found.id = row.value("id").toString();
        found.name = row.value("name").toString(found.id);
        found.video = row.value("kind").toString() == "video";
        found.music = row.value("kind").toString() == "music";
        found.maxSeconds = row.value("max_seconds").toInt(-1);
        // An installed model the memory can't hold right now waits for the
        // text models in its way.
        if (row.value("fits").toBool(true) || runningText.isEmpty()) {
            found.state = "installed";
            found.reason = row.value("fit_reason").toString();
        } else {
            found.state = "blocked";
            found.reason = row.value("fit_reason").toString();
            found.blockers = runningText;
            found.blockerIds = runningTextIds;
        }
        return found;
    }

    // Nothing set up: the best image model that runs here, else why none does.
    QList<QJsonObject> candidates;
    QString reason;
    for (const QJsonValue &value : list) {
        const QJsonObject row = value.toObject();
        if (!isImage(row))
            continue;
        if (row.value("available").toBool())
            candidates << row;
        else if (reason.isEmpty())
            reason = row.value("reason").toString();
    }
    std::stable_sort(candidates.begin(), candidates.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return a.value("best").toBool() && !b.value("best").toBool();
    });
    if (!candidates.isEmpty()) {
        found.state = "installable";
        found.id = candidates.first().value("id").toString();
        found.name = candidates.first().value("name").toString(found.id);
        return found;
    }
    found.state = "none";
    found.reason = reason;
    return found;
}

QVariantList Models::offersFrom(const QJsonObject &status, const QJsonArray &list) {
    const QJsonObject models = status.value("models").toObject();
    QVariantList offers;
    for (const QString kind : {"image", "music", "video"}) {
        QList<QJsonObject> rows;
        for (const QJsonValue &value : list)
            if (value.toObject().value("kind").toString() == kind && value.toObject().value("available").toBool())
                rows << value.toObject();
        if (rows.isEmpty())
            continue;
        // The engine's pick for its kind first.
        std::stable_sort(rows.begin(), rows.end(), [](const QJsonObject &a, const QJsonObject &b) {
            return a.value("best").toBool() && !b.value("best").toBool();
        });
        const QJsonObject row = rows.first();
        const QString id = row.value("id").toString();
        const QJsonObject model = models.value(id).toObject();
        const QJsonObject install = model.value("install").toObject();
        const QString unit = model.value("unit").toString();
        const QString error = model.value("error").toString();
        QString phase = "offer";
        if (unit == "installing")
            phase = !error.isEmpty() ? "failed" : install.value("phase").toString("waiting");
        else if (unit == "activating")
            phase = "starting";
        else if (unit == "active")
            phase = "ready";
        else if (!model.isEmpty())
            phase = "installed";
        constexpr double gib = 1024.0 * 1024 * 1024;
        offers << QVariantMap{{"id", id}, {"kind", kind}, {"name", row.value("name").toString(id)},
                              {"vendor", row.value("vendor").toString()},
                              {"downloadBytes", qint64(row.value("download_gib").toDouble() * gib)},
                              {"memoryBytes", qint64(row.value("memory_gib").toDouble() * gib)},
                              {"phase", phase}, {"error", error},
                              {"doneBytes", install.value("done_bytes").toInteger()},
                              {"totalBytes", install.value("total_bytes").toInteger()},
                              {"rateBytes", install.value("rate_bytes_s").toInteger()}};
    }
    return offers;
}

// The engine's endpoint is the OpenAI base, ending in /v1; the native API
// lives beside it.
static QString originOf(const QString &endpoint) {
    QUrl url(endpoint);
    if (!url.isValid() || url.host().isEmpty())
        return {};
    // A paired host's model lives under /local-ai/<recipe>/v1; its native
    // API beside the /v1.
    QString path = url.path();
    if (path.endsWith("/v1"))
        path.chop(3);
    url.setPath(path);
    return url.toString(QUrl::StripTrailingSlash);
}

QString Models::origin() const { return originOf(m_found.endpoint); }
QString Models::editOrigin() const { return originOf(m_found.editEndpoint); }
QList<int> Models::lengthsUpTo(int maxSeconds) {
    if (maxSeconds < 0)
        return {2, 5, 10};
    QList<int> lengths;
    for (int seconds : {2, 5})
        if (seconds <= maxSeconds)
            lengths << seconds;
    for (int seconds = 10; seconds <= maxSeconds; seconds += 5)
        lengths << seconds;
    return lengths.isEmpty() ? QList<int>{2} : lengths;
}

QVariantList Models::clipLengths() const {
    QVariantList lengths;
    for (int seconds : lengthsUpTo(m_found.maxSeconds))
        lengths << seconds;
    return lengths;
}

QString Models::videoOrigin() const { return m_found.video ? origin() : QString(); }

QString Models::logo(const QString &vendor, bool light) {
    const QString omarchy = qEnvironmentVariable("OMARCHY_PATH");
    if (omarchy.isEmpty())
        return {};
    const QString assets = omarchy + "/shell/plugins/agents/assets/";
    static const QRegularExpression slug("^[a-z0-9-]+$");
    const QString id = slug.match(vendor).hasMatch() && QFileInfo::exists(assets + vendor + ".svg") ? vendor : "local";
    const QString path = light && QFileInfo::exists(assets + id + "-light.svg") ? assets + id + "-light.svg" : assets + id + ".svg";
    return QFileInfo::exists(path) ? QUrl::fromLocalFile(path).toString() : QString();
}

QByteArray Models::keyFor(const QString &id) const {
    const QString host = id.contains('/') ? id.section('/', 0, 0) : QString();
    static const QRegularExpression name("^[a-z0-9-]+$");
    if (!host.isEmpty() && !name.match(host).hasMatch())
        return {};
    QFile file(host.isEmpty() ? m_keyPath : QFileInfo(m_keyPath).absolutePath() + "/remotes/" + host + ".key");
    return file.open(QIODevice::ReadOnly) ? file.readAll().trimmed() : QByteArray();
}

void Models::start() {
    if (m_found.state == "installed")
        run({{"start", m_found.id}});
}

void Models::install() {
    // A setup that failed is tried again the same way: the engine replaces
    // the failed record rather than inheriting its error.
    if (m_found.state == "installable" || (m_found.state == "installing" && m_found.setupPhase == "failed"))
        run({{"use", m_found.id, "--detach"}});
}

void Models::download(const QString &id) {
    for (const QVariant &offer : m_found.offers) {
        const QVariantMap row = offer.toMap();
        if (row.value("id").toString() == id && (row.value("phase") == "offer" || row.value("phase") == "failed"))
            run({{"use", id, "--detach"}});
    }
}

void Models::endSetup() {
    if (!m_settingUp)
        return;
    m_settingUp = false;
    emit changed();
}

void Models::switchTo() {
    if (m_found.state != "blocked")
        return;
    QList<QStringList> commands;
    for (const QString &id : m_found.blockerIds)
        commands << QStringList{"stop", id};
    commands << QStringList{"start", m_found.id};
    run(commands);
}

void Models::choose(const QString &id) {
    if (id == m_found.id || working())
        return;
    // One already running is simply used from now on: nothing to stop or start.
    for (const QVariant &choice : m_found.choices) {
        const QVariantMap row = choice.toMap();
        if (row.value("id").toString() == id && row.value("running").toBool()) {
            m_error.clear();
            QSettings().setValue("model", id);
            reload();
            return;
        }
    }
    m_chosen = id;
    emit changed();
    // The one in use keeps running beside it, ready to switch back to, unless
    // the engine says there's no room for both.
    bool fits = true;
    for (const QVariant &choice : m_found.choices)
        if (choice.toMap().value("id").toString() == id)
            fits = choice.toMap().value("fits").toBool();
    QList<QStringList> commands;
    if (!fits && (m_found.state == "ready" || m_found.state == "starting"))
        commands << QStringList{"stop", m_found.id};
    commands << QStringList{"start", id};
    run(commands);
}

void Models::run(const QList<QStringList> &commands) {
    if (working())
        return;
    // Said rather than swallowed: a click that starts nothing looks broken.
    if (m_command.isEmpty()) {
        m_error = tr("omarchy-models couldn't be run");
        m_chosen.clear();
        emit changed();
        return;
    }
    m_error.clear();
    m_queue = commands;
    runNext();
    emit changed();
}

void Models::runNext() {
    if (m_queue.isEmpty()) {
        emit changed();
        return;
    }
    m_process.start(m_command, m_queue.takeFirst());
}

void Models::reload() {
    const auto paths = m_watcher.files() + m_watcher.directories();
    if (!paths.isEmpty())
        m_watcher.removePaths(paths);
    // Watching the nearest folder that exists means a first install of the
    // engine shows without a restart.
    QString ancestor = m_directory;
    while (!QFileInfo::exists(ancestor) && ancestor != "/")
        ancestor = QFileInfo(ancestor).absolutePath();
    QStringList candidates{ancestor, m_directory, m_directory + "/status.json", m_directory + "/list.json", m_directory + "/network.json"};
    candidates.removeDuplicates();
    for (const QString &path : candidates)
        if (QFileInfo::exists(path))
            m_watcher.addPath(path);

    QSettings settings;
    const QString preferred = settings.value("model").toString();
    QJsonObject status = readJson(m_directory + "/status.json").object();
    // A paired host's running image models, shared on the tailnet, join this
    // machine's own as choices, named for their host.
    QJsonObject models = status.value("models").toObject();
    const QJsonObject network = readJson(m_directory + "/network.json").object().value("models").toObject();
    for (auto it = network.begin(); it != network.end(); ++it) {
        QJsonObject row = it.value().toObject();
        if (!isMaker(row) || !row.value("paired").toBool() || !row.value("offline").toString().isEmpty()
            || row.value("unit").toString() != "active")
            continue;
        row.insert("name", tr("%1 on %2").arg(row.value("name").toString(it.key()), row.value("host").toString()));
        models.insert(it.key(), row);
    }
    status.insert("models", models);
    const QJsonArray list = readJson(m_directory + "/list.json").array();
    Discovery found = discover(status, list, !m_command.isEmpty(), preferred);
    found.vendor = status.value("models").toObject().value(found.id).toObject().value("vendor").toString();
    for (const QJsonValue &row : list)
        if (found.vendor.isEmpty() && row.toObject().value("id").toString() == found.id)
            found.vendor = row.toObject().value("vendor").toString();
    if (found.state == "ready" && found.id != preferred)
        settings.setValue("model", found.id);

    // A first run, while nothing to make things with is set up yet: it offers
    // what this machine runs, and lasts until the first prompt is sent.
    found.offers = offersFrom(status, list);
    bool settingUp = m_settingUp || (found.choices.isEmpty() && !found.offers.isEmpty());

    if (found.state != m_found.state || found.id != m_found.id || found.endpoint != m_found.endpoint || found.edits != m_found.edits
        || found.reason != m_found.reason || found.blockers != m_found.blockers
        || found.choices != m_found.choices || found.editEndpoint != m_found.editEndpoint || found.vendor != m_found.vendor || found.video != m_found.video || found.maxSeconds != m_found.maxSeconds
        || found.music != m_found.music
        || found.setupPhase != m_found.setupPhase || found.doneBytes != m_found.doneBytes || found.totalBytes != m_found.totalBytes
        || found.rateBytes != m_found.rateBytes || found.startedMs != m_found.startedMs || found.loadSeconds != m_found.loadSeconds
        || found.firstStart != m_found.firstStart || settingUp != m_settingUp || found.offers != m_found.offers) {
        m_found = found;
        m_settingUp = settingUp;
        emit changed();
    }
}

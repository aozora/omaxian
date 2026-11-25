#include "models.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>

namespace {

QJsonDocument readJson(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(file.readAll()) : QJsonDocument();
}

bool isMusic(const QJsonObject &row) { return row.value("kind").toString() == "music"; }

} // namespace

Models::Models(const QString &stateDirectory, const QString &keyPath, const QString &command, const QString &meminfo,
               QObject *parent)
    : QObject(parent),
      m_directory(!stateDirectory.isEmpty() ? stateDirectory : QDir::homePath() + "/.local/state/omarchy/agent-local"),
      m_keyPath(!keyPath.isEmpty() ? keyPath : QDir::homePath() + "/.config/omarchy/agent-local/key"),
      m_command(!command.isEmpty() ? command : QStandardPaths::findExecutable("omarchy-models")),
      m_meminfo(!meminfo.isEmpty() ? meminfo : "/proc/meminfo") {
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
            m_error = said != lines.rend() ? said->mid(7).trimmed() : tr("The music model couldn't be started");
            m_queue.clear();
            reload();
            emit changed();
            return;
        }
        reload();
        runNext();
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart)
            return;
        m_error = tr("omarchy-models couldn't be run");
        m_queue.clear();
        emit changed();
    });

    // What each running model holds now, which can be much less than it
    // took to load once it's idle.
    connect(&m_meter, &QProcess::finished, this, [this](int code) {
        const QJsonObject held = QJsonDocument::fromJson(m_meter.readAllStandardOutput()).object();
        if (code != 0)
            return;
        m_memory.held.clear();
        for (auto it = held.begin(); it != held.end(); ++it)
            if (it.value().isDouble())
                m_memory.held.insert(it.key(), it.value().toDouble());
        rediscover();
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

Models::Memory Models::memoryOf(const QByteArray &meminfo) {
    QHash<QString, double> fields;
    for (const QByteArray &line : meminfo.split('\n')) {
        const QList<QByteArray> parts = line.simplified().split(' ');
        if (parts.size() >= 2)
            fields.insert(QString::fromLatin1(parts[0].chopped(1)), parts[1].toDouble() / (1024 * 1024));
    }
    Memory memory;
    if (!fields.contains("MemTotal") || !fields.contains("MemAvailable"))
        return memory;
    // A GPU driver's pool of pages it has let go of (GPUReclaim) is what the
    // next model loads into, so the engine counts it as free, and so does this.
    memory.totalGib = fields.value("MemTotal");
    memory.freeGib = fields.value("MemAvailable") + fields.value("GPUReclaim");
    return memory;
}

Models::Discovery Models::discover(const QJsonObject &status, const QJsonArray &list, bool engine, const Memory &memory,
                                   const QString &preferred) {
    Discovery found;
    if (!engine && status.isEmpty() && list.isEmpty()) {
        found.state = "noEngine";
        return found;
    }
    found.freeGib = memory.freeGib;
    found.totalGib = memory.totalGib > 0 ? memory.totalGib : status.value("ram_total_gib").toDouble();

    QHash<QString, QJsonObject> listed;
    for (const QJsonValue &value : list)
        listed.insert(value.toObject().value("id").toString(), value.toObject());

    const QJsonObject models = status.value("models").toObject();
    QList<QJsonObject> music;
    for (auto it = models.begin(); it != models.end(); ++it) {
        QJsonObject row = it.value().toObject();
        row.insert("id", it.key());
        if (isMusic(row))
            music << row;
    }
    // This machine's own before a paired host's.
    std::stable_sort(music.begin(), music.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return !a.contains("host") && b.contains("host");
    });
    // The one picked in the sheet, else one running, else one on its way,
    // else one set up.
    const QJsonObject *chosen = nullptr;
    for (const QJsonObject &row : music)
        if (!preferred.isEmpty() && row.value("id").toString() == preferred)
            chosen = &row;
    for (const char *unit : {"active", "activating", "installing", ""})
        for (const QJsonObject &row : music)
            if (!chosen && (!*unit || row.value("unit").toString() == unit))
                chosen = &row;

    const auto heldBy = [&](const QJsonObject &row) {
        const QString id = row.value("id").toString();
        return memory.held.contains(id) ? memory.held.value(id) : row.value("observed").toObject().value("ram_used_gib").toDouble();
    };
    const auto other = [](const QJsonObject &row) {
        return QVariantMap{{"id", row.value("id").toString()}, {"name", row.value("name").toString(row.value("id").toString())},
                           {"vendor", row.value("vendor").toString()}, {"vocals", row.value("vocals").toBool(true)},
                           {"installed", row.value("installed").toBool()}, {"downloadGib", row.value("download_gib").toDouble()},
                           {"memoryGib", row.value("memory_gib").toDouble()}, {"best", row.value("best").toBool()}};
    };
    QList<QJsonObject> available;
    for (const QJsonValue &value : list) {
        const QJsonObject row = value.toObject();
        if (isMusic(row) && row.value("available").toBool())
            available << row;
    }
    std::stable_sort(available.begin(), available.end(), [&](const QJsonObject &a, const QJsonObject &b) {
        const bool aBest = a.value("best").toBool(), bBest = b.value("best").toBool();
        if (aBest != bBest)
            return aBest;
        return a.value("name").toString(a.value("id").toString()) < b.value("name").toString(b.value("id").toString());
    });
    for (const QJsonObject &row : available)
        found.offers << other(row);

    const auto offerOthers = [&] {
        QSet<QString> seen{found.id};
        for (const QJsonValue &value : list) {
            const QJsonObject row = value.toObject();
            const QString id = row.value("id").toString();
            if (isMusic(row) && row.value("available").toBool() && !seen.contains(id)) {
                seen.insert(id);
                found.others << other(row);
            }
        }
        // Installed or paired host music models not present in list.json stay switchable too.
        for (const QJsonObject &row : music) {
            const QString id = row.value("id").toString();
            if (seen.contains(id) || row.value("unit").toString() == "installing")
                continue;
            seen.insert(id);
            const QJsonObject card = listed.value(id);
            found.others << QVariantMap{{"id", id}, {"name", row.value("name").toString(id)},
                                        {"vendor", row.value("vendor").toString(card.value("vendor").toString())},
                                        {"vocals", row.contains("vocals") ? row.value("vocals").toBool(true) : card.value("vocals").toBool(true)},
                                        {"installed", true}, {"downloadGib", card.value("download_gib").toDouble()},
                                        {"memoryGib", card.value("memory_gib").toDouble()}, {"best", card.value("best").toBool()}};
        }
    };

    if (!chosen) {
        // Nothing set up: the music model this machine is best for, else
        // any that runs here, else why none does.
        QJsonObject offer;
        for (const QJsonValue &value : list) {
            const QJsonObject row = value.toObject();
            if (!isMusic(row))
                continue;
            if (!row.value("available").toBool()) {
                // Memory it lacks says more than a runtime that was never
                // built for this GPU.
                const QString reason = row.value("reason").toString();
                if (found.reason.isEmpty() || (reason.startsWith("needs") && !found.reason.startsWith("needs")))
                    found.reason = reason;
            } else if (offer.isEmpty() || row.value("id").toString() == preferred
                       || (row.value("best").toBool() && offer.value("id").toString() != preferred)) {
                offer = row;
            }
        }
        if (offer.isEmpty()) {
            found.state = "none";
            return found;
        }
        found.state = "installable";
        found.id = offer.value("id").toString();
        found.name = offer.value("name").toString(found.id);
        found.vendor = offer.value("vendor").toString();
        found.vocals = offer.value("vocals").toBool(true);
        found.reason.clear();
        found.needGib = offer.value("memory_gib").toDouble();
        found.diskGib = offer.value("download_gib").toDouble();
        offerOthers();
        return found;
    }

    const QJsonObject &row = *chosen;
    const QJsonObject card = listed.value(row.value("id").toString());
    found.id = row.value("id").toString();
    found.name = row.value("name").toString(found.id);
    found.vendor = row.value("vendor").toString();
    if (found.vendor.isEmpty())
        found.vendor = card.value("vendor").toString();
    found.vocals = row.contains("vocals") ? row.value("vocals").toBool(true) : card.value("vocals").toBool(true);
    found.host = row.value("host").toString();
    found.endpoint = row.value("endpoint").toString();
    found.needGib = card.value("memory_gib").toDouble();
    if (found.needGib <= 0)
        found.needGib = row.value("observed").toObject().value("ram_used_gib").toDouble();
    found.diskGib = card.value("download_gib").toDouble();
    const QJsonObject update = row.value("update").toObject();
    found.updatable = !update.isEmpty() && found.host.isEmpty();
    found.updateBytes = update.value("download_bytes").toInteger();
    found.updating = row.value("updating").toBool();
    const QJsonObject progress = row.value(found.updating ? "update_progress" : "install").toObject();
    found.phase = progress.value("phase").toString();
    found.doneBytes = progress.value("done_bytes").toInteger();
    found.totalBytes = progress.value("total_bytes").toInteger();
    found.rateBytes = progress.value("rate_bytes_s").toInteger();
    found.sinceMs = row.value("since_ms").toInteger();
    found.loadSeconds = row.value("expected_load_seconds").toDouble();
    offerOthers();

    // What else runs on this machine, and holds memory: a paired host's
    // models hold theirs elsewhere.
    for (auto it = models.begin(); it != models.end(); ++it) {
        QJsonObject holder = it.value().toObject();
        holder.insert("id", it.key());
        if (it.key() == found.id || holder.contains("host")
            || !QStringList{"active", "activating", "deactivating"}.contains(holder.value("unit").toString()))
            continue;
        found.holders << QVariantMap{{"id", it.key()}, {"name", holder.value("name").toString(it.key())},
                                     {"kind", holder.value("kind").toString("text")}, {"gib", heldBy(holder)}};
    }
    std::stable_sort(found.holders.begin(), found.holders.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("gib").toDouble() > b.toMap().value("gib").toDouble();
    });

    const QString unit = row.value("unit").toString();
    if (unit == "active") {
        found.state = "ready";
        found.heldGib = found.host.isEmpty() ? heldBy(row) : 0;
    } else if (unit == "activating") {
        found.state = "starting";
    } else if (unit == "removing") {
        found.state = "removing";
    } else if (unit == "installing") {
        // A setup that failed is on offer again, with why it failed.
        const QString error = row.value("error").toString();
        found.state = error.isEmpty() ? "installing" : "installable";
        found.reason = error;
    } else {
        found.reason = row.value("fit_reason").toString();
        // Stopped, and whether it fits in the memory free now, weighed as
        // the engine weighs a start. Without the numbers, the engine's own
        // word on it from its last start or stop, which only running models
        // stand in the way of.
        const bool known = found.needGib > 0 && found.freeGib >= 0;
        const bool fits = known ? found.freeGib >= found.needGib : row.value("fits").toBool(true) || found.holders.isEmpty();
        found.state = fits ? "installed" : "blocked";
        if (!fits) {
            // Which models to stop: the smallest that makes room alone, so
            // a big model someone is working with stays when a small one
            // will do; else the biggest until there's room; none when
            // stopping all of them wouldn't be enough. Without the numbers,
            // all of them.
            const auto gib = [](const QVariant &holder) { return holder.toMap().value("gib").toDouble(); };
            QVariantList stopping;
            if (!known) {
                stopping = found.holders;
            } else {
                // Biggest first, so the last that makes room alone is the smallest.
                for (const QVariant &holder : found.holders)
                    if (found.freeGib + gib(holder) >= found.needGib)
                        stopping = {holder};
                if (stopping.isEmpty()) {
                    double room = found.freeGib;
                    for (const QVariant &holder : found.holders) {
                        if (room >= found.needGib)
                            break;
                        stopping << holder;
                        room += gib(holder);
                    }
                    if (room < found.needGib)
                        stopping.clear();
                }
            }
            for (const QVariant &value : stopping) {
                found.blockers << value.toMap().value("name").toString();
                found.blockerIds << value.toMap().value("id").toString();
            }
        }
    }
    return found;
}

QString Models::origin() const {
    // The engine's endpoint is the OpenAI base, ending in /v1; the model's
    // own API lives beside it.
    QUrl url(m_found.endpoint);
    if (!url.isValid() || url.host().isEmpty())
        return {};
    QString path = url.path();
    if (path.endsWith("/v1"))
        path.chop(3);
    url.setPath(path);
    return url.toString(QUrl::StripTrailingSlash);
}

QByteArray Models::key() const {
    const QString host = m_found.id.contains('/') ? m_found.id.section('/', 0, 0) : QString();
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

void Models::makeRoom() {
    if (m_found.state != "blocked" || m_found.blockerIds.isEmpty())
        return;
    QList<QStringList> commands;
    for (const QString &id : m_found.blockerIds)
        commands << QStringList{"stop", id};
    commands << QStringList{"start", m_found.id};
    run(commands);
}

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

void Models::install(const QString &id) {
    // A setup that failed is tried again the same way: the engine replaces
    // the failed record rather than inheriting its error.
    if (m_found.state != "installable")
        return;
    const QString target = id.isEmpty() ? m_found.id : id;
    bool known = target == m_found.id;
    for (const QVariant &offer : m_found.offers)
        if (offer.toMap().value("id").toString() == target)
            known = true;
    if (!known || target.isEmpty())
        return;
    if (target != m_found.id) {
        QSettings().setValue("model", target);
        rediscover();
    }
    run({{"use", target, "--detach"}});
}

void Models::stop() {
    if (m_found.host.isEmpty() && (m_found.state == "ready" || m_found.state == "starting"))
        run({{"stop", m_found.id}});
}

void Models::update() {
    if (m_found.updatable && !m_found.updating)
        run({{"update", m_found.id, "--detach"}});
}

void Models::remove() {
    if (m_found.host.isEmpty() && QStringList{"ready", "starting", "installed", "blocked"}.contains(m_found.state))
        run({{"remove", m_found.id}});
}

void Models::use(const QString &id) {
    QVariantMap picked;
    for (const QVariant &value : m_found.others)
        if (value.toMap().value("id").toString() == id)
            picked = value.toMap();
    if (picked.isEmpty() || working())
        return;
    QList<QStringList> commands;
    if (m_found.host.isEmpty() && (m_found.state == "ready" || m_found.state == "starting"))
        commands << QStringList{"stop", m_found.id};
    if (!picked.value("installed").toBool())
        commands << QStringList{"use", id, "--detach"};
    QSettings().setValue("model", id);
    rediscover();
    if (!commands.isEmpty())
        run(commands);
}

void Models::checkMemory() { measure(true); }

void Models::measure(bool always) {
    QFile meminfo(m_meminfo);
    const Memory now = memoryOf(meminfo.open(QIODevice::ReadOnly) ? meminfo.readAll() : QByteArray());
    m_memory.freeGib = now.freeGib;
    m_memory.totalGib = now.totalGib;
    // What the running models hold is asked of the engine when asked for,
    // and when which models run changes, not at every status the engine writes.
    QStringList running;
    const QJsonObject models = m_status.value("models").toObject();
    for (auto it = models.begin(); it != models.end(); ++it)
        if (!it.value().toObject().contains("host") && it.value().toObject().value("unit").toString() == "active")
            running << it.key();
    if (running != m_running)
        m_memory.held.clear();
    if (!running.isEmpty() && (always || running != m_running) && m_meter.state() == QProcess::NotRunning && !m_command.isEmpty())
        m_meter.start(m_command, {"memory", "--json"});
    m_running = running;
    rediscover();
}

void Models::run(const QList<QStringList> &commands) {
    if (working())
        return;
    m_error.clear();
    if (m_command.isEmpty()) {
        m_error = tr("omarchy-models couldn't be run");
        emit changed();
        return;
    }
    m_queue = commands;
    runNext();
}

void Models::runNext() {
    if (!m_queue.isEmpty())
        m_process.start(m_command, m_queue.takeFirst());
    emit changed();
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

    m_status = readJson(m_directory + "/status.json").object();
    // A paired host's running music model, shared on the tailnet, serves when
    // this machine has none running, named for its host.
    QJsonObject models = m_status.value("models").toObject();
    const QJsonObject network = readJson(m_directory + "/network.json").object().value("models").toObject();
    for (auto it = network.begin(); it != network.end(); ++it) {
        QJsonObject row = it.value().toObject();
        if (!isMusic(row) || !row.value("paired").toBool() || !row.value("offline").toString().isEmpty()
            || row.value("unit").toString() != "active")
            continue;
        row.insert("name", tr("%1 on %2").arg(row.value("name").toString(it.key()), row.value("host").toString()));
        models.insert(it.key(), row);
    }
    if (!models.isEmpty())
        m_status.insert("models", models);
    m_list = readJson(m_directory + "/list.json").array();
    // A model starting or stopping is when memory changes hands.
    measure(false);
}

void Models::rediscover() {
    const Discovery found = discover(m_status, m_list, !m_command.isEmpty(), m_memory, QSettings().value("model").toString());
    if (found == m_found)
        return;
    m_found = found;
    emit changed();
    hold();
}

void Models::hold() {
    // This machine's own, set up: a paired host's model is held there.
    const bool own = QStringList{"installed", "blocked", "starting", "ready"}.contains(m_found.state) && m_found.host.isEmpty();
    const QString id = own ? m_found.id : QString();
    if (id == m_held || m_command.isEmpty())
        return;
    m_held = id;
    // The engine holds it until its input closes, as when this app quits or dies.
    m_hold.closeWriteChannel();
    m_hold.waitForFinished(1000);
    if (!id.isEmpty())
        m_hold.start(m_command, {"hold", id});
}

void Models::release() {
    m_hold.closeWriteChannel();
    m_hold.waitForFinished(1000);
    QStringList running;
    const QJsonObject models = m_status.value("models").toObject();
    for (auto it = models.begin(); it != models.end(); ++it) {
        const QJsonObject row = it.value().toObject();
        const QString unit = row.value("unit").toString();
        if (isMusic(row) && !row.value("paired").toBool() && (unit == "active" || unit == "activating"))
            running << it.key();
    }
    if (!running.isEmpty() && !m_command.isEmpty())
        QProcess::startDetached(m_command, QStringList{"stop", "--unless-used"} + running);
}

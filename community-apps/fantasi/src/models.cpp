#include "models.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QSet>
#include <QSettings>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>
#include <algorithm>
#include <cmath>

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

// Whether a set-up model can run on this machine as it is. Of the reasons the
// engine gives for one not fitting, only a lack of free memory goes away by
// stopping other models; a GPU too small, or one waiting on a reboot to
// address more, leaves nothing to switch to.
bool runsHere(const QJsonObject &row) {
    return row.value("fits").toBool(true) || row.value("fit_reason").toString() == "Not enough memory";
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

    m_memoryTimer.setInterval(2000);
    connect(&m_memoryTimer, &QTimer::timeout, this, &Models::readMemory);
    connect(&m_memoryProcess, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        QHash<QString, double> held;
        const QJsonObject measured = QJsonDocument::fromJson(m_memoryProcess.readAllStandardOutput()).object();
        if (code == 0 && status == QProcess::NormalExit)
            for (auto it = measured.begin(); it != measured.end(); ++it)
                if (it.value().isDouble() && it.value().toDouble() >= 0)
                    held.insert(it.key(), it.value().toDouble());
        m_memory.held = held;
        reload();
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
        if (isMaker(row)) {
            if (runsHere(row))
                images << row;
        }
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
                                         {"vocals", row.value("vocals").toBool(true)},
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
            found.vocals = row.value("vocals").toBool(true);
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
        found.vocals = row.value("vocals").toBool(true);
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

Models::Memory Models::parseMeminfo(const QByteArray &meminfo) {
    QHash<QByteArray, double> fields;
    for (const QByteArray &line : meminfo.split('\n')) {
        const qsizetype colon = line.indexOf(':');
        if (colon > 0)
            fields.insert(line.left(colon), line.mid(colon + 1).trimmed().split(' ').value(0).toDouble());
    }
    Memory memory;
    constexpr double kibPerGib = 1024.0 * 1024;
    if (fields.value("MemTotal") <= 0 || !fields.contains("MemAvailable"))
        return memory;
    memory.total = fields.value("MemTotal") / kibPerGib;
    memory.free = std::min(memory.total, (fields.value("MemAvailable") + fields.value("GPUReclaim")) / kibPerGib);
    // Tenths are all anyone reads, and all a change needs redrawing for.
    memory.total = std::round(memory.total * 10) / 10;
    memory.free = std::round(memory.free * 10) / 10;
    return memory;
}

namespace {

// What a model needs to load, as the catalog measured it on this kind of
// machine, else what it took the last time it loaded here; 0 when unknown.
double needsOf(const QJsonObject &model, const QJsonObject &recipe) {
    const double measured = recipe.value("memory_gib").toDouble();
    return measured > 0 ? measured : model.value("observed").toObject().value("ram_used_gib").toDouble();
}

QJsonObject recipeOf(const QJsonArray &list, const QString &id) {
    for (const QJsonValue &row : list)
        if (row.toObject().value("id").toString() == id)
            return row.toObject();
    return {};
}

} // namespace

QVariantList Models::holdersFrom(const QJsonObject &status, const QJsonArray &list, const Memory &memory) {
    const QJsonObject models = status.value("models").toObject();
    QVariantList holders;
    for (auto it = models.begin(); it != models.end(); ++it) {
        const QJsonObject row = it.value().toObject();
        const QString unit = row.value("unit").toString();
        if (unit != "active" && unit != "activating")
            continue;
        // What it holds now, measured; else what it took to load.
        const double gib = memory.held.contains(it.key()) ? memory.held.value(it.key()) : needsOf(row, recipeOf(list, it.key()));
        holders << QVariantMap{{"id", it.key()}, {"name", row.value("name").toString(it.key())},
                               {"kind", row.value("kind").toString("text")}, {"gib", gib}};
    }
    std::sort(holders.begin(), holders.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value("gib").toDouble() > b.toMap().value("gib").toDouble();
    });
    return holders;
}

QVariantList Models::roomFor(double needs, double free, const QVariantList &holders, const QString &except,
                             double *shortBy) {
    *shortBy = 0;
    const double gap = needs - free;
    if (needs <= 0 || gap <= 0)
        return {};
    QVariantList others;
    for (const QVariant &holder : holders)
        if (holder.toMap().value("id").toString() != except && holder.toMap().value("gib").toDouble() > 0)
            others << holder;
    // One that frees enough on its own, the smallest such: the holders come
    // biggest first.
    for (auto it = others.rbegin(); it != others.rend(); ++it)
        if (it->toMap().value("gib").toDouble() >= gap)
            return {*it};
    QVariantList room;
    double freed = 0;
    for (const QVariant &holder : others) {
        room << holder;
        freed += holder.toMap().value("gib").toDouble();
        if (freed >= gap)
            return room;
    }
    *shortBy = gap - freed;
    return room;
}

QVariantMap Models::libraryFrom(const QJsonObject &status, const QJsonArray &list, const Memory &memory,
                                const QString &inUse, QStringList *order) {
    const QJsonObject models = status.value("models").toObject();
    const QVariantList holders = holdersFrom(status, list, memory);
    constexpr double gib = 1024.0 * 1024 * 1024;
    QList<QVariantMap> rows;
    QSet<QString> offered;

    auto addRow = [&](const QString &id, const QJsonObject &model, const QJsonObject &recipe) {
        const QString kind = model.value("kind").toString(recipe.value("kind").toString());
        const QString unit = model.value("unit").toString();
        const QString error = model.value("error").toString();
        const QJsonObject update = model.value("update").toObject();
        const bool updating = model.value("updating").toBool();
        const QJsonObject progress = (unit == "installing" ? model.value("install") : model.value("update_progress")).toObject();
        QString state;
        if (model.isEmpty())
            state = recipe.value("available").toBool() ? "offer" : "unavailable";
        else if (unit == "installing")
            state = !error.isEmpty() ? "failed" : "installing";
        else if (unit == "activating")
            state = "starting";
        else if (unit == "deactivating")
            state = "stopping";
        else if (unit == "removing")
            state = "removing";
        else if (updating)
            state = "updating";
        else if (unit == "active")
            state = "running";
        else
            state = "stopped";
        const double needs = needsOf(model, recipe);
        // The engine decides whether a stopped model fits as it last started
        // or stopped one; what's free now says the same, more recently.
        const bool fits = needs > 0 && memory.total > 0 ? needs <= memory.free : model.value("fits").toBool(true);
        double shortBy = 0;
        const QVariantList room = state == "running" || state == "starting" ? QVariantList()
                                  : roomFor(needs, memory.free, holders, id, &shortBy);
        double held = 0;
        for (const QVariant &holder : holders)
            if (holder.toMap().value("id").toString() == id)
                held = holder.toMap().value("gib").toDouble();
        rows << QVariantMap{
            {"id", id}, {"kind", kind}, {"section", state == "unavailable" ? QString("unavailable") : kind},
            {"name", model.value("name").toString(recipe.value("name").toString(id))},
            {"vendor", model.value("vendor").toString(recipe.value("vendor").toString())},
            {"best", recipe.value("best").toBool()}, {"state", state}, {"inUse", id == inUse},
            {"error", error}, {"reason", recipe.value("reason").toString()},
            {"needs", needs}, {"held", held}, {"fits", fits}, {"room", room}, {"shortBy", shortBy},
            {"downloadBytes", qint64(recipe.value("download_gib").toDouble() * gib)},
            {"update", !update.isEmpty() && !updating},
            {"updateBytes", update.value("download_bytes").toInteger()},
            {"phase", progress.value("phase").toString()},
            {"doneBytes", progress.value("done_bytes").toInteger()},
            {"totalBytes", progress.value("total_bytes").toInteger()},
            {"rateBytes", progress.value("rate_bytes_s").toInteger()},
            {"sinceMs", model.value("since_ms").toInteger()},
            {"loadSeconds", model.value("expected_load_seconds").toDouble()}};
    };

    // This machine's own set-up models, and those being set up.
    for (auto it = models.begin(); it != models.end(); ++it) {
        const QJsonObject model = it.value().toObject();
        if (isMaker(model) && !model.contains("host")) {
            addRow(it.key(), model, recipeOf(list, it.key()));
            offered << model.value("kind").toString() + "\n" + model.value("name").toString();
        }
    }
    // Then what could be set up. A recipe has a variant per kind of GPU, all
    // under one name: one that runs here stands for the rest.
    for (const QJsonValue &value : list) {
        const QJsonObject recipe = value.toObject();
        if (isMaker(recipe) && recipe.value("available").toBool() && !models.contains(recipe.value("id").toString())
            && !offered.contains(recipe.value("kind").toString() + "\n" + recipe.value("name").toString())) {
            addRow(recipe.value("id").toString(), {}, recipe);
            offered << recipe.value("kind").toString() + "\n" + recipe.value("name").toString();
        }
    }
    for (const QJsonValue &value : list) {
        const QJsonObject recipe = value.toObject();
        if (isMaker(recipe) && !offered.contains(recipe.value("kind").toString() + "\n" + recipe.value("name").toString())) {
            addRow(recipe.value("id").toString(), {}, recipe);
            offered << recipe.value("kind").toString() + "\n" + recipe.value("name").toString();
        }
    }

    // Images, video, music, then what isn't for this machine; within each,
    // what's set up before what could be, the engine's pick first, by name.
    const QStringList sections{"image", "video", "music", "unavailable"};
    std::stable_sort(rows.begin(), rows.end(), [&](const QVariantMap &a, const QVariantMap &b) {
        const int as = sections.indexOf(a.value("section").toString()), bs = sections.indexOf(b.value("section").toString());
        if (as != bs)
            return as < bs;
        const bool aOffer = a.value("state") == "offer", bOffer = b.value("state") == "offer";
        if (aOffer != bOffer)
            return bOffer;
        if (a.value("best").toBool() != b.value("best").toBool())
            return a.value("best").toBool();
        return a.value("name").toString() < b.value("name").toString();
    });
    QVariantMap library;
    order->clear();
    QString section;
    for (QVariantMap &row : rows) {
        row.insert("first", row.value("section").toString() != section);
        section = row.value("section").toString();
        *order << row.value("id").toString();
        library.insert(row.value("id").toString(), row);
    }
    return library;
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
                              {"vocals", row.value("vocals").toBool(true)},
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
        run(startCommands(m_found.id));
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
    if (m_found.state == "blocked")
        run(startCommands(m_found.id));
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
    run(startCommands(id));
}

QList<QStringList> Models::startCommands(const QString &id) const {
    QList<QStringList> commands;
    const QVariantMap row = m_library.value(id).toMap();
    const QVariantList room = row.value("room").toList();
    if (!room.isEmpty() && row.value("shortBy").toDouble() <= 0) {
        // What's in the way, by how much it holds.
        for (const QVariant &holder : room)
            commands << QStringList{"stop", holder.toMap().value("id").toString()};
    } else if (row.value("needs").toDouble() <= 0) {
        // Without numbers, the engine's word: the one in use keeps running
        // beside it, ready to switch back to, unless there's no room for
        // both; a model blocked by text models stops them.
        bool fits = true;
        for (const QVariant &choice : m_found.choices)
            if (choice.toMap().value("id").toString() == id)
                fits = choice.toMap().value("fits").toBool();
        if (!fits && id != m_found.id && (m_found.state == "ready" || m_found.state == "starting"))
            commands << QStringList{"stop", m_found.id};
        if (id == m_found.id && m_found.state == "blocked")
            for (const QString &blocker : m_found.blockerIds)
                commands << QStringList{"stop", blocker};
    }
    commands << QStringList{"start", id};
    return commands;
}

void Models::setUp(const QString &id) {
    const QString state = m_library.value(id).toMap().value("state").toString();
    if (state == "offer" || state == "failed")
        run({{"use", id, "--detach"}});
}

void Models::startModel(const QString &id) {
    if (id == m_found.id) {
        if (!working() && (m_found.state == "installed" || m_found.state == "blocked"))
            run(startCommands(id));
    } else {
        choose(id);
    }
}

void Models::stop(const QString &id) {
    const QString state = m_library.value(id).toMap().value("state").toString();
    if (state == "running" || state == "starting")
        run({{"stop", id}});
}

void Models::update(const QString &id) {
    if (m_library.value(id).toMap().value("update").toBool())
        run({{"update", "--detach", id}});
}

void Models::remove(const QString &id) {
    const QString state = m_library.value(id).toMap().value("state").toString();
    if (state != "offer" && state != "unavailable" && state != "removing" && !state.isEmpty())
        run({{"remove", id}});
}

void Models::setWatching(bool watching) {
    if (watching == m_memoryTimer.isActive())
        return;
    if (watching) {
        m_memoryTimer.start();
        readMemory();
    } else {
        m_memoryTimer.stop();
        // Measured only while watched: an old figure would outlast what the
        // model holds now, so what it took to load stands in again.
        m_memory.held.clear();
        reload();
    }
    emit watchingChanged();
}

void Models::readMeminfo() {
    QFile meminfo(m_meminfoPath);
    const Memory read = parseMeminfo(meminfo.open(QIODevice::ReadOnly) ? meminfo.readAll() : QByteArray());
    m_memory.total = read.total;
    m_memory.free = read.free;
}

void Models::readMemory() {
    // What each running model holds now, measured only while the manager is
    // open; the rest of the time, what it took to load stands in.
    bool running = false;
    const QJsonObject models = m_status.value("models").toObject();
    for (auto it = models.begin(); it != models.end(); ++it)
        running = running || QStringList{"active", "activating"}.contains(it.value().toObject().value("unit").toString());
    if (!running)
        m_memory.held.clear();
    else if (watching() && !m_command.isEmpty() && m_memoryProcess.state() == QProcess::NotRunning)
        m_memoryProcess.start(m_command, {"memory", "--json"});
    // What's free decides whether the model in use fits, so it's all read again.
    reload();
}

void Models::updateLibrary() {
    QStringList order;
    const QVariantMap library = libraryFrom(m_status, m_list, m_memory, m_found.id, &order);
    const QVariantList holders = holdersFrom(m_status, m_list, m_memory);
    if (library != m_library || holders != m_holders || m_memory.total != m_shownTotal || m_memory.free != m_shownFree) {
        m_library = library;
        m_holders = holders;
        m_shownTotal = m_memory.total;
        m_shownFree = m_memory.free;
        emit libraryChanged();
    }
    if (order != m_libraryIds) {
        m_libraryIds = order;
        emit libraryIdsChanged();
    }
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
    m_status = status;
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
    m_list = list;
    Discovery found = discover(status, list, !m_command.isEmpty(), preferred);
    // A model blocked by others names those it would stop to fit, once
    // there's memory to tell by; the engine decided it as a model last
    // started or stopped, so one that fits now isn't blocked at all.
    readMeminfo();
    if (found.state == "blocked") {
        QStringList order;
        const QVariantMap row = libraryFrom(m_status, m_list, m_memory, found.id, &order).value(found.id).toMap();
        const QVariantList room = row.value("room").toList();
        if (row.value("needs").toDouble() > 0 && row.value("fits").toBool()) {
            found.state = "installed";
            found.blockers.clear();
            found.blockerIds.clear();
        } else if (!room.isEmpty()) {
            found.blockers.clear();
            found.blockerIds.clear();
            for (const QVariant &holder : room) {
                found.blockers << holder.toMap().value("name").toString();
                found.blockerIds << holder.toMap().value("id").toString();
            }
        }
    }
    const QJsonObject foundRow = status.value("models").toObject().value(found.id).toObject();
    found.vendor = foundRow.value("vendor").toString();
    for (const QJsonValue &row : list) {
        if (row.toObject().value("id").toString() == found.id) {
            if (found.vendor.isEmpty())
                found.vendor = row.toObject().value("vendor").toString();
            if (!foundRow.contains("vocals") && row.toObject().contains("vocals"))
                found.vocals = row.toObject().value("vocals").toBool(true);
        }
    }
    if (found.state == "ready" && found.id != preferred)
        settings.setValue("model", found.id);

    // A first run, while nothing to make things with is set up yet: it offers
    // what this machine runs, and lasts until the first prompt is sent.
    found.offers = offersFrom(status, list);
    bool settingUp = m_settingUp || (found.choices.isEmpty() && !found.offers.isEmpty());

    if (found.state != m_found.state || found.id != m_found.id || found.endpoint != m_found.endpoint || found.edits != m_found.edits
        || found.reason != m_found.reason || found.blockers != m_found.blockers
        || found.choices != m_found.choices || found.editEndpoint != m_found.editEndpoint || found.vendor != m_found.vendor || found.video != m_found.video || found.maxSeconds != m_found.maxSeconds
        || found.music != m_found.music || found.vocals != m_found.vocals
        || found.setupPhase != m_found.setupPhase || found.doneBytes != m_found.doneBytes || found.totalBytes != m_found.totalBytes
        || found.rateBytes != m_found.rateBytes || found.startedMs != m_found.startedMs || found.loadSeconds != m_found.loadSeconds
        || found.firstStart != m_found.firstStart || settingUp != m_settingUp || found.offers != m_found.offers) {
        m_found = found;
        m_settingUp = settingUp;
        emit changed();
    }
    updateLibrary();
    hold();
}

void Models::hold() {
    // This machine's own, set up: a paired host's model is held there.
    QStringList ids;
    if (QStringList{"installed", "blocked", "starting", "ready"}.contains(m_found.state))
        ids << m_found.id;
    if (!m_found.editId.isEmpty())
        ids << m_found.editId;
    ids.removeIf([](const QString &id) { return id.isEmpty() || id.contains('/'); });
    ids.removeDuplicates();
    if (ids == m_held || m_command.isEmpty())
        return;
    m_held = ids;
    // The engine holds them until its input closes, as when this app quits or dies.
    m_hold.closeWriteChannel();
    m_hold.waitForFinished(1000);
    if (!ids.isEmpty())
        m_hold.start(m_command, QStringList{"hold"} + ids);
}

void Models::release() {
    m_hold.closeWriteChannel();
    m_hold.waitForFinished(1000);
    QStringList running;
    const QJsonObject models = m_status.value("models").toObject();
    for (auto it = models.begin(); it != models.end(); ++it) {
        const QString unit = it.value().toObject().value("unit").toString();
        if (isMaker(it.value().toObject()) && (unit == "active" || unit == "activating"))
            running << it.key();
    }
    if (!running.isEmpty() && !m_command.isEmpty())
        QProcess::startDetached(m_command, QStringList{"stop", "--unless-used"} + running);
}

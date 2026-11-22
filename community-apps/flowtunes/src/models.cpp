#include "models.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QRegularExpression>
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

Models::Models(const QString &stateDirectory, const QString &keyPath, const QString &command, QObject *parent)
    : QObject(parent),
      m_directory(!stateDirectory.isEmpty() ? stateDirectory : QDir::homePath() + "/.local/state/omarchy/agent-local"),
      m_keyPath(!keyPath.isEmpty() ? keyPath : QDir::homePath() + "/.config/omarchy/agent-local/key"),
      m_command(!command.isEmpty() ? command : QStandardPaths::findExecutable("omarchy-agent-local")) {
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
        m_error = tr("omarchy-agent-local couldn't be run");
        m_queue.clear();
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

Models::Discovery Models::discover(const QJsonObject &status, const QJsonArray &list, bool engine) {
    Discovery found;
    if (!engine && status.isEmpty() && list.isEmpty()) {
        found.state = "noEngine";
        return found;
    }

    const QJsonObject models = status.value("models").toObject();
    QList<QJsonObject> music;
    QStringList runningText, runningTextIds;
    for (auto it = models.begin(); it != models.end(); ++it) {
        QJsonObject row = it.value().toObject();
        row.insert("id", it.key());
        if (isMusic(row)) {
            music << row;
        } else if (row.value("kind").toString("text") == "text" && row.value("unit").toString() == "active") {
            runningText << row.value("name").toString(it.key());
            runningTextIds << it.key();
        }
    }
    // This machine's own before a paired host's.
    std::stable_sort(music.begin(), music.end(), [](const QJsonObject &a, const QJsonObject &b) {
        return !a.contains("host") && b.contains("host");
    });
    auto take = [&](const QJsonObject &row, const QString &state) {
        found.id = row.value("id").toString();
        found.name = row.value("name").toString(found.id);
        found.endpoint = row.value("endpoint").toString();
        found.state = state;
    };
    for (const char *unit : {"active", "activating", "installing"}) {
        for (const QJsonObject &row : music) {
            if (row.value("unit").toString() != unit)
                continue;
            if (QString(unit) != "installing") {
                take(row, QString(unit) == "active" ? "ready" : "starting");
                return found;
            }
            // A setup that failed is on offer again, with why it failed.
            const QString error = row.value("error").toString();
            take(row, error.isEmpty() ? "installing" : "installable");
            found.reason = error;
            const QJsonObject install = row.value("install").toObject();
            found.doneBytes = install.value("done_bytes").toInteger();
            found.totalBytes = install.value("total_bytes").toInteger();
            return found;
        }
    }
    if (!music.isEmpty()) {
        // One the memory can't hold right now waits for the text models in its way.
        const QJsonObject &row = music.first();
        const bool blocked = !row.value("fits").toBool(true) && !runningText.isEmpty();
        take(row, blocked ? "blocked" : "installed");
        found.reason = row.value("fit_reason").toString();
        if (blocked) {
            found.blockers = runningText;
            found.blockerIds = runningTextIds;
        }
        return found;
    }

    // Nothing set up: a music model that runs here, else why none does.
    for (const QJsonValue &value : list) {
        const QJsonObject row = value.toObject();
        if (!isMusic(row))
            continue;
        if (row.value("available").toBool()) {
            take(row, "installable");
            found.reason.clear();
            return found;
        }
        if (found.reason.isEmpty())
            found.reason = row.value("reason").toString();
    }
    found.state = "none";
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
    if (m_found.state != "blocked")
        return;
    QList<QStringList> commands;
    for (const QString &id : m_found.blockerIds)
        commands << QStringList{"stop", id};
    commands << QStringList{"start", m_found.id};
    run(commands);
}

void Models::install() {
    // A setup that failed is tried again the same way: the engine replaces
    // the failed record rather than inheriting its error.
    if (m_found.state == "installable")
        run({{"use", m_found.id, "--detach"}});
}

void Models::run(const QList<QStringList> &commands) {
    if (working())
        return;
    m_error.clear();
    if (m_command.isEmpty()) {
        m_error = tr("omarchy-agent-local couldn't be run");
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

    QJsonObject status = readJson(m_directory + "/status.json").object();
    // A paired host's running music model, shared on the tailnet, serves when
    // this machine has none running, named for its host.
    QJsonObject models = status.value("models").toObject();
    const QJsonObject network = readJson(m_directory + "/network.json").object().value("models").toObject();
    for (auto it = network.begin(); it != network.end(); ++it) {
        QJsonObject row = it.value().toObject();
        if (!isMusic(row) || !row.value("paired").toBool() || !row.value("offline").toString().isEmpty()
            || row.value("unit").toString() != "active")
            continue;
        row.insert("name", tr("%1 on %2").arg(row.value("name").toString(it.key()), row.value("host").toString()));
        models.insert(it.key(), row);
    }
    status.insert("models", models);
    const Discovery found = discover(status, readJson(m_directory + "/list.json").array(), !m_command.isEmpty());
    if (found == m_found)
        return;
    m_found = found;
    emit changed();
}

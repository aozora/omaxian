#pragma once

#include <QFileSystemWatcher>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QTimer>

// The music model omarchy-local-ai runs for Flowtunes. It reads the engine's
// own status.json and list.json, follows their changes, and starts or sets up
// the model through omarchy-agent-local.
class Models : public QObject {
    Q_OBJECT
    // noEngine, none, installable, installing, installed, blocked, starting, ready
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString name READ name NOTIFY changed)
    // Why no music model runs here, or why its setup failed.
    Q_PROPERTY(QString reason READ reason NOTIFY changed)
    // The running text models that hold the memory a blocked model needs.
    Q_PROPERTY(QStringList blockers READ blockers NOTIFY changed)
    // Why the engine couldn't do what it was last asked.
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool working READ working NOTIFY changed)
    // How far a setup's download is.
    Q_PROPERTY(qint64 doneBytes READ doneBytes NOTIFY changed)
    Q_PROPERTY(qint64 totalBytes READ totalBytes NOTIFY changed)

public:
    struct Discovery {
        QString state;
        QString id;
        QString name;
        QString endpoint;
        QString reason;
        QStringList blockers;
        QStringList blockerIds;
        qint64 doneBytes = 0;
        qint64 totalBytes = 0;

        bool operator==(const Discovery &other) const {
            return state == other.state && id == other.id && name == other.name && endpoint == other.endpoint
                   && reason == other.reason && blockers == other.blockers && blockerIds == other.blockerIds && doneBytes == other.doneBytes && totalBytes == other.totalBytes;
        }
    };

    // The engine's state folder, its key file, and the command that drives
    // it; empty means the user's own.
    explicit Models(const QString &stateDirectory = {}, const QString &keyPath = {}, const QString &command = {},
                    QObject *parent = nullptr);

    // The music model to use or offer, from the engine's two files: one
    // running, else one on its way, else one set up, else one to set up.
    static Discovery discover(const QJsonObject &status, const QJsonArray &list, bool engine);

    QString state() const { return m_found.state; }
    QString name() const { return m_found.name; }
    QString reason() const { return m_found.reason; }
    QStringList blockers() const { return m_found.blockers; }
    QString error() const { return m_error; }
    bool working() const { return m_process.state() != QProcess::NotRunning || !m_queue.isEmpty(); }
    qint64 doneBytes() const { return m_found.doneBytes; }
    qint64 totalBytes() const { return m_found.totalBytes; }

    // The ready model's server, as scheme://host:port, and the engine's key.
    QString origin() const;
    // The key it takes: the engine's own, or for a paired host's model
    // (host/recipe), the one that host gave when pairing.
    QByteArray key() const;

    // Starts the model that's set up.
    Q_INVOKABLE void start();
    // Stops the text models in a blocked model's way, then starts it.
    Q_INVOKABLE void makeRoom();
    // Sets up the one on offer, or tries again a setup that failed.
    Q_INVOKABLE void install();

signals:
    void changed();

private:
    void reload();
    void run(const QList<QStringList> &commands);
    void runNext();

    QString m_directory;
    QString m_keyPath;
    QString m_command;
    Discovery m_found;
    QString m_error;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QProcess m_process;
    QList<QStringList> m_queue;
};

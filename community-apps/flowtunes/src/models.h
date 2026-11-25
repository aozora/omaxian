#pragma once

#include <QFileSystemWatcher>
#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <tuple>

// Memory as the engine weighs it, in GiB: free is what's available plus what
// a GPU driver holds pooled, -1 when unknown; held is what each running model
// holds now, where the engine has measured it.
struct ModelMemory {
    double freeGib = -1;
    double totalGib = 0;
    QHash<QString, double> held;
};

// The music model omarchy-local-ai runs for Flowtunes. It reads the engine's
// own status.json and list.json, follows their changes, weighs the model
// against the memory that's free, and starts, stops, updates, removes or sets
// up the model through omarchy-models.
class Models : public QObject {
    Q_OBJECT
    // noEngine, none, installable, installing, installed, blocked, starting, ready
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString id READ id NOTIFY changed)
    Q_PROPERTY(QString name READ name NOTIFY changed)
    Q_PROPERTY(QString vendor READ vendor NOTIFY changed)
    // Whether the music model in use sings with lyrics; false for instrumental-only models.
    Q_PROPERTY(bool vocals READ vocals NOTIFY changed)
    // The machine a paired model runs on; empty for this one's own.
    Q_PROPERTY(QString host READ host NOTIFY changed)
    // Why no music model runs here, or why its setup failed.
    Q_PROPERTY(QString reason READ reason NOTIFY changed)
    // What the model needs to run, and what's free for it, in GiB: 0 and -1
    // when they aren't known.
    Q_PROPERTY(double needGib READ needGib NOTIFY changed)
    Q_PROPERTY(double freeGib READ freeGib NOTIFY changed)
    Q_PROPERTY(double totalGib READ totalGib NOTIFY changed)
    // What the model's setup downloads, which is about what removing it frees.
    Q_PROPERTY(double diskGib READ diskGib NOTIFY changed)
    // What the running model holds now, in GiB.
    Q_PROPERTY(double heldGib READ heldGib NOTIFY changed)
    // The other models running here, each {id, name, kind, gib}, biggest first.
    Q_PROPERTY(QVariantList holders READ holders NOTIFY changed)
    // The fewest of them to stop to make room for a blocked model, by name;
    // empty when stopping them wouldn't be enough.
    Q_PROPERTY(QStringList blockers READ blockers NOTIFY changed)
    // Why the engine couldn't do what it was last asked.
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(bool working READ working NOTIFY changed)
    // How far a setup, or an update's download, is: waiting or downloading.
    Q_PROPERTY(QString phase READ phase NOTIFY changed)
    Q_PROPERTY(qint64 doneBytes READ doneBytes NOTIFY changed)
    Q_PROPERTY(qint64 totalBytes READ totalBytes NOTIFY changed)
    Q_PROPERTY(qint64 rateBytes READ rateBytes NOTIFY changed)
    // A starting model's progress, from when it began and how long it took last time.
    Q_PROPERTY(qint64 sinceMs READ sinceMs NOTIFY changed)
    Q_PROPERTY(double loadSeconds READ loadSeconds NOTIFY changed)
    // An update the catalog has for the model, and its download once sized
    // (0 until then); and whether one is running.
    Q_PROPERTY(bool updatable READ updatable NOTIFY changed)
    Q_PROPERTY(qint64 updateBytes READ updateBytes NOTIFY changed)
    Q_PROPERTY(bool updating READ updating NOTIFY changed)
    // The other music models that run here, each {id, name, vendor, vocals, installed, downloadGib, memoryGib}.
    Q_PROPERTY(QVariantList others READ others NOTIFY changed)
    // Every music model available on this machine, best first, for choosing one on first run.
    Q_PROPERTY(QVariantList offers READ offers NOTIFY changed)

public:
    using Memory = ModelMemory;

    struct Discovery {
        QString state;
        QString id;
        QString name;
        QString vendor;
        bool vocals = true;
        QString host;
        QString endpoint;
        QString reason;
        double needGib = 0;
        double freeGib = -1;
        double totalGib = 0;
        double diskGib = 0;
        double heldGib = 0;
        QVariantList holders;
        QStringList blockers;
        QStringList blockerIds;
        QString phase;
        qint64 doneBytes = 0;
        qint64 totalBytes = 0;
        qint64 rateBytes = 0;
        qint64 sinceMs = 0;
        double loadSeconds = 0;
        bool updatable = false;
        qint64 updateBytes = 0;
        bool updating = false;
        QVariantList others;
        QVariantList offers;

        auto tied() const {
            return std::tie(state, id, name, vendor, vocals, host, endpoint, reason, needGib, freeGib, totalGib, diskGib, heldGib, holders,
                            blockers, blockerIds, phase, doneBytes, totalBytes, rateBytes, sinceMs, loadSeconds, updatable,
                            updateBytes, updating, others, offers);
        }
        bool operator==(const Discovery &other) const { return tied() == other.tied(); }
    };

    // The engine's state folder, its key file, the command that drives it,
    // and where the kernel says how much memory is free; empty means the
    // user's own.
    explicit Models(const QString &stateDirectory = {}, const QString &keyPath = {}, const QString &command = {},
                    const QString &meminfo = {}, QObject *parent = nullptr);

    // The music model to use or offer, from the engine's two files and the
    // memory free: the one picked in the sheet when it's set up, else one
    // running, else one on its way, else one set up, else one to set up.
    static Discovery discover(const QJsonObject &status, const QJsonArray &list, bool engine, const Memory &memory = {},
                              const QString &preferred = {});
    // Free and total memory from /proc/meminfo's text, as the engine counts them.
    static Memory memoryOf(const QByteArray &meminfo);

    QString state() const { return m_found.state; }
    QString id() const { return m_found.id; }
    QString name() const { return m_found.name; }
    QString vendor() const { return m_found.vendor; }
    bool vocals() const { return m_found.vocals; }
    QString host() const { return m_found.host; }
    QString reason() const { return m_found.reason; }
    double needGib() const { return m_found.needGib; }
    double freeGib() const { return m_found.freeGib; }
    double totalGib() const { return m_found.totalGib; }
    double diskGib() const { return m_found.diskGib; }
    double heldGib() const { return m_found.heldGib; }
    QVariantList holders() const { return m_found.holders; }
    QStringList blockers() const { return m_found.blockers; }
    QString error() const { return m_error; }
    bool working() const { return m_process.state() != QProcess::NotRunning || !m_queue.isEmpty(); }
    QString phase() const { return m_found.phase; }
    qint64 doneBytes() const { return m_found.doneBytes; }
    qint64 totalBytes() const { return m_found.totalBytes; }
    qint64 rateBytes() const { return m_found.rateBytes; }
    qint64 sinceMs() const { return m_found.sinceMs; }
    double loadSeconds() const { return m_found.loadSeconds; }
    bool updatable() const { return m_found.updatable; }
    qint64 updateBytes() const { return m_found.updateBytes; }
    bool updating() const { return m_found.updating; }
    QVariantList others() const { return m_found.others; }
    QVariantList offers() const { return m_found.offers; }

    // The vendor's mark as Omarchy's agents panel draws it: dark version on a
    // light theme where there is one, local model's mark when unknown, empty without Omarchy.
    Q_INVOKABLE static QString logo(const QString &vendor, bool light);

    // The ready model's server, as scheme://host:port, and the engine's key.
    QString origin() const;
    // The key it takes: the engine's own, or for a paired host's model
    // (host/recipe), the one that host gave when pairing.
    QByteArray key() const;

    // Starts the model that's set up.
    Q_INVOKABLE void start();
    // Stops the models in a blocked model's way, then starts it.
    Q_INVOKABLE void makeRoom();
    // Sets up the chosen music model (or the default offer when empty), or tries again one that failed.
    Q_INVOKABLE void install(const QString &id = {});
    // Stops the running model, to give its memory back.
    Q_INVOKABLE void stop();
    // On quit: lets go of the model in use, then stops every music model
    // running here that no other app holds, nor a tailnet machine uses.
    void release();
    // Brings the model up to what the catalog has now.
    Q_INVOKABLE void update();
    // Removes the model's weights, to give its disk back.
    Q_INVOKABLE void remove();
    // Plays with another music model from now on, setting it up first when
    // it isn't; the one in use is stopped to make room for it.
    Q_INVOKABLE void use(const QString &id);
    // Reads again what memory is free and what each model holds, which
    // nothing announces: when a start is asked for, and when the window or
    // the sheet is looked at.
    Q_INVOKABLE void checkMemory();

signals:
    void changed();

private:
    void reload();
    void rediscover();
    void measure(bool always);
    void run(const QList<QStringList> &commands);
    void runNext();
    // Holds the model in use through the engine for as long as the app runs,
    // so another app quitting leaves it running.
    void hold();

    QString m_directory;
    QString m_keyPath;
    QString m_command;
    QString m_meminfo;
    QJsonObject m_status;
    QJsonArray m_list;
    Memory m_memory;
    Discovery m_found;
    QString m_error;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QProcess m_process;
    QProcess m_meter;
    QList<QStringList> m_queue;
    QProcess m_hold;
    QString m_held;
    // The models running here when memory was last measured.
    QStringList m_running;
};

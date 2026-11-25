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

// The image models omarchy-local-ai knows about, and which one Fantasi uses.
// It reads the engine's own status.json and list.json, follows their changes,
// and starts or sets up a model through omarchy-models.
class Models : public QObject {
    Q_OBJECT
    // noEngine, none, installable, installing, installed, blocked, starting, ready
    Q_PROPERTY(QString state READ state NOTIFY changed)
    Q_PROPERTY(QString modelId READ modelId NOTIFY changed)
    Q_PROPERTY(QString modelName READ modelName NOTIFY changed)
    // Whether the model changes an image by an instruction (an edit model),
    // rather than redrawing it from a description.
    Q_PROPERTY(bool edits READ edits NOTIFY changed)
    // Why nothing runs here, or why the model can't start now.
    Q_PROPERTY(QString reason READ reason NOTIFY changed)
    // The running text models that hold the memory a blocked model needs.
    Q_PROPERTY(QStringList blockers READ blockers NOTIFY changed)
    Q_PROPERTY(bool working READ working NOTIFY changed)
    // Every image model that's set up, as {id, name}, in the order to step
    // through them; the one in use among them. A model still being set up
    // isn't one yet.
    Q_PROPERTY(QVariantList choices READ choices NOTIFY changed)
    // Setting up this machine's first image model: from when none is set up,
    // through its download and first start, until it's ready.
    Q_PROPERTY(bool settingUp READ settingUp NOTIFY changed)
    // What a first run offers to download: the image, music and video model
    // this machine runs, each with its sizes and how far its setup has come.
    Q_PROPERTY(QVariantList offers READ offers NOTIFY changed)
    // The setup's progress: waiting, downloading, starting or failed, what it
    // has fetched of how much and how fast, and how long the start takes.
    Q_PROPERTY(QString setupPhase READ setupPhase NOTIFY changed)
    Q_PROPERTY(qint64 doneBytes READ doneBytes NOTIFY changed)
    Q_PROPERTY(qint64 totalBytes READ totalBytes NOTIFY changed)
    Q_PROPERTY(qint64 rateBytes READ rateBytes NOTIFY changed)
    Q_PROPERTY(qint64 startedMs READ startedMs NOTIFY changed)
    Q_PROPERTY(double loadSeconds READ loadSeconds NOTIFY changed)
    Q_PROPERTY(QString vendor READ vendor NOTIFY changed)
    Q_PROPERTY(bool canEdit READ canEdit NOTIFY changed)
    // The model in use makes clips with their sound rather than images.
    Q_PROPERTY(bool video READ video NOTIFY changed)
    // The model in use makes songs.
    Q_PROPERTY(bool music READ music NOTIFY changed)
    // Whether the music model in use sings with lyrics; false for instrumental-only models.
    Q_PROPERTY(bool vocals READ vocals NOTIFY changed)
    // The clip lengths, in seconds, the video model in use makes here.
    Q_PROPERTY(QVariantList clipLengths READ clipLengths NOTIFY changed)
    // The model being started in place of the one in use, while it starts.
    Q_PROPERTY(QString switchingTo READ switchingTo NOTIFY changed)
    Q_PROPERTY(QString switchingVendor READ switchingVendor NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    // Every image, video and music model for this machine, by id: set up,
    // being set up, there to set up, or not for this machine and why. The
    // ids come in the order the manager lists them, and change only when
    // a model comes or goes, so its rows stay put while one downloads.
    Q_PROPERTY(QStringList libraryIds READ libraryIds NOTIFY libraryIdsChanged)
    Q_PROPERTY(QVariantMap library READ library NOTIFY libraryChanged)
    // The memory: the machine's, what's free for a model to load into, and
    // the running models of every kind holding some, as {id, name, kind, gib}.
    Q_PROPERTY(double memoryTotal READ memoryTotal NOTIFY libraryChanged)
    Q_PROPERTY(double memoryFree READ memoryFree NOTIFY libraryChanged)
    Q_PROPERTY(QVariantList holders READ holders NOTIFY libraryChanged)
    // While the manager is open, memory is read every few seconds: it has no
    // change signal, and what a running model holds moves as it works.
    Q_PROPERTY(bool watching READ watching WRITE setWatching NOTIFY watchingChanged)

public:
    struct Discovery {
        QString state;
        QString id;
        QString name;
        QString endpoint;
        bool edits = false;
        QString reason;
        QStringList blockers;
        QStringList blockerIds;
        QVariantList choices;
        QVariantList offers;
        // A running model that edits by instruction, for changing a picture
        // whichever model makes new ones.
        QString editEndpoint;
        QString editId;
        // Who makes the model, as Omarchy names vendors: bfl, alibaba, qwen.
        QString vendor;
        // A setup in progress, from the engine's installing row; a model
        // starting reports since when and how long a start takes.
        QString setupPhase;
        qint64 doneBytes = 0;
        qint64 totalBytes = 0;
        qint64 rateBytes = 0;
        qint64 startedMs = 0;
        double loadSeconds = 0;
        // Starting for the first time ever: the engine records how a start went
        // (`observed`) only once one has succeeded.
        bool firstStart = false;
        // The model in use makes clips rather than images.
        bool video = false;
        // The model in use makes songs.
        bool music = false;
        // Whether the music model in use sings with lyrics.
        bool vocals = true;
        // The longest clip a video model makes on its machine now, as its
        // engine works it out; -1 from an engine that doesn't say.
        int maxSeconds = -1;
    };

    // What's free for a model to load into, as the engine decides whether one
    // fits (available memory plus what a GPU driver keeps pooled), in GiB, and
    // what each running model holds now, by id, where the engine measured it.
    struct Memory {
        double total = 0;
        double free = 0;
        QHash<QString, double> held;
    };
    static Memory parseMeminfo(const QByteArray &meminfo);
    // The running models of every kind, holding memory, biggest first.
    static QVariantList holdersFrom(const QJsonObject &status, const QJsonArray &list, const Memory &memory);
    // Which of the holders to stop so `needs` GiB fit: one that frees enough
    // on its own, the smallest such, or else the biggest until enough is
    // free. `shortBy` is what's still missing once all of them are stopped.
    static QVariantList roomFor(double needs, double free, const QVariantList &holders, const QString &except,
                                double *shortBy);
    // The manager's rows, by id, each with its section (image, video, music
    // or unavailable) and what it needs, holds and would take to start.
    static QVariantMap libraryFrom(const QJsonObject &status, const QJsonArray &list, const Memory &memory,
                                   const QString &inUse, QStringList *order);

    // The engine's state folder, its key file, and the command that drives
    // it; empty means the user's own.
    explicit Models(const QString &stateDirectory = {}, const QString &keyPath = {}, const QString &command = {},
                    QObject *parent = nullptr);
    // A process still running when the window closes finishes as it's
    // destroyed, after the state its handlers read is gone: they're let go first.
    ~Models() override {
        m_process.disconnect(this);
        m_memoryProcess.disconnect(this);
    }
    // On quit: lets go of the models in use, then stops every media model
    // running here that no other app holds, nor a tailnet machine uses.
    void release();

    // What to use or offer, from the engine's two files. A row without a kind
    // is a text model, as every row was before the engine had image models.
    static Discovery discover(const QJsonObject &status, const QJsonArray &list, bool engine,
                              const QString &preferred = {});

    QString state() const { return m_found.state; }
    QString modelId() const { return m_found.id; }
    QString modelName() const { return m_found.name; }
    bool edits() const { return m_found.edits; }
    QString reason() const { return m_found.reason; }
    QStringList blockers() const { return m_found.blockers; }
    QVariantList choices() const { return m_found.choices; }
    // Whether a running model edits by instruction, which can take several pictures.
    bool canEdit() const { return !m_found.editEndpoint.isEmpty(); }
    bool video() const { return m_found.video; }
    bool music() const { return m_found.music; }
    bool vocals() const { return m_found.vocals; }
    QVariantList clipLengths() const;
    // 2, 5, 10, then every 5 seconds, up to the longest that fits: 2, 5 and
    // 10 when the engine doesn't say, and 2 when not even that fits.
    static QList<int> lengthsUpTo(int maxSeconds);
    QString switchingTo() const { return choiceField(m_chosen, "name"); }
    QString switchingVendor() const { return choiceField(m_chosen, "vendor"); }
    // The video model's server, when it's the one in use and running.
    QString videoOrigin() const;
    QByteArray videoKey() const { return key(); }
    QString vendor() const { return m_found.vendor; }
    bool settingUp() const { return m_settingUp; }
    QVariantList offers() const { return m_found.offers; }
    // For each of image, music and video, the model this machine runs best:
    // id, kind, name, vendor, downloadBytes and memoryBytes (0 when the
    // engine doesn't say), and phase, one of offer, waiting, downloading,
    // starting, ready, installed or failed, with its progress and error.
    static QVariantList offersFrom(const QJsonObject &status, const QJsonArray &list);
    QString setupPhase() const { return m_found.setupPhase; }
    qint64 doneBytes() const { return m_found.doneBytes; }
    qint64 totalBytes() const { return m_found.totalBytes; }
    qint64 rateBytes() const { return m_found.rateBytes; }
    qint64 startedMs() const { return m_found.startedMs; }
    double loadSeconds() const { return m_found.loadSeconds; }

    // The vendor's mark as the agents panel draws it, from Omarchy's own
    // set: its dark version on a light theme where there is one, the local
    // model's for a vendor without a mark, and empty without Omarchy.
    Q_INVOKABLE static QString logo(const QString &vendor, bool light);
    bool working() const { return m_process.state() != QProcess::NotRunning || !m_queue.isEmpty(); }
    QString error() const { return m_error; }

    // The ready model's server, as scheme://host:port, and the engine's key.
    QString origin() const;
    // The server of a running edit model, empty when none runs.
    QString editOrigin() const;
    QByteArray key() const { return keyFor(m_found.id); }
    // The key a model takes: the engine's own, or for a paired host's model
    // (host/recipe), the one that host gave when pairing.
    QByteArray keyFor(const QString &id) const;
    QByteArray editKey() const { return keyFor(m_found.editId); }

    Q_INVOKABLE void start();
    Q_INVOKABLE void install();
    // Sets up an offer; the engine queues one asked for while another downloads.
    Q_INVOKABLE void download(const QString &id);
    // The first prompt is sent: the first run is over.
    Q_INVOKABLE void endSetup();
    // Stops the text models in the way, then starts the image model.
    Q_INVOKABLE void switchTo();
    // Uses another set-up image model from now on: stops the running one
    // and starts it.
    Q_INVOKABLE void choose(const QString &id);
    // A model's own actions in the manager. Starting one stops what's in
    // its way first, and makes it the one in use.
    Q_INVOKABLE void setUp(const QString &id);
    Q_INVOKABLE void startModel(const QString &id);
    Q_INVOKABLE void stop(const QString &id);
    Q_INVOKABLE void update(const QString &id);
    // Removes a model's weights, or cancels or dismisses its setup.
    Q_INVOKABLE void remove(const QString &id);
    // Reads the free memory again, as when the window comes to the front.
    Q_INVOKABLE void readMemory();

    QStringList libraryIds() const { return m_libraryIds; }
    QVariantMap library() const { return m_library; }
    double memoryTotal() const { return m_memory.total; }
    double memoryFree() const { return m_memory.free; }
    QVariantList holders() const { return m_holders; }
    bool watching() const { return m_memoryTimer.isActive(); }
    void setWatching(bool watching);
    // /proc/meminfo, or a stand-in for tests.
    void setMeminfoPath(const QString &path) { m_meminfoPath = path; reload(); }

signals:
    void changed();
    void libraryChanged();
    void libraryIdsChanged();
    void watchingChanged();

private:
    void reload();
    QString choiceField(const QString &id, const QString &field) const {
        for (const QVariant &choice : m_found.choices)
            if (choice.toMap().value("id").toString() == id)
                return choice.toMap().value(field).toString();
        return {};
    }
    void run(const QList<QStringList> &commands);
    void runNext();
    void updateLibrary();
    void readMeminfo();
    // What starting a model takes: stopping what's in its way, then the start.
    QList<QStringList> startCommands(const QString &id) const;
    // Holds the models in use through the engine for as long as the app
    // runs, so another app quitting leaves them running.
    void hold();

    QString m_directory;
    QString m_keyPath;
    QString m_command;
    Discovery m_found;
    QString m_error;
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QProcess m_process;
    QList<QStringList> m_queue;
    // The model chosen, kept as the one to use once it has started.
    QString m_chosen;
    bool m_settingUp = false;
    // The engine's own files as last read, for the manager.
    QJsonObject m_status;
    QJsonArray m_list;
    Memory m_memory;
    QString m_meminfoPath = "/proc/meminfo";
    QProcess m_memoryProcess;
    QProcess m_hold;
    QStringList m_held;
    QTimer m_memoryTimer;
    QVariantMap m_library;
    QStringList m_libraryIds;
    QVariantList m_holders;
    double m_shownTotal = -1;
    double m_shownFree = -1;
};

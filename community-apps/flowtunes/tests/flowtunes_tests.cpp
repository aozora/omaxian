#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QProcess>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QRandomGenerator>
#include <QRegularExpression>
#include <QSettings>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QUrlQuery>
#include <QtEndian>
#include <QtTest>
#include <memory>

#include "backend.h"
#include "flow.h"
#include "genres.h"
#include "models.h"
#include "mpris.h"
#include "theme.h"
#include "translator.h"

namespace {

bool write(const QString &path, const QByteArray &contents) {
    QFile file(path);
    return file.open(QIODevice::WriteOnly) && file.write(contents) == contents.size();
}

int lines(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll().count('\n') : 0;
}

// The window's item with this objectName. What a Repeater, ListView or Loader
// makes isn't a QObject child of the window, so findChild never finds it; walk
// the items instead. Popups aren't items: find those with findChild.
QQuickItem *item(QQuickItem *from, const QString &name) {
    for (auto *child : from->childItems()) {
        if (child->objectName() == name)
            return child;
        if (auto *found = item(child, name))
            return found;
    }
    return nullptr;
}

// A hyprctl that answers with response.json beside it and counts its calls.
QString fakeHyprctl(const QString &directory) {
    const QString command = directory + "/hyprctl";
    write(command, "#!/bin/bash\necho >> '" + directory.toUtf8() + "/calls'\ncat '" + directory.toUtf8()
                       + "/response.json'\n");
    QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    return command;
}

QJsonObject readCatalog(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? QJsonDocument::fromJson(file.readAll()).object() : QJsonObject();
}

// The placeholders in a text, sorted: %1 to %99, and the count (%n, %Ln).
QStringList placeholders(const QString &text) {
    static const QRegularExpression placeholder("%L?(?:[1-9][0-9]?|n)");
    QStringList found;
    for (auto it = placeholder.globalMatch(text); it.hasNext();)
        found << it.next().captured();
    found.sort();
    return found;
}

// Every text the sources hand to qsTr() or tr(), and whether a call passes it
// a count. It walks the code a token at a time, so a string never hides a
// comment or the other way round, C++'s adjacent literals join, and QML's
// single quotes count. A text that isn't a literal can't be in a catalog.
QMap<QString, bool> translatables(const QString &folder, QStringList *problems) {
    QMap<QString, bool> found;
    for (const QFileInfo &info : QDir(folder).entryInfoList({"*.qml", "*.js", "*.cpp", "*.h"}, QDir::Files)) {
        QFile file(info.filePath());
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QString code = QString::fromUtf8(file.readAll());
        qsizetype i = 0;
        auto literal = [&](QString *text) {
            const QChar quote = code[i++];
            for (; i < code.size() && code[i] != quote; ++i) {
                if (code[i] == '\\' && i + 1 < code.size()) {
                    const QChar escaped = code[++i];
                    const int digits = escaped == 'u' ? 4 : escaped == 'x' ? 2 : 0;
                    bool hex = false;
                    const ushort unit = code.mid(i + 1, digits).toUShort(&hex, 16);
                    if (digits && hex) {
                        *text += QChar(unit);
                        i += digits;
                    } else {
                        *text += escaped == 'n' ? QChar('\n') : escaped == 't' ? QChar('\t') : escaped;
                    }
                } else {
                    *text += code[i];
                }
            }
            ++i;
        };
        auto skipSpace = [&] {
            while (i < code.size() && code[i].isSpace())
                ++i;
        };
        while (i < code.size()) {
            const QChar c = code[i];
            if (code.mid(i, 2) == "//") {
                i = code.indexOf('\n', i);
                if (i < 0)
                    break;
            } else if (code.mid(i, 2) == "/*") {
                i = code.indexOf("*/", i + 2);
                if (i < 0)
                    break;
                i += 2;
            } else if (c == '"' || c == '\'') {
                QString skipped;
                literal(&skipped);
            } else if (c.isLetter() || c == '_') {
                const qsizetype start = i;
                while (i < code.size() && (code[i].isLetterOrNumber() || code[i] == '_'))
                    ++i;
                const QString word = code.mid(start, i - start);
                skipSpace();
                if ((word != "qsTr" && word != "tr") || i >= code.size() || code[i] != '(')
                    continue;
                ++i;
                skipSpace();
                if (i >= code.size() || (code[i] != '"' && code[i] != '\'')) {
                    *problems << info.fileName() + ": not a literal: " + code.mid(start, 40);
                    continue;
                }
                QString text;
                do {
                    literal(&text);
                    skipSpace();
                } while (i < code.size() && code[i] == '"');
                // The arguments after the text, to the call's closing parenthesis.
                int depth = 0, commas = 0;
                while (i < code.size()) {
                    const QChar d = code[i];
                    if (d == '"' || d == '\'') {
                        QString skipped;
                        literal(&skipped);
                        continue;
                    }
                    if (d == '(' || d == '[' || d == '{')
                        ++depth;
                    else if ((d == ')' || d == ']' || d == '}') && depth-- == 0)
                        break;
                    else if (d == ',' && depth == 0)
                        ++commas;
                    ++i;
                }
                found[text] = found.value(text) || commas >= 2;
            } else {
                ++i;
            }
        }
    }
    return found;
}

// A music model's server: it takes the jobs Flowtunes hands it, remembers
// every request, and answers a job's result with a written-out song or a
// rendered MP3. `held` keeps jobs running, and `broken` fails them.
struct FakeServer : QObject {
    QTcpServer server;
    QStringList requests;
    QList<QJsonObject> bodies;
    QByteArray sound;
    bool held = false;
    bool broken = false;
    // How many songs asked for with lyrics it writes without any first.
    int shy = 0;
    QHash<QString, bool> worded;
    int jobs = 0;
    QHash<QString, QString> kinds;

    FakeServer() {
        server.listen(QHostAddress::LocalHost);
        connect(&server, &QTcpServer::newConnection, this, [this] {
            while (QTcpSocket *socket = server.nextPendingConnection()) {
                auto buffer = std::make_shared<QByteArray>();
                connect(socket, &QTcpSocket::readyRead, socket, [this, socket, buffer] {
                    *buffer += socket->readAll();
                    const qsizetype end = buffer->indexOf("\r\n\r\n");
                    if (end < 0)
                        return;
                    const QList<QByteArray> head = buffer->left(end).split('\n');
                    qsizetype length = 0;
                    for (const QByteArray &line : head)
                        if (line.toLower().startsWith("content-length:"))
                            length = line.mid(15).trimmed().toLongLong();
                    if (buffer->size() < end + 4 + length)
                        return;
                    const QList<QByteArray> request = head.first().split(' ');
                    const QString method = request.value(0), path = request.value(1);
                    requests << method + " " + path;
                    bodies << QJsonDocument::fromJson(buffer->mid(end + 4, length)).object();
                    const QByteArray body = answer(method, path);
                    socket->write("HTTP/1.1 200 OK\r\nContent-Length: " + QByteArray::number(body.size())
                                  + "\r\nConnection: close\r\n\r\n" + body);
                    socket->disconnectFromHost();
                    buffer->clear();
                });
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            }
        });
    }

    QByteArray answer(const QString &method, const QString &path) {
        if (method == "POST" && (path == "/lm" || path == "/synth")) {
            const QString id = QString::number(++jobs);
            kinds[id] = path;
            // Left without lyrics, it's the model that writes them.
            worded[id] = path == "/lm" && bodies.last().value("lyrics").toString().isEmpty() && shy-- <= 0;
            return "{\"id\":\"" + id.toLatin1() + "\"}";
        }
        const QString id = QUrlQuery(QUrl(path).query()).queryItemValue("id");
        if (path.contains("cancel=1"))
            return "{}";
        if (!path.contains("result=1"))
            return broken ? "{\"status\":\"failed\"}" : held ? "{\"status\":\"running\"}" : "{\"status\":\"done\"}";
        if (worded.value(id))
            return QJsonDocument(QJsonArray{QJsonObject{{"caption", "written out"}, {"lyrics", "[Verse]\nLa la la\nOh la la\n[Chorus]\nLa"},
                                                        {"bpm", 88}, {"keyscale", "C minor"}, {"audio_codes", "1,2,3"}}}).toJson();
        if (kinds.value(id) == "/lm")
            return R"([{"caption":"written out","lyrics":"[Instrumental]","bpm":88,"keyscale":"C minor","audio_codes":"1,2,3"}])";
        return "--ace-batch-boundary\r\nContent-Type: audio/mpeg\r\n\r\n" + sound + "\r\n--ace-batch-boundary--\r\n";
    }

    int count(const QString &request) const { return requests.count(request); }
    QString origin() const { return QString("http://127.0.0.1:%1").arg(server.serverPort()); }
};

// An engine state folder with one music model in `unit` at `origin`, and a key.
void engineWith(const QString &folder, const QString &unit, const QString &origin) {
    QDir().mkpath(folder);
    write(folder + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{{"ace-step", QJsonObject{
        {"kind", "music"}, {"name", "ACE-Step 1.5 Turbo"}, {"unit", unit}, {"endpoint", origin + "/v1"}}}}}}).toJson());
    write(folder + "/list.json", "[]");
    write(folder + "/key", "secret\n");
}

// A second of a real MP3, as the model would render one.
QByteArray tone() {
    QProcess ffmpeg;
    ffmpeg.start("ffmpeg", {"-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=1", "-f", "mp3", "-"});
    ffmpeg.waitForFinished();
    return ffmpeg.readAllStandardOutput();
}

// A stand-in for omarchy-models that notes what it was asked.
QString fakeEngine(const QString &folder) {
    const QString path = folder + "/engine";
    // The refresh every start asks for, and what the running models hold,
    // are beside the point of any test that doesn't say otherwise. The hold
    // on the model in use is noted on its own, and lasts until its input
    // closes, as the engine's does.
    write(path, "#!/bin/sh\n[ \"$1\" = refresh ] && exit 0\n[ \"$1\" = memory ] && { cat \"$(dirname \"$0\")/held\" 2>/dev/null || echo {}; exit 0; }\n"
                "[ \"$1\" = hold ] && { echo \"$@\" >> \"$(dirname \"$0\")/holding\"; cat > /dev/null; echo released >> \"$(dirname \"$0\")/holding\"; exit 0; }\n"
                "echo \"$@\" >> \"$(dirname \"$0\")/asked\"\n");
    QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    return path;
}

} // namespace

class FlowtunesTests : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() {
        QQuickStyle::setStyle("Material");
        // The genre played last is remembered in the settings: never the user's own.
        QStandardPaths::setTestModeEnabled(true);
        QCoreApplication::setOrganizationName("flowtunes");
        QCoreApplication::setApplicationName("flowtunes");
        m_tone = tone();
        QVERIFY(m_tone.size() > 1000);
    }

    void init() { QSettings().clear(); }

    void everyGenreAsksForItsOwnSoundWithoutAVoice() {
        const QStringList ids = Genres::ids();
        QCOMPARE(ids.size(), 12);
        QCOMPARE(QSet<QString>(ids.begin(), ids.end()).size(), 12);
        QRandomGenerator random(7);
        for (const Genre &genre : Genres::all()) {
            QSet<QString> captions;
            for (int i = 0; i < 20; ++i) {
                const QString caption = Genres::caption(genre.id, random);
                QVERIFY(caption.startsWith(genre.sound));
                QVERIFY(caption.endsWith(", instrumental"));
                captions << caption;
            }
            // One tune is asked for differently from the next.
            QVERIFY2(captions.size() > 5, qPrintable(genre.id));
        }
        QVERIFY(Genres::caption("polka", random).isEmpty());
        QVERIFY(Genres::caption("jazz", random, true).startsWith("vocal jazz song"));
        QVERIFY(!Genres::caption("jazz", random, true).contains("instrumental"));
        QCOMPARE(Flow::sungLines("[Intro]\n\n[Instrumental]"), 0);
        QCOMPARE(Flow::sungLines("[Verse]\nOne line\n And another\n\n[Chorus]\nA third"), 3);
    }

    void modelsFindTheMusicModel() {
        const auto status = [](const QString &kind, const QString &unit) {
            return QJsonObject{{"models", QJsonObject{{"m", QJsonObject{{"kind", kind}, {"name", "M"}, {"unit", unit},
                                                                       {"endpoint", "http://127.0.0.1:1/v1"}}}}}};
        };
        QCOMPARE(Models::discover({}, {}, false).state, QString("noEngine"));
        QCOMPARE(Models::discover({}, {}, true).state, QString("none"));
        QCOMPARE(Models::discover(status("music", "active"), {}, true).state, QString("ready"));
        QCOMPARE(Models::discover(status("music", "activating"), {}, true).state, QString("starting"));
        QCOMPARE(Models::discover(status("music", "inactive"), {}, true).state, QString("installed"));
        QCOMPARE(Models::discover(status("music", "installing"), {}, true).state, QString("installing"));
        // A stopped model that doesn't fit waits for the text models in its way.
        QJsonObject crowded = status("music", "inactive");
        QJsonObject rows = crowded.value("models").toObject();
        QJsonObject music = rows.value("m").toObject();
        music.insert("fits", false);
        music.insert("fit_reason", "needs 8 GiB");
        rows.insert("m", music);
        rows.insert("llm", QJsonObject{{"kind", "text"}, {"name", "Big Talker"}, {"unit", "active"}});
        rows.insert("idle", QJsonObject{{"kind", "text"}, {"name", "Quiet One"}, {"unit", "inactive"}});
        crowded.insert("models", rows);
        const Models::Discovery blocked = Models::discover(crowded, {}, true);
        QCOMPARE(blocked.state, QString("blocked"));
        QCOMPARE(blocked.blockers, QStringList{"Big Talker"});
        QCOMPARE(blocked.blockerIds, QStringList{"llm"});
        QCOMPARE(blocked.reason, QString("needs 8 GiB"));
        // An image model is no use here.
        QCOMPARE(Models::discover(status("image", "active"), {}, true).state, QString("none"));

        const QJsonArray list{QJsonObject{{"id", "z"}, {"kind", "image"}, {"available", true}},
                              QJsonObject{{"id", "a"}, {"kind", "music"}, {"name", "A"}, {"available", false}, {"reason", "no GPU"}},
                              QJsonObject{{"id", "b"}, {"kind", "music"}, {"name", "B"}, {"available", true}}};
        const Models::Discovery offered = Models::discover({}, list, true);
        QCOMPARE(offered.state, QString("installable"));
        QCOMPARE(offered.name, QString("B"));
        const Models::Discovery unfit = Models::discover({}, QJsonArray{list[0], list[1]}, true);
        QCOMPARE(unfit.state, QString("none"));
        QCOMPARE(unfit.reason, QString("no GPU"));
    }

    void modelsWeighTheMemoryFree() {
        // As the engine counts it: what's available and what a GPU driver keeps pooled.
        const Models::Memory read = Models::memoryOf("MemTotal:       65011712 kB\nMemFree:  1 kB\nMemAvailable:    3145728 kB\nGPUReclaim:      1048576 kB\n");
        QCOMPARE(read.totalGib, 62.0);
        QCOMPARE(read.freeGib, 4.0);
        QCOMPARE(Models::memoryOf("").freeGib, -1.0);

        const auto running = [](const QString &kind, double gib) {
            return QJsonObject{{"kind", kind}, {"name", kind + " model"}, {"unit", "active"}, {"observed", QJsonObject{{"ram_used_gib", gib}}}};
        };
        const QJsonObject status{{"models", QJsonObject{
            {"ace", QJsonObject{{"kind", "music"}, {"name", "ACE"}, {"unit", "inactive"}, {"fits", true}}},
            {"qwen", running("text", 40)}, {"flux", running("image", 11)}, {"wan", running("video", 3)},
            {"far", QJsonObject{{"kind", "text"}, {"unit", "active"}, {"host", "studio"}}}}}};
        const QJsonArray list{QJsonObject{{"id", "ace"}, {"kind", "music"}, {"available", true}, {"memory_gib", 8}, {"download_gib", 7.5}}};
        Models::Memory memory;
        memory.freeGib = 9;
        Models::Discovery found = Models::discover(status, list, true, memory);
        QCOMPARE(found.state, QString("installed"));
        QCOMPARE(found.needGib, 8.0);
        QCOMPARE(found.diskGib, 7.5);
        // Every model running here holds memory, whatever its kind, biggest
        // first; a paired host's holds its own.
        QCOMPARE(found.holders.size(), 3);
        QCOMPARE(found.holders.first().toMap().value("name").toString(), QString("text model"));

        // Short by 5: of the models that would make room alone, the smallest
        // is stopped, leaving the big text model someone's coding with.
        memory.freeGib = 3;
        found = Models::discover(status, list, true, memory);
        QCOMPARE(found.state, QString("blocked"));
        QCOMPARE(found.blockerIds, QStringList{"flux"});
        // What the engine measures a model holding now counts over what it
        // took to load. With none enough alone, the biggest go first.
        memory.held.insert("qwen", 2);
        memory.held.insert("flux", 1);
        found = Models::discover(status, list, true, memory);
        QCOMPARE(found.blockerIds, (QStringList{"wan", "qwen"}));
        memory.freeGib = 2;
        found = Models::discover(status, list, true, memory);
        QCOMPARE(found.blockerIds, (QStringList{"wan", "qwen", "flux"}));
        // Stopping them all wouldn't be enough: nothing to offer to stop.
        memory.held.insert("wan", 1);
        found = Models::discover(status, list, true, memory);
        QCOMPARE(found.state, QString("blocked"));
        QVERIFY(found.blockers.isEmpty());
    }

    void modelsPlayWithTheOnePicked() {
        const QJsonObject status{{"models", QJsonObject{
            {"ace", QJsonObject{{"kind", "music"}, {"name", "ACE"}, {"unit", "active"}}},
            {"other", QJsonObject{{"kind", "music"}, {"name", "Other"}, {"unit", "inactive"}}}}}};
        const QJsonArray list{QJsonObject{{"id", "ace"}, {"kind", "music"}, {"available", true}, {"installed", true}},
                              QJsonObject{{"id", "other"}, {"kind", "music"}, {"available", true}, {"installed", true}},
                              QJsonObject{{"id", "new"}, {"kind", "music"}, {"name", "New"}, {"available", true}, {"best", true}}};
        QCOMPARE(Models::discover(status, list, true).id, QString("ace"));
        QCOMPARE(Models::discover(status, list, true).others.size(), 2);
        QCOMPARE(Models::discover(status, list, true, {}, "other").id, QString("other"));
        // One picked that isn't set up yet is offered, over the recommended one.
        QCOMPARE(Models::discover({}, list, true).id, QString("new"));
        QCOMPARE(Models::discover({}, list, true, {}, "ace").id, QString("ace"));
    }

    void modelsFollowTheEngine() {
        QTemporaryDir dir;
        engineWith(dir.path(), "inactive", "http://127.0.0.1:1");
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        QCOMPARE(models.state(), QString("installed"));
        QCOMPARE(models.key(), QByteArray("secret"));

        models.start();
        QTRY_VERIFY(!models.working());
        QFile asked(dir.path() + "/asked");
        QVERIFY(asked.open(QIODevice::ReadOnly));
        QCOMPARE(asked.readAll(), QByteArray("start ace-step\n"));

        engineWith(dir.path(), "active", "http://127.0.0.1:1");
        QTRY_COMPARE(models.state(), QString("ready"));
        QCOMPARE(models.origin(), QString("http://127.0.0.1:1"));
    }

    void holdsTheModelInUseAndStopsTheMusicModelsOnQuit() {
        QTemporaryDir dir;
        engineWith(dir.path(), "active", "http://127.0.0.1:1");
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        const auto read = [&](const QString &name) {
            QFile file(dir.path() + "/" + name);
            return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
        };
        QTRY_COMPARE(read("holding"), QByteArray("hold ace-step\n"));
        // Held for as long as the app runs, and let go before anything is stopped.
        QTest::qWait(200);
        QCOMPARE(read("holding"), QByteArray("hold ace-step\n"));
        models.release();
        QCOMPARE(read("holding"), QByteArray("hold ace-step\nreleased\n"));
        QTRY_COMPARE(read("asked"), QByteArray("stop --unless-used ace-step\n"));
    }

    void aBlockedModelIsStartedOnceItsWayIsCleared() {
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"ace-step", QJsonObject{{"kind", "music"}, {"name", "ACE-Step"}, {"unit", "inactive"}, {"fits", false}}},
            {"llm", QJsonObject{{"kind", "text"}, {"name", "Big Talker"}, {"unit", "active"}}}}}}).toJson()));
        QVERIFY(write(dir.path() + "/list.json", "[]"));
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        QCOMPARE(models.state(), QString("blocked"));
        // The flow doesn't stop anyone's model by itself.
        flow.play("jazz");
        QTest::qWait(300);
        QVERIFY(!QFile::exists(dir.path() + "/asked"));
        QVERIFY(flow.error().isEmpty());

        models.makeRoom();
        QTRY_VERIFY(!models.working());
        QFile asked(dir.path() + "/asked");
        QVERIFY(asked.open(QIODevice::ReadOnly));
        QCOMPARE(asked.readAll(), QByteArray("stop llm\nstart ace-step\n"));
    }

    void modelsAreStoppedUpdatedRemovedAndSwapped() {
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"ace", QJsonObject{{"kind", "music"}, {"name", "ACE"}, {"unit", "active"}, {"update", QJsonObject{{"image", true}}}}}}}}).toJson()));
        QVERIFY(write(dir.path() + "/list.json", R"([{"id":"ace","kind":"music","available":true,"installed":true},
                                                     {"id":"xl","kind":"music","name":"XL","available":true,"installed":false}])"));
        // What the running model holds now, as the engine measures it.
        QVERIFY(write(dir.path() + "/held", R"({"ace": 6.5})"));
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        QTRY_COMPARE(models.heldGib(), 6.5);
        QVERIFY(models.updatable());
        const auto asked = [&]() -> QString {
            QTest::qWaitFor([&] { return !models.working(); });
            QFile file(dir.path() + "/asked");
            return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()) : QString();
        };
        models.update();
        QCOMPARE(asked(), QString("update ace --detach\n"));
        models.stop();
        QCOMPARE(asked(), QString("update ace --detach\nstop ace\n"));
        models.remove();
        QCOMPARE(asked(), QString("update ace --detach\nstop ace\nremove ace\n"));
        // Another music model makes room for itself, and is set up first.
        QFile::remove(dir.path() + "/asked");
        models.use("xl");
        QCOMPARE(asked(), QString("stop ace\nuse xl --detach\n"));
        QCOMPARE(QSettings().value("model").toString(), QString("xl"));
    }

    void aPairedHostsModelServes() {
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/status.json", "{\"models\":{}}"));
        QVERIFY(write(dir.path() + "/list.json", "[]"));
        const auto shared = [](const QString &host, bool paired) {
            return QJsonObject{{"kind", "music"}, {"name", "ACE-Step"}, {"host", host}, {"paired", paired}, {"offline", ""},
                               {"unit", "active"}, {"endpoint", "http://" + host + ":8443/local-ai/ace-step/v1"}};
        };
        QVERIFY(write(dir.path() + "/network.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"studio/ace-step", shared("studio", true)}, {"attic/ace-step", shared("attic", false)}}}}).toJson()));
        QVERIFY(QDir(dir.path()).mkpath("remotes"));
        QVERIFY(write(dir.path() + "/key", "mine\n"));
        QVERIFY(write(dir.path() + "/remotes/studio.key", "theirs\n"));
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        QCOMPARE(models.state(), QString("ready"));
        QCOMPARE(models.name(), QString("ACE-Step on studio"));
        QCOMPARE(models.origin(), QString("http://studio:8443/local-ai/ace-step"));
        QCOMPARE(models.key(), QByteArray("theirs"));
    }

    void aModelThatStopsMidFlowIsStartedAgain() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        engineWith(dir.path(), "active", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        flow.retryDelayMs = 50;
        flow.play("techno");
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty() && !flow.composing(), 10000);
        QTRY_COMPARE_WITH_TIMEOUT(server.count("POST /synth"), 3, 10000);
        QTRY_VERIFY(!flow.composing());

        // The model stops while the music plays on what's ready.
        engineWith(dir.path(), "inactive", server.origin());
        QTRY_COMPARE(models.state(), QString("installed"));
        flow.next();
        // It's asked to start again, with nothing said of it.
        QTRY_COMPARE(lines(dir.path() + "/asked"), 1);
        QVERIFY(flow.error().isEmpty());
        QVERIFY(!flow.track().isEmpty());
        engineWith(dir.path(), "active", server.origin());
        QTRY_COMPARE_WITH_TIMEOUT(server.count("POST /synth"), 4, 10000);
        QVERIFY(flow.error().isEmpty());
    }

    void aFlowKeepsTwoTunesAhead() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        engineWith(dir.path(), "active", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");

        flow.play("polka");
        QVERIFY(flow.genre().isEmpty());
        flow.play("jazz");
        QCOMPARE(flow.genre(), QString("jazz"));
        QVERIFY(flow.composing());
        QVERIFY(flow.track().isEmpty());

        // The first tune plays, and the two after it are made behind it.
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
        QCOMPARE(flow.number(), 1);
        QCOMPARE(flow.bpm(), 88);
        QCOMPARE(flow.key(), QString("C minor"));
        QCOMPARE(flow.wave().size(), Flow::waveBars);
        QVERIFY(QFile::exists(flow.track().toLocalFile()));
        // Named in two words of its genre, kept in the file.
        QCOMPARE(flow.title().split(' ').size(), 2);
        QCOMPARE(Flow::titleOf(flow.track().toLocalFile()), flow.title());
        QTRY_VERIFY_WITH_TIMEOUT(server.count("POST /synth") == 3 && !flow.composing(), 10000);
        // And no more than that until the music moves on.
        QTest::qWait(700);
        QCOMPARE(server.count("POST /lm"), 3);

        // Asked for as its genre, without a voice, at a tune's length; the
        // song the model wrote goes back to be rendered as it is.
        QVERIFY(server.bodies[server.requests.indexOf("POST /lm")].value("caption").toString().startsWith("smooth jazz"));
        QCOMPARE(server.bodies[server.requests.indexOf("POST /lm")].value("lyrics").toString(), QString("[Instrumental]"));
        QCOMPARE(server.bodies[server.requests.indexOf("POST /lm")].value("duration").toInt(), Flow::trackSeconds);
        QCOMPARE(server.bodies[server.requests.indexOf("POST /synth")].value("audio_codes").toString(), QString("1,2,3"));

        // On to the next, and another is made. Every tune stays, in the
        // genre's own folder.
        const QString first = flow.track().toLocalFile();
        QCOMPARE(QFileInfo(first).absolutePath(), dir.path() + "/music/Jazz");
        QVERIFY(QFileInfo(first).fileName().endsWith("-88bpm-C-minor-instrumental.mp3"));
        flow.next();
        QCOMPARE(flow.number(), 2);
        QVERIFY(flow.track().toLocalFile() != first);
        QVERIFY(QFile::exists(first));
        QTRY_COMPARE_WITH_TIMEOUT(server.count("POST /synth"), 4, 10000);
        QCOMPARE(QSettings().value("genre").toString(), QString("jazz"));
        QCOMPARE(flow.lastGenre(), QString("jazz"));
    }

    void aSkipPastTheLastTuneWaitsForTheNext() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        engineWith(dir.path(), "active", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        flow.play("lofi");
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
        server.held = true;
        QTRY_VERIFY_WITH_TIMEOUT(server.count("POST /lm") == 2 || !flow.composing(), 10000);
        flow.next();
        flow.next();
        QVERIFY(flow.track().isEmpty());
        QVERIFY(flow.error().isEmpty());
        server.held = false;
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
    }

    void anotherGenreDropsTheTuneBeingMade() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        server.held = true;
        engineWith(dir.path(), "active", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        flow.play("techno");
        QTRY_VERIFY_WITH_TIMEOUT(server.count("GET /job?id=1") > 0, 10000);

        flow.play("ambient");
        QTRY_COMPARE_WITH_TIMEOUT(server.count("POST /job?id=1&cancel=1"), 1, 10000);
        server.held = false;
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
        QCOMPARE(flow.genre(), QString("ambient"));
        QCOMPARE(flow.number(), 1);
        QVERIFY(server.bodies[server.requests.lastIndexOf("POST /lm")].value("caption").toString().startsWith("ambient"));

        // Stopping drops the tune being made.
        server.held = true;
        QTRY_VERIFY_WITH_TIMEOUT(flow.composing(), 10000);
        const int cancels = server.requests.filter("cancel=1").size();
        flow.stop();
        QVERIFY(flow.genre().isEmpty());
        QVERIFY(flow.track().isEmpty());
        QTRY_COMPARE_WITH_TIMEOUT(server.requests.filter("cancel=1").size(), cancels + 1, 10000);
    }

    void aTuneThatFailsStopsTheFlowUntilAskedAgain() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        server.broken = true;
        engineWith(dir.path(), "active", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        flow.retryDelayMs = 50;
        flow.play("dnb");
        QTRY_COMPARE_WITH_TIMEOUT(flow.error(), QString("The tune couldn't be made"), 10000);
        QVERIFY(!flow.composing());
        // Tried once more by itself, and then no more.
        QCOMPARE(server.count("POST /lm"), 2);
        QTest::qWait(700);
        QCOMPARE(server.count("POST /lm"), 2);
        // Neither job it gave up on is left with the model.
        QTRY_COMPARE(server.requests.filter("cancel=1").size(), 2);

        server.broken = false;
        flow.retry();
        QVERIFY(flow.error().isEmpty());
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
    }

    void aTuneThatCannotBePlayedIsPassedOver() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        engineWith(dir.path(), "active", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        flow.play("jazz");
        QTRY_VERIFY_WITH_TIMEOUT(server.count("POST /synth") == 3 && !flow.composing(), 10000);

        // One that can't be played gives way to the next, with nothing said.
        server.held = true;
        const QUrl first = flow.track();
        flow.playbackFailed("no such file");
        QVERIFY(flow.error().isEmpty());
        QVERIFY(!flow.track().isEmpty());
        QVERIFY(flow.track() != first);
        // Three in a row is the sound itself: the flow stops, and says why.
        flow.playbackFailed("no sound card");
        QVERIFY(flow.error().isEmpty());
        flow.playbackFailed("no sound card");
        QCOMPARE(flow.error(), QString("The tune couldn't be played: no sound card"));
        QVERIFY(flow.track().isEmpty());

        // A tune that was on its way arrives, and waits to be asked.
        server.held = false;
        QTRY_VERIFY_WITH_TIMEOUT(server.count("POST /synth") >= 4 && !flow.composing(), 10000);
        QTest::qWait(300);
        QVERIFY(flow.track().isEmpty());
        QVERIFY(!flow.error().isEmpty());
        flow.retry();
        QVERIFY(flow.error().isEmpty());
        QVERIFY(!flow.track().isEmpty());
    }

    void troubleBehindTheMusicWaitsUntilItRunsOut() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        engineWith(dir.path(), "active", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        flow.retryDelayMs = 50;
        flow.play("lofi");
        QTRY_VERIFY_WITH_TIMEOUT(server.count("POST /synth") == 3 && !flow.composing(), 10000);

        // The next tune fails, and fails again, while one plays: it's tried
        // again every so often, and the music is left alone.
        server.broken = true;
        flow.next();
        QTRY_VERIFY_WITH_TIMEOUT(server.count("POST /lm") >= 6, 10000);
        QVERIFY(flow.error().isEmpty());
        QVERIFY(!flow.track().isEmpty());

        // Once there's nothing left to play, it's said.
        flow.next();
        QVERIFY(flow.error().isEmpty());
        flow.next();
        QTRY_COMPARE_WITH_TIMEOUT(flow.error(), QString("The tune couldn't be made"), 10000);
        QVERIFY(flow.track().isEmpty());

        server.broken = false;
        flow.retry();
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
        QVERIFY(flow.error().isEmpty());
    }

    void aModelThatTakesItsStartAndStaysStoppedIsSaid() {
        QTemporaryDir dir;
        engineWith(dir.path(), "inactive", "http://127.0.0.1:9");
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        flow.startGraceMs = 200;
        flow.play("jazz");
        QTRY_COMPARE(lines(dir.path() + "/asked"), 1);
        QTRY_COMPARE_WITH_TIMEOUT(flow.error(), QString("ACE-Step 1.5 Turbo didn't start"), 10000);
        // Asking again starts it again.
        flow.retry();
        QVERIFY(flow.error().isEmpty());
        QTRY_COMPARE(lines(dir.path() + "/asked"), 2);
    }

    void aFileWithNoSoundInItIsPassedOver() {
        QTemporaryDir dir;
        engineWith(dir.path(), "inactive", "http://127.0.0.1:9");
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        QVERIFY(QDir().mkpath(flow.folder("jazz")));
        QVERIFY(write(flow.folder("jazz") + "/empty.mp3", ""));
        QVERIFY(write(flow.folder("jazz") + "/not music.mp3", "words, not sound"));
        // Anything in the genre's folder plays, whoever put it there. A file
        // not named as instrumental plays with the lyrics on.
        QVERIFY(write(flow.folder("jazz") + "/a song of my own.mp3", m_tone));

        flow.setLyrics(true);
        flow.play("jazz");
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
        QCOMPARE(QFileInfo(flow.track().toLocalFile()).fileName(), QString("a song of my own.mp3"));
        QCOMPARE(flow.number(), 1);
        QCOMPARE(flow.wave().size(), Flow::waveBars);
        // The other two never come up: the model is started for what's next.
        QTRY_VERIFY(QFile::exists(dir.path() + "/asked"));
        flow.next();
        QVERIFY(flow.track().isEmpty());
        QVERIFY(flow.error().isEmpty());
    }

    void aModelThatDoesNotAnswerIsSaid() {
        QTemporaryDir dir;
        // Nothing listens there.
        engineWith(dir.path(), "active", "http://127.0.0.1:9");
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        flow.retryDelayMs = 50;
        flow.play("jazz");
        QTRY_VERIFY_WITH_TIMEOUT(flow.error().startsWith("The music model didn't answer: "), 10000);
    }

    void aStoppedModelIsStartedForTheFlow() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        engineWith(dir.path(), "inactive", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        flow.play("classical");
        QTRY_VERIFY(QFile::exists(dir.path() + "/asked"));
        QTRY_VERIFY(!models.working());
        // Asked once, however often the engine's files change meanwhile.
        engineWith(dir.path(), "activating", server.origin());
        QTRY_COMPARE(models.state(), QString("starting"));
        QCOMPARE(lines(dir.path() + "/asked"), 1);
        QVERIFY(server.requests.isEmpty());

        engineWith(dir.path(), "active", server.origin());
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
    }

    void aGenresTunesFromBeforePlayFirst() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        // The model is set up but stopped: tunes from before need none.
        engineWith(dir.path(), "inactive", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        QCOMPARE(flow.folder("dnb"), dir.path() + "/music/Drum & Bass");
        QVERIFY(QDir().mkpath(flow.folder("dnb")));
        QVERIFY(QDir().mkpath(flow.folder("jazz")));
        const QStringList before{"20260101-100000-174bpm-F#-minor-instrumental.mp3", "20260101-100500-instrumental.mp3",
                                 "20260101-101000-170bpm-instrumental.mp3"};
        for (const QString &name : before)
            QVERIFY(write(flow.folder("dnb") + "/" + name, m_tone));
        QVERIFY(write(flow.folder("jazz") + "/20260101-100000.mp3", m_tone));
        // One has a name of its own.
        QVERIFY(write(flow.folder("dnb") + "/" + before[1], Flow::titled(m_tone, "Night Bus")));

        flow.play("dnb");
        QStringList played;
        for (int i = 0; i < 3; ++i) {
            QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
            const QString name = QFileInfo(flow.track().toLocalFile()).fileName();
            QCOMPARE(QFileInfo(flow.track().toLocalFile()).absolutePath(), flow.folder("dnb"));
            QCOMPARE(flow.wave().size(), Flow::waveBars);
            // Its tempo and key are read back from its name.
            QCOMPARE(flow.bpm(), name.contains("174") ? 174 : name.contains("170") ? 170 : 0);
            QCOMPARE(flow.key(), name.contains("174") ? QString("F# minor") : QString());
            // Those without a name are named for their file, the same every time.
            QRandomGenerator named(quint32(qHash(name, 0)));
            QCOMPARE(flow.title(), name == before[1] ? QString("Night Bus") : Genres::title("dnb", named));
            played << name;
            // None of them asked anything of the model.
            if (i == 0)
                QVERIFY(server.requests.isEmpty());
            flow.next();
        }
        played.sort();
        QCOMPARE(played, before);
        // Each played once and still there; then the model is started for new ones.
        QCOMPARE(QDir(flow.folder("dnb")).entryList({"*.mp3"}, QDir::Files).size(), 3);
        QTRY_VERIFY(QFile::exists(dir.path() + "/asked"));
        engineWith(dir.path(), "active", server.origin());
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
        QVERIFY(!before.contains(QFileInfo(flow.track().toLocalFile()).fileName()));
        QTRY_VERIFY_WITH_TIMEOUT(QDir(flow.folder("dnb")).entryList({"*.mp3"}, QDir::Files).size() >= 5, 10000);
    }

    void lyricsChangeWhatIsMadeAndPlayedFromTheNextTuneOn() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        engineWith(dir.path(), "active", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        {
            Flow flow(&models, dir.path() + "/music");
            QVERIFY(!flow.lyrics());
            QVERIFY(QDir().mkpath(flow.folder("jazz")));
            QVERIFY(write(flow.folder("jazz") + "/20260101-100000-90bpm.mp3", m_tone));
            flow.setProperty("language", "da");
            flow.play("jazz");
            // Music alone to begin with: the sung tune from before is left out.
            QTRY_VERIFY_WITH_TIMEOUT(server.count("POST /synth") == 3 && !flow.composing(), 10000);
            const QUrl playing = flow.track();
            QVERIFY(!Flow::sungOf(playing.fileName()));
            QCOMPARE(server.bodies[server.requests.indexOf("POST /lm")].value("lyrics").toString(), QString("[Instrumental]"));

            // With lyrics, the tune playing stays, and what's behind it is sung:
            // the one from before first, then ones the model writes words for.
            // The model doesn't always write words when asked: it's asked
            // again until it does, and only then is the tune rendered.
            server.shy = 2;
            flow.setLyrics(true);
            QCOMPARE(flow.track(), playing);
            QCOMPARE(flow.number(), 1);
            QTRY_VERIFY_WITH_TIMEOUT(server.count("POST /synth") == 4 && !flow.composing(), 10000);
            QCOMPARE(server.count("POST /lm"), 6);
            const QJsonObject asked = server.bodies[server.requests.lastIndexOf("POST /lm")];
            QCOMPARE(asked.value("lyrics").toString(), QString());
            QCOMPARE(asked.value("vocal_language").toString(), QString("da"));
            QVERIFY(asked.value("caption").toString().startsWith("vocal jazz song"));
            flow.next();
            QCOMPARE(flow.number(), 2);
            QCOMPARE(flow.track().fileName(), QString("20260101-100000-90bpm.mp3"));
            flow.next();
            QVERIFY(Flow::sungOf(flow.track().fileName()));
            // Named for its first line, as none comes back.
            QCOMPARE(flow.title(), QString("La la la"));
            QCOMPARE(Flow::titleOf(flow.track().toLocalFile()), QString("La la la"));
            QVERIFY(flow.error().isEmpty());
        }
        // And it's remembered.
        Flow later(&models, dir.path() + "/music");
        QVERIFY(later.lyrics());
    }

    void aTuneIsNamedForWhenItWasMadeAndHowItSounds() {
        const QDateTime when(QDate(2026, 11, 20), QTime(14, 5, 9));
        QCOMPARE(Flow::fileName(when, 88, "C minor", true), QString("20261120-140509-88bpm-C-minor.mp3"));
        QCOMPARE(Flow::fileName(when, 0, "", true), QString("20261120-140509.mp3"));
        QCOMPARE(Flow::fileName(when, 120, "F# major", true), QString("20261120-140509-120bpm-F#-major.mp3"));
        // Nothing of a key can leave its folder.
        QCOMPARE(Flow::fileName(when, 0, "../x", true), QString("20261120-140509--x.mp3"));
        QCOMPARE(Flow::bpmOf("20261120-140509-88bpm-C-minor.mp3"), 88);
        QCOMPARE(Flow::keyOf("20261120-140509-88bpm-C-minor.mp3"), QString("C minor"));
        QCOMPARE(Flow::keyOf("20261120-140509-88bpm-C-minor_2.mp3"), QString("C minor"));
        QCOMPARE(Flow::keyOf("20261120-140509-A-major.mp3"), QString("A major"));
        QCOMPARE(Flow::keyOf("20261120-140509-88bpm.mp3"), QString());
        // A tune nobody sings in says so at the end of its name.
        QCOMPARE(Flow::fileName(when, 88, "C minor"), QString("20261120-140509-88bpm-C-minor-instrumental.mp3"));
        QCOMPARE(Flow::fileName(when, 0, ""), QString("20261120-140509-instrumental.mp3"));
        QCOMPARE(Flow::bpmOf("20261120-140509-88bpm-C-minor-instrumental.mp3"), 88);
        QCOMPARE(Flow::keyOf("20261120-140509-88bpm-C-minor-instrumental.mp3"), QString("C minor"));
        QCOMPARE(Flow::keyOf("20261120-140509-88bpm-C-minor-instrumental_2.mp3"), QString("C minor"));
        QCOMPARE(Flow::keyOf("20261120-140509-88bpm-instrumental.mp3"), QString());
        QVERIFY(!Flow::sungOf("20261120-140509-88bpm-C-minor-instrumental.mp3"));
        QVERIFY(!Flow::sungOf("20261120-140509-instrumental_2.mp3"));
        QVERIFY(Flow::sungOf("20261120-140509-88bpm-C-minor.mp3"));
        QVERIFY(Flow::sungOf("a song of my own.mp3"));
        QCOMPARE(Flow::bpmOf("a song of my own.mp3"), 0);
        QCOMPARE(Flow::keyOf("a song of my own.mp3"), QString());
    }

    void aShapeIsHowLoudEachPartIs() {
        // Quiet for its first half, loud for its second.
        QByteArray samples;
        for (int i = 0; i < 9600; ++i) {
            const qint16 level = qToLittleEndian<qint16>(i < 4800 ? 100 : (i % 2 ? 10000 : -10000));
            samples.append(reinterpret_cast<const char *>(&level), 2);
        }
        const QVariantList shape = Flow::shapeOf(samples);
        QCOMPARE(shape.size(), Flow::waveBars);
        QCOMPARE(shape.last().toDouble(), 1.0);
        QVERIFY(qAbs(shape.first().toDouble() - 0.01) < 0.001);
        QVERIFY(Flow::shapeOf({}).isEmpty());
    }

    void aTuneIsNamedForItsHookOrItsGenre() {
        // The line sung most, the first among equals, without its punctuation.
        QCOMPARE(Flow::hookOf("[Verse]\nWalking home\nUnder the lights,\n[Chorus]\nUnder the lights!\nHold on"), QString("Under the lights"));
        QCOMPARE(Flow::hookOf("[Verse]\n\"Walking home\"\nUnder the lights"), QString("Walking home"));
        QCOMPARE(Flow::hookOf("[Instrumental]"), QString());
        QCOMPARE(Flow::hookOf("And the river carries everything we never said to the sea"), QString("And the river carries everything we"));
        QCOMPARE(Flow::hookOf(QString(50, QChar(0x6C34))), QString(40, QChar(0x6C34)));

        QRandomGenerator random(3);
        for (const Genre &genre : Genres::all()) {
            const QString title = Genres::title(genre.id, random);
            QVERIFY2(genre.moods.contains(title.section(' ', 0, 0)), qPrintable(title));
            QVERIFY2(genre.things.contains(title.section(' ', 1)), qPrintable(title));
        }
        QVERIFY(Genres::title("polka", random).isEmpty());
    }

    void aTunesNameIsKeptInItsTag() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/tune.mp3";
        // Written as ID3v2.4 ahead of the sound, any name at all.
        QVERIFY(write(path, Flow::titled(m_tone, "Smoky Corner")));
        QCOMPARE(Flow::titleOf(path), QString("Smoky Corner"));
        QVERIFY(write(path, Flow::titled(m_tone, "夜のバス")));
        QCOMPARE(Flow::titleOf(path), QString("夜のバス"));
        // A tag already there gives way, so there's one, and the sound is as it was.
        const QByteArray tagged = Flow::titled(Flow::titled(m_tone, "First"), "Second");
        QVERIFY(write(path, tagged));
        QCOMPARE(Flow::titleOf(path), QString("Second"));
        QCOMPARE(tagged.count("ID3"), Flow::titled(m_tone, "Second").count("ID3"));
        QVERIFY(tagged.endsWith(m_tone.mid(m_tone.startsWith("ID3") ? 10 + ((m_tone[6] & 0x7f) << 21 | (m_tone[7] & 0x7f) << 14
                                                                                | (m_tone[8] & 0x7f) << 7 | (m_tone[9] & 0x7f)) : 0)));
        // Other players write ID3v2.3, in UTF-16; a file without a tag has no name.
        QByteArray text("\x01\xff\xfe", 3);
        for (const QChar c : QString("Côte"))
            text += char(c.unicode() & 0xff) + QByteArray(1, char(c.unicode() >> 8));
        const QByteArray frame = "TIT2" + QByteArray(3, 0) + char(text.size()) + QByteArray(2, 0) + text;
        QVERIFY(write(path, "ID3" + QByteArray("\x03\x00\x00\x00\x00\x00", 6) + char(frame.size()) + frame + m_tone));
        QCOMPARE(Flow::titleOf(path), QString("Côte"));
        // ID3v2.4 may put a frame's length ahead of its text, and unsynchronise it.
        const QByteArray marked = "TIT2" + QByteArray(3, 0) + char(11) + QByteArray("\x00\x03", 2) + QByteArray(3, 0) + char(6)
                                  + QByteArray(1, 0) + QByteArray("\xff\x00", 2) + "Home";
        QVERIFY(write(path, "ID3" + QByteArray("\x04\x00\x00\x00\x00\x00", 6) + char(marked.size()) + marked + m_tone));
        QCOMPARE(Flow::titleOf(path), QString("\u00ffHome"));
        QVERIFY(write(path, "no tag here"));
        QCOMPARE(Flow::titleOf(path), QString());
        QCOMPARE(Flow::titleOf(dir.path() + "/gone.mp3"), QString());
    }

    void themeFallsBack() {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QColor("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QColor("black"));
        QVERIFY(!theme.light());
        QCOMPARE(theme.radius(), 0);
    }

    void themeReadsThePalette() {
        QTemporaryDir dir;
        QVERIFY(QDir(dir.path()).mkpath("theme"));
        QVERIFY(write(dir.path() + "/theme/colors.toml", "mode = \"light\"\n"
                                                         "theme_type = \"dark\"\n"
                                                         "accent = \"#112233\"\n"
                                                         "bg = #fafafa # paper\n"
                                                         "foreground = '#202020'\n"
                                                         "color1 = \"#aa0000\"\n"));

        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QColor("#112233"));
        QCOMPARE(theme.accentForeground(), QColor("white"));
        QCOMPARE(theme.background(), QColor("#fafafa"));
        QCOMPARE(theme.foreground(), QColor("#202020"));
        QCOMPARE(theme.colors().value("red").value<QColor>(), QColor("#aa0000"));
        QVERIFY(theme.light());
    }

    void themeAsksHyprlandAgainOnlyWhenItReloads() {
        // The fake Hyprland lives outside the theme directory, whose changes
        // the Theme also follows.
        QTemporaryDir dir, hypr;
        const QString command = fakeHyprctl(hypr.path());
        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":4}"));
        QLocalServer events;
        QVERIFY(events.listen(hypr.filePath("events.sock")));

        // Once on start, and once more when the event socket connects.
        Theme theme(dir.path(), nullptr, command, events.fullServerName());
        QTRY_VERIFY(events.hasPendingConnections());
        QLocalSocket *hyprland = events.nextPendingConnection();
        QTRY_COMPARE(lines(hypr.filePath("calls")), 2);
        QTRY_COMPARE(theme.radius(), 4);

        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":10}"));
        QTest::qWait(300);
        QCOMPARE(lines(hypr.filePath("calls")), 2);
        // Events arrive in pieces; only a whole configreloaded line counts.
        hyprland->write("activewindow>>kitty,~\nconfigrel");
        hyprland->flush();
        QTest::qWait(100);
        QCOMPARE(lines(hypr.filePath("calls")), 2);
        hyprland->write("oaded>>\n");
        QTRY_COMPARE(theme.radius(), 10);
        QCOMPARE(lines(hypr.filePath("calls")), 3);
    }

    void themeReachesHyprlandOnceItListens() {
        QTemporaryDir dir, hypr;
        const QString command = fakeHyprctl(hypr.path());
        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":4}"));
        Theme theme(dir.path(), nullptr, command, hypr.filePath("events.sock"));
        QTRY_COMPARE(theme.radius(), 4);

        QVERIFY(write(hypr.filePath("response.json"), "{\"int\":8}"));
        QLocalServer events;
        QVERIFY(events.listen(hypr.filePath("events.sock")));
        QTRY_VERIFY_WITH_TIMEOUT(events.hasPendingConnections(), 5000);
        QTRY_COMPARE(theme.radius(), 8);
    }

    void translatorFallsBackToEnglish() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Save").isNull());
    }

    void translatorFollowsTheLanguageFile() {
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/language", "pt-BR\n"));
        QVERIFY(write(dir.path() + "/pt.json", R"({"Save": "Guardar", "Open": "Abrir"})"));
        QVERIFY(write(dir.path() + "/pt-BR.json", R"({"Save": "Salvar"})"));

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("pt-BR"));
        QCOMPARE(translator.translate("Main", "Save"), QString("Salvar"));
        QCOMPARE(translator.translate("Main", "Open"), QString("Abrir"));
        QVERIFY(translator.translate("Main", "Quit").isNull());
    }

    void translatorSeesAFirstPick() {
        // Before the first pick there is no ~/.config/omarchy to watch.
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/da.json", R"({"Save": "Gem"})"));
        Translator translator(dir.path() + "/omarchy/language", dir.path());
        QVERIFY(QDir(dir.path()).mkpath("omarchy"));
        QVERIFY(write(dir.path() + "/omarchy/language", "da\n"));
        QTRY_COMPARE(translator.translate("Main", "Save"), QString("Gem"));
    }

    void translatorPicksPluralForms() {
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/language", "ru\n"));
        QVERIFY(write(dir.path() + "/en.json", R"({"%n clips": {"one": "%n clip", "other": "%n clips"},
                                                   "%n files": {"one": "%n file", "other": "%n files"}})"));
        QVERIFY(write(dir.path() + "/ru.json", R"({"%n clips": {"one": "%n клип", "few": "%n клипа", "many": "%n клипов", "other": "%n клипа"}})"));

        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 21), QString("%n клип"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 22), QString("%n клипа"));
        QCOMPARE(translator.translate("Main", "%n clips", nullptr, 25), QString("%n клипов"));
        // An untranslated counted string falls back to English, with English rules.
        QCOMPARE(translator.translate("Main", "%n files", nullptr, 21), QString("%n files"));
    }

    void englishCatalogListsEveryString() {
        // en.json is what translators work from: every text the sources
        // translate is in it, as itself or, when counted, as its English
        // plural forms, and nothing else is.
        const QString sources = QFileInfo(QFINDTESTDATA("../src/Main.qml")).absolutePath();
        QStringList problems;
        const QMap<QString, bool> used = translatables(sources, &problems);
        const QJsonObject english = readCatalog(sources + "/i18n/en.json");
        for (auto it = used.begin(); it != used.end(); ++it) {
            const QJsonValue value = english.value(it.key());
            if (value.isUndefined())
                problems << "missing from en.json: " + it.key();
            else if (it.value() && (value.toObject().keys() != QStringList{"one", "other"}
                                    || value.toObject().value("other").toString() != it.key()))
                problems << "counted, so needs its one and other forms: " + it.key();
            else if (!it.value() && value.toString() != it.key())
                problems << "should be itself: " + it.key();
        }
        for (const QString &key : english.keys())
            if (!used.contains(key))
                problems << "in en.json but no source translates it: " + key;
        QVERIFY2(problems.isEmpty(), qPrintable(problems.join('\n')));
    }

    void catalogsMatchTheEnglishOne() {
        // A catalog may lack a string (it shows in English meanwhile), but what
        // it has translates something in en.json, with the same placeholders,
        // and a counted string has every form its language uses.
        const QString folder = QFileInfo(QFINDTESTDATA("../src/i18n/en.json")).absolutePath();
        const QJsonObject english = readCatalog(folder + "/en.json");
        QStringList problems;
        for (const QFileInfo &file : QDir(folder).entryInfoList({"*.json"}, QDir::Files)) {
            const QString code = file.completeBaseName();
            const QJsonObject catalog = readCatalog(file.filePath());
            if (catalog.isEmpty())
                problems << code + ": not a JSON object, or empty";
            // Some languages reach a form only at a million ("many" in French).
            QSet<QString> categories{"other", Translator::pluralCategory(code, 1000000)};
            for (long long n = 0; n <= 1000; ++n)
                categories << Translator::pluralCategory(code, n);
            for (auto it = catalog.begin(); it != catalog.end(); ++it) {
                const QString where = code + ": " + it.key() + ": ";
                const QJsonValue source = english.value(it.key());
                if (source.isUndefined()) {
                    problems << where + "not in en.json";
                } else if (source.isString()) {
                    if (!it.value().isString() || it.value().toString().isEmpty())
                        problems << where + "needs a translation";
                    else if (placeholders(it.value().toString()) != placeholders(it.key()))
                        problems << where + "has other placeholders than the English";
                } else {
                    const QJsonObject forms = it.value().toObject();
                    const QStringList wanted = placeholders(source.toObject().value("other").toString());
                    for (const QString &category : categories)
                        if (forms.value(category).toString().isEmpty())
                            problems << where + "needs its " + category + " form";
                    // A form other than "other" may say its number in words.
                    for (auto form = forms.begin(); form != forms.end(); ++form) {
                        const QStringList has = placeholders(form.value().toString());
                        QStringList needed = wanted;
                        if (form.key() != "other")
                            needed.removeIf([&](const QString &p) { return p.endsWith('n') && !has.contains(p); });
                        if (has != needed)
                            problems << where + form.key() + " has other placeholders than the English";
                    }
                }
            }
        }
        QVERIFY2(problems.isEmpty(), qPrintable(problems.join('\n')));
    }

    void windowPicksAGenreAndPlaysIt() {
        // A temp language and theme, so the test never depends on the desktop's.
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        FakeServer server;
        server.sound = m_tone;
        engineWith(dir.path() + "/engine-state", "active", server.origin());
        Backend backend({dir.path() + "/engine-state", dir.path() + "/engine-state/key", fakeEngine(dir.path()), dir.path() + "/music", {}});

        QQmlApplicationEngine engine;
        QStringList warnings;
        connect(&engine, &QQmlEngine::warnings, this, [&](const QList<QQmlError> &errors) {
            for (const auto &error : errors)
                warnings << error.toString();
        });
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/Main.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));

        // Every genre has a tile with a name of its own.
        auto *picker = item(window->contentItem(), "picker");
        auto *playing = item(window->contentItem(), "playing");
        QVERIFY(picker->isVisible());
        QVERIFY(!playing->isVisible());
        QVERIFY(!item(window->contentItem(), "setup")->isVisible());
        const QVariantMap names = window->property("genreNames").toMap();
        for (const QString &id : backend.flow()->genres()) {
            QVERIFY2(item(picker, "genre-" + id), qPrintable(id));
            QVERIFY2(!names.value(id).toString().isEmpty(), qPrintable(id));
        }

        // The arrows move between them, and Enter plays the one they're on.
        QCOMPARE(window->property("chosen").toInt(), 0);
        QTest::keyClick(window, Qt::Key_Right);
        QTest::keyClick(window, Qt::Key_Down);
        QCOMPARE(window->property("chosen").toInt(), 5);
        QTest::keyClick(window, Qt::Key_Left);
        QTest::keyClick(window, Qt::Key_Up);
        QTest::keyClick(window, Qt::Key_Left);
        QCOMPARE(window->property("chosen").toInt(), 11);
        QTest::keyClick(window, Qt::Key_Right);
        QTest::keyClick(window, Qt::Key_Right);
        QTest::keyClick(window, Qt::Key_Return);
        QCOMPARE(backend.flow()->genre(), QString("ambient"));
        QVERIFY(playing->isVisible());
        QVERIFY(!picker->isVisible());
        QCOMPARE(item(playing, "genre")->property("text").toString(), QString("Ambient"));
        QCOMPARE(item(playing, "status")->property("text").toString(), QString("Composing your first tune…"));
        QVERIFY(item(playing, "wave")->property("forming").toBool());

        // The tune arrives, and plays.
        QTRY_VERIFY_WITH_TIMEOUT(!backend.flow()->track().isEmpty(), 10000);
        QTRY_COMPARE(item(playing, "detail")->property("text").toString(), backend.flow()->title() + "  ·  88 BPM  ·  C minor");
        QVERIFY(!item(playing, "wave")->property("forming").toBool());
        QTRY_VERIFY(item(playing, "status")->property("text").toString().contains(" / "));

        // Space pauses and plays; the caption reads on the accent.
        auto *playPause = item(playing, "playPause");
        QCOMPARE(playPause->property("text").toString(), QString("Pause"));
        QCOMPARE(playPause->property("ink").value<QColor>(), theme.accentForeground());
        QCOMPARE(playPause->property("glyph").toString(), QString("pause"));
        QTest::keyClick(window, Qt::Key_Space);
        QVERIFY(window->property("paused").toBool());
        QCOMPARE(playPause->property("text").toString(), QString("Play"));
        QTest::keyClick(window, Qt::Key_Space);
        QVERIFY(!window->property("paused").toBool());

        // The media keys do as Space and N do, and Previous starts the tune over.
        Mpris *mpris = backend.mpris();
        QCOMPARE(mpris->playbackStatus(), QString("Playing"));
        QCOMPARE(mpris->metadata().value("xesam:title").toString(), backend.flow()->title());
        QCOMPARE(mpris->metadata().value("xesam:album").toString(), QString("Ambient"));
        mpris->playPause();
        QVERIFY(window->property("paused").toBool());
        QCOMPARE(mpris->playbackStatus(), QString("Paused"));
        mpris->play();
        QVERIFY(!window->property("paused").toBool());
        QTRY_VERIFY(mpris->position() > 200);
        QSignalSpy seeked(mpris, &Mpris::seeked);
        mpris->previous();
        QTRY_VERIFY(mpris->position() < 200);
        QVERIFY(!seeked.isEmpty());
        // A seek meant for another tune is left alone.
        QSignalSpy seekAsked(mpris, &Mpris::seekAsked);
        mpris->seekTo("/org/flowtunes/tune/99", 500000);
        QCOMPARE(seekAsked.size(), 0);
        // And so is one past its end.
        mpris->seekTo(mpris->tuneId(), mpris->duration() * 1000 + 1);
        QCOMPARE(seekAsked.size(), 0);
        mpris->seekTo(mpris->tuneId(), 500000);
        QCOMPARE(seekAsked.size(), 1);
        // Stop goes back to the start and waits there for Play.
        mpris->stop();
        QCOMPARE(mpris->playbackStatus(), QString("Stopped"));
        QVERIFY(window->property("paused").toBool());
        QTRY_VERIFY(mpris->position() < 200);
        mpris->play();
        QCOMPARE(mpris->playbackStatus(), QString("Playing"));
        const int playingNumber = backend.flow()->number();
        mpris->next();
        QVERIFY(backend.flow()->number() > playingNumber || backend.flow()->track().isEmpty());

        // L turns the lyrics on and off, as the switch under the genre shows.
        auto *lyrics = item(playing, "lyrics");
        QVERIFY(!lyrics->property("checked").toBool());
        QTest::keyClick(window, Qt::Key_L);
        QVERIFY(backend.flow()->lyrics());
        QVERIFY(lyrics->property("checked").toBool());
        QTest::keyClick(window, Qt::Key_L);
        QVERIFY(!backend.flow()->lyrics());

        // `flowtunes <genre>` asks for a genre to play from the start; here none was.
        QCOMPARE(window->property("picking").toBool(), false);

        // The one-second tune ends by itself, and the next one plays.
        QTRY_VERIFY_WITH_TIMEOUT(backend.flow()->number() >= 2, 15000);
        // And that one plays to its end too: the music flows on by itself.
        QTRY_VERIFY_WITH_TIMEOUT(backend.flow()->number() >= 4, 15000);
        // N skips on.
        const int before = backend.flow()->number();
        QTRY_VERIFY_WITH_TIMEOUT(!backend.flow()->track().isEmpty(), 10000);
        QTest::keyClick(window, Qt::Key_N);
        QVERIFY(backend.flow()->number() > before || backend.flow()->track().isEmpty());

        // Escape shows the genres while the music goes on, and goes back.
        QTest::keyClick(window, Qt::Key_Escape);
        QVERIFY(picker->isVisible());
        QCOMPARE(backend.flow()->genre(), QString("ambient"));
        QTest::keyClick(window, Qt::Key_Escape);
        QVERIFY(playing->isVisible());
        QTest::keyClick(window, Qt::Key_G);
        QVERIFY(picker->isVisible());
        // A click on another genre plays that one.
        auto *jazz = item(picker, "genre-jazz");
        QTest::mouseClick(window, Qt::LeftButton, {}, jazz->mapToScene(QPointF(jazz->width() / 2, jazz->height() / 2)).toPoint());
        QTRY_COMPARE(backend.flow()->genre(), QString("jazz"));
        QVERIFY(playing->isVisible());

        auto *help = window->findChild<QObject *>("help");
        QTest::keyClick(window, '?');
        QTRY_VERIFY(help->property("opened").toBool());
        // A Material popup animates out: `opened` drops at once, `visible` after.
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(!help->property("visible").toBool());
        QVERIFY(playing->isVisible());

        // Closing the window ends the flow.
        window->close();
        QVERIFY(backend.flow()->genre().isEmpty());

        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }

    void mprisAnswersOnTheSessionBus() {
        if (!QDBusConnection::sessionBus().isConnected())
            QSKIP("No session bus");
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        engineWith(dir.path(), "active", server.origin());
        Models models(dir.path(), dir.path() + "/key", fakeEngine(dir.path()));
        Flow flow(&models, dir.path() + "/music");
        Mpris mpris(&flow);
        const QString name = QString("flowtunes_test%1").arg(QCoreApplication::applicationPid());
        QVERIFY(mpris.publish(name));
        const QString service = "org.mpris.MediaPlayer2." + name;
        QDBusInterface root(service, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2");
        QDBusInterface player(service, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player");
        QCOMPARE(root.property("Identity").toString(), QString("Flowtunes"));
        QCOMPARE(root.property("DesktopEntry").toString(), QString("flowtunes"));
        QCOMPARE(player.property("PlaybackStatus").toString(), QString("Stopped"));
        QVERIFY(!player.property("CanGoNext").toBool());

        // Play with nothing playing asks the window to play.
        QSignalSpy asked(&mpris, &Mpris::pauseAsked);
        QVERIFY(player.call("PlayPause").type() != QDBusMessage::ErrorMessage);
        QTRY_COMPARE(asked.size(), 1);
        QCOMPARE(asked.first().first().toBool(), false);

        flow.play("jazz");
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
        QTRY_COMPARE(player.property("PlaybackStatus").toString(), QString("Playing"));
        QVERIFY(player.property("CanGoNext").toBool());
        mpris.setDuration(1000);
        QDBusInterface properties(service, "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties");
        const QDBusReply<QDBusVariant> metadata = properties.call("Get", "org.mpris.MediaPlayer2.Player", "Metadata");
        QVERIFY(metadata.isValid());
        QVariantMap tune;
        metadata.value().variant().value<QDBusArgument>() >> tune;
        QCOMPARE(tune.value("xesam:title").toString(), flow.title());
        QCOMPARE(tune.value("mpris:length").toLongLong(), 1000000);

        // Next skips on; Pause asks the window to pause.
        QTRY_VERIFY_WITH_TIMEOUT(server.count("POST /synth") >= 2 && !flow.composing(), 10000);
        const QString firstId = tune.value("mpris:trackid").value<QDBusObjectPath>().path();
        player.call("Next");
        QTRY_COMPARE(flow.number(), 2);
        // A tune's ID is its own, even after the genre starts over from tune 1.
        QVERIFY(mpris.tuneId() != firstId);
        flow.play("lofi");
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
        QCOMPARE(flow.number(), 1);
        QVERIFY(mpris.tuneId() != firstId);
        player.call("Pause");
        QTRY_COMPARE(asked.size(), 2);
        QCOMPARE(asked.last().first().toBool(), true);
        flow.stop();
    }

    void windowSaysWhatHoldsTheMemoryAndMakesRoom() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        const QString state = dir.path() + "/engine-state";
        QDir().mkpath(state);
        const auto running = [](const QString &kind, const QString &name, double gib) {
            return QJsonObject{{"kind", kind}, {"name", name}, {"unit", "active"}, {"observed", QJsonObject{{"ram_used_gib", gib}}}};
        };
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"ace", QJsonObject{{"kind", "music"}, {"name", "ACE-Step"}, {"unit", "inactive"}, {"endpoint", "http://127.0.0.1:9/v1"}}},
            {"qwen", running("text", "Qwen", 40)}, {"flux", running("image", "FLUX", 11)}}}}).toJson());
        write(state + "/list.json", R"([{"id":"ace","kind":"music","available":true,"installed":true,"memory_gib":8,"download_gib":7.5}])");
        write(dir.path() + "/meminfo", "MemTotal: 67108864 kB\nMemAvailable: 3145728 kB\n");
        Backend backend({state, state + "/key", fakeEngine(dir.path()), dir.path() + "/music", dir.path() + "/meminfo"});

        QQmlApplicationEngine engine;
        QStringList warnings;
        connect(&engine, &QQmlEngine::warnings, this, [&](const QList<QQmlError> &errors) {
            for (const auto &error : errors)
                warnings << error.toString();
        });
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/Main.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(QTest::qWaitForWindowExposed(window));
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));

        // Playing says what the model needs, what's free and who has the rest,
        // and offers to stop the one that's enough.
        QTest::keyClick(window, Qt::Key_Space);
        QCOMPARE(backend.models()->state(), QString("blocked"));
        QCOMPARE(item(window->contentItem(), "status")->property("text").toString(),
                 QString("ACE-Step needs 8 GB of memory to play, and 3 GB is free."));
        QCOMPARE(item(window->contentItem(), "holders")->property("text").toString(), QString("Running now: Qwen (40 GB), FLUX (11 GB)"));
        auto *retry = item(window->contentItem(), "retry");
        QCOMPARE(retry->property("text").toString(), QString("Stop FLUX and play"));
        QVERIFY(!QFile::exists(dir.path() + "/asked"));
        QTest::mouseClick(window, Qt::LeftButton, {}, retry->mapToScene(QPointF(retry->width() / 2, retry->height() / 2)).toPoint());
        QTRY_VERIFY(!backend.models()->working());
        QFile asked(dir.path() + "/asked");
        QVERIFY(asked.open(QIODevice::ReadOnly));
        QCOMPARE(asked.readAll(), QByteArray("stop flux\nstart ace\n"));
        asked.close();

        // The sheet removes the model only once asked twice, and stops the music first.
        QTest::keyClick(window, Qt::Key_M);
        auto *sheet = window->findChild<QObject *>("sheet");
        QTRY_VERIFY(sheet->property("opened").toBool());
        QTest::keyClick(window, Qt::Key_Delete);
        QVERIFY(sheet->property("removing").toBool());
        QTest::keyClick(window, Qt::Key_Return);
        QTRY_VERIFY(!backend.models()->working());
        QVERIFY(asked.open(QIODevice::ReadOnly));
        QVERIFY(asked.readAll().endsWith("remove ace\n"));
        QVERIFY(backend.flow()->genre().isEmpty());

        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }

    void windowOffersToSetUpAModel() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        const QString state = dir.path() + "/engine-state";
        QDir().mkpath(state);
        write(state + "/status.json", "{\"models\":{}}");
        write(state + "/list.json", R"([{"id":"ace-step","kind":"music","name":"ACE-Step 1.5 Turbo","available":true}])");
        Backend backend({state, state + "/key", fakeEngine(dir.path()), dir.path() + "/music", {}});
        // As `flowtunes jazz` starts it.
        backend.setInitialGenre("jazz");

        QQmlApplicationEngine engine;
        QStringList warnings;
        connect(&engine, &QQmlEngine::warnings, this, [&](const QList<QQmlError> &errors) {
            for (const auto &error : errors)
                warnings << error.toString();
        });
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/Main.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(QTest::qWaitForWindowExposed(window));
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));

        QVERIFY(item(window->contentItem(), "setup")->isVisible());
        QVERIFY(!item(window->contentItem(), "picker")->isVisible());
        // No genre plays without a model, whatever the keyboard says.
        QTest::keyClick(window, Qt::Key_Return);
        QVERIFY(backend.flow()->genre().isEmpty());

        auto *setUp = item(window->contentItem(), "setUp");
        QVERIFY(setUp->isVisible());
        QTest::mouseClick(window, Qt::LeftButton, {}, setUp->mapToScene(QPointF(setUp->width() / 2, setUp->height() / 2)).toPoint());
        QTRY_VERIFY(QFile::exists(dir.path() + "/asked"));
        QFile asked(dir.path() + "/asked");
        QVERIFY(asked.open(QIODevice::ReadOnly));
        QCOMPARE(asked.readAll(), QByteArray("use ace-step --detach\n"));

        // Once it's set up and running, the genre asked for from the start plays.
        engineWith(state, "active", "http://127.0.0.1:9");
        QTRY_COMPARE(backend.flow()->genre(), QString("jazz"));
        QVERIFY(item(window->contentItem(), "playing")->isVisible());
        QVERIFY(!item(window->contentItem(), "picker")->isVisible());

        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }

    void logoIsTheVendorsMarkFromOmarchy() {
        QTemporaryDir dir;
        const QString assets = dir.path() + "/shell/plugins/agents/assets/";
        QDir().mkpath(assets);
        for (const char *name : {"ace-step.svg", "ace-step-light.svg", "stability.svg", "local.svg"})
            write(assets + name, "<svg/>");
        const QByteArray saved = qgetenv("OMARCHY_PATH");
        const auto restore = qScopeGuard([&] {
            if (saved.isEmpty())
                qunsetenv("OMARCHY_PATH");
            else
                qputenv("OMARCHY_PATH", saved);
        });
        qputenv("OMARCHY_PATH", dir.path().toUtf8());
        QCOMPARE(Models::logo("ace-step", true), QUrl::fromLocalFile(assets + "ace-step-light.svg").toString());
        QCOMPARE(Models::logo("stability", true), QUrl::fromLocalFile(assets + "stability.svg").toString());
        QCOMPARE(Models::logo("unknown", false), QUrl::fromLocalFile(assets + "local.svg").toString());
        QCOMPARE(Models::logo("../stability", false), QUrl::fromLocalFile(assets + "local.svg").toString());
        qunsetenv("OMARCHY_PATH");
        QCOMPARE(Models::logo("stability", false), QString());
    }

    void anInstrumentalMusicModelRendersDirectlyAndHidesLyrics() {
        QTemporaryDir dir;
        FakeServer server;
        server.sound = m_tone;
        const QString state = dir.path() + "/engine-state";
        QDir().mkpath(state);
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{{"sa3", QJsonObject{
            {"kind", "music"}, {"vocals", false}, {"vendor", "stability"}, {"name", "Stable Audio 3 Medium"},
            {"unit", "active"}, {"endpoint", server.origin() + "/v1"}}}}}}).toJson());
        write(state + "/list.json", R"([{"id":"sa3","kind":"music","vocals":false,"vendor":"stability","name":"Stable Audio 3 Medium","available":true,"installed":true,"download_gib":2.56,"memory_gib":4}])");
        write(state + "/key", "secret\n");

        Models models(state, state + "/key", fakeEngine(dir.path()));
        QCOMPARE(models.vendor(), QString("stability"));
        QVERIFY(!models.vocals());

        // Even with lyrics saved on from a vocal model, an instrumental model plays only saved
        // instrumental tracks (skipping sung ones), renders new ones straight via /synth without
        // calling /lm, and never overwrites the user's saved lyrics preference.
        QSettings().setValue("lyrics", true);
        Flow flow(&models, dir.path() + "/music");
        QVERIFY(flow.lyrics());
        QVERIFY(QDir().mkpath(flow.folder("synthwave")));
        QVERIFY(write(flow.folder("synthwave") + "/20260101-100000-110bpm.mp3", m_tone));
        QVERIFY(write(flow.folder("synthwave") + "/20260101-100500-110bpm-instrumental.mp3", m_tone));
        flow.play("synthwave");
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
        QCOMPARE(QFileInfo(flow.track().toLocalFile()).fileName(), QString("20260101-100500-110bpm-instrumental.mp3"));
        QTRY_VERIFY_WITH_TIMEOUT(server.count("POST /synth") >= 1 && !flow.composing(), 10000);
        QCOMPARE(server.count("POST /lm"), 0);
        const QJsonObject body = server.bodies[server.requests.indexOf("POST /synth")];
        QVERIFY(body.value("caption").toString().endsWith(", instrumental"));
        QCOMPARE(body.value("duration").toInt(), Flow::trackSeconds);
        // Skipping past the saved instrumental tune plays the newly generated instrumental tune, never the sung one.
        flow.next();
        QTRY_VERIFY_WITH_TIMEOUT(!flow.track().isEmpty(), 10000);
        QVERIFY(!Flow::sungOf(flow.track().fileName()));
        QVERIFY(QFileInfo(flow.track().toLocalFile()).fileName() != QString("20260101-100000-110bpm.mp3"));
        QVERIFY(QSettings().value("lyrics").toBool());
        flow.stop();

        // The window hides the lyrics switch and ignores L for an instrumental-only model.
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        Backend backend({state, state + "/key", fakeEngine(dir.path()), dir.path() + "/music2", {}});
        QQmlApplicationEngine engine;
        QStringList warnings;
        connect(&engine, &QQmlEngine::warnings, this, [&](const QList<QQmlError> &errors) {
            for (const auto &error : errors)
                warnings << error.toString();
        });
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/Main.qml"));
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window && QTest::qWaitForWindowExposed(window));
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        QTest::keyClick(window, Qt::Key_Return);
        QTRY_VERIFY(item(window->contentItem(), "playing")->isVisible());
        QVERIFY(!item(window->contentItem(), "lyrics")->isVisible());
        const bool before = backend.flow()->lyrics();
        QTest::keyClick(window, Qt::Key_L);
        QCOMPARE(backend.flow()->lyrics(), before);
        window->close();
        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }

    void windowOffersMultipleMusicModelsOnFirstRun() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        const QString state = dir.path() + "/engine-state";
        QDir().mkpath(state);
        write(state + "/status.json", "{\"models\":{}}");
        write(state + "/list.json", R"([
            {"id":"ace-step","kind":"music","vocals":true,"vendor":"ace-step","name":"ACE-Step 1.5 Turbo","available":true,"best":true,"download_gib":7.57,"memory_gib":8},
            {"id":"sa3-medium","kind":"music","vocals":false,"vendor":"stability","name":"Stable Audio 3 Medium","available":true,"download_gib":2.56,"memory_gib":4}
        ])");
        Backend backend({state, state + "/key", fakeEngine(dir.path()), dir.path() + "/music", {}});
        QCOMPARE(backend.models()->offers().size(), 2);
        QCOMPARE(backend.models()->offers().first().toMap().value("id").toString(), QString("ace-step"));

        QQmlApplicationEngine engine;
        QStringList warnings;
        connect(&engine, &QQmlEngine::warnings, this, [&](const QList<QQmlError> &errors) {
            for (const auto &error : errors)
                warnings << error.toString();
        });
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/Main.qml"));
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window && QTest::qWaitForWindowExposed(window));
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));

        QVERIFY(item(window->contentItem(), "setup")->isVisible());
        QVERIFY(item(window->contentItem(), "offer-ace-step")->isVisible());
        QVERIFY(item(window->contentItem(), "offer-sa3-medium")->isVisible());
        QVERIFY(!item(window->contentItem(), "setUp")->isVisible());

        auto *sa3Button = item(window->contentItem(), "setUp-sa3-medium");
        QVERIFY(sa3Button && sa3Button->isVisible());
        QTest::mouseClick(window, Qt::LeftButton, {}, sa3Button->mapToScene(QPointF(sa3Button->width() / 2, sa3Button->height() / 2)).toPoint());
        QTRY_VERIFY(QFile::exists(dir.path() + "/asked"));
        QFile asked(dir.path() + "/asked");
        QVERIFY(asked.open(QIODevice::ReadOnly));
        QCOMPARE(asked.readAll(), QByteArray("use sa3-medium --detach\n"));
        QCOMPARE(QSettings().value("model").toString(), QString("sa3-medium"));

        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }

private:
    QByteArray m_tone;
};

QTEST_MAIN(FlowtunesTests)
#include "flowtunes_tests.moc"

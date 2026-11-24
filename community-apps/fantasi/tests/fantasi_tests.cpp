#include <QtEndian>
#include <QBuffer>
#include <QDir>
#include <QFile>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlProperty>
#include <QQmlContext>
#include <QSettings>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>
#include <algorithm>
#include <functional>
#include <memory>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"
#include "generator.h"
#include "history.h"
#include "instance.h"
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

// JSON written with ' for ", so moc, which doesn't understand raw literals,
// never meets one.
QByteArray q(const char *text) { return QByteArray(text).replace('\'', '"'); }
QJsonObject json(const QByteArray &text) { return QJsonDocument::fromJson(text).object(); }
QJsonArray jsonArray(const QByteArray &text) { return QJsonDocument::fromJson(text).array(); }

// A stand-in for stable-diffusion.cpp's server: answers each request with
// what `answer` returns for its method and path, and records the bodies.
class FakeServer : public QObject {
public:
    std::function<QPair<int, QByteArray>(const QString &, const QString &)> answer;
    QList<QPair<QString, QJsonObject>> requests;
    QTcpServer server;

    FakeServer() {
        server.listen(QHostAddress::LocalHost);
        connect(&server, &QTcpServer::newConnection, this, [this] {
            while (QTcpSocket *socket = server.nextPendingConnection()) {
                auto *buffer = new QByteArray;
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
                    requests << qMakePair(method + " " + path, QJsonDocument::fromJson(buffer->mid(end + 4, length)).object());
                    const auto [status, body] = answer(method, path);
                    socket->write("HTTP/1.1 " + QByteArray::number(status) + " X\r\nContent-Type: application/json\r\n"
                                  "Content-Length: " + QByteArray::number(body.size()) + "\r\nConnection: close\r\n\r\n" + body);
                    socket->disconnectFromHost();
                    delete buffer;
                });
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
            }
        });
    }
    QString origin() const { return QString("http://127.0.0.1:%1").arg(server.serverPort()); }
};

// An engine state folder with one image model ready at `origin`, and a key.
void readyEngine(const QString &folder, const QString &origin) {
    QDir().mkpath(folder);
    write(folder + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{{"z-image-turbo", QJsonObject{
        {"kind", "image"}, {"name", "Z-Image Turbo"}, {"unit", "active"}, {"endpoint", origin + "/v1"}}}}}}).toJson());
    write(folder + "/list.json", "[]");
    write(folder + "/key", "secret\n");
}

QByteArray png(int size = 8) {
    QImage image(size, size, QImage::Format_RGB32);
    image.fill(Qt::darkCyan);
    QByteArray bytes;
    QBuffer buffer(&bytes);
    buffer.open(QIODevice::WriteOnly);
    image.save(&buffer, "PNG");
    return bytes;
}

// A save dialog that answers with `answer` at once.
class FakePicker : public FilePicker {
public:
    QUrl answer;
    QUrl suggested;
    void openImage() override { emit openSelected(answer); }
    void saveImage(const QUrl &suggestedUrl) override {
        suggested = suggestedUrl;
        emit saveSelected(answer);
    }
};

} // namespace

class FantasiTests : public QObject {
    Q_OBJECT

private slots:
    void initTestCase() {
        QQuickStyle::setStyle("Material");
        // As main() does: hover, and so tooltips, whatever the platform says.
        qputenv("QT_QUICK_CONTROLS_HOVER_ENABLED", "1");
        // The model used last is remembered in settings; never the user's own.
        QStandardPaths::setTestModeEnabled(true);
        // As main() names the app, which is where its settings live.
        QCoreApplication::setOrganizationName("fantasi");
        QCoreApplication::setApplicationName("fantasi");
    }

    void discoveryWithoutTheEngine() {
        QCOMPARE(Models::discover({}, {}, false).state, QString("noEngine"));
    }

    void discoveryIgnoresTextModels() {
        // Rows without a kind are the text models the engine always had.
        const auto found = Models::discover(json(q("{'models': {'qwen': {'name': 'Qwen', 'unit': 'active'}}}")),
                                            jsonArray(q("[{'id': 'qwen', 'available': true}]")), true);
        QCOMPARE(found.state, QString("none"));
    }

    void discoveryUsesTheRunningModel() {
        const auto found = Models::discover(json(q("{'models': { 'a': {'kind': 'image', 'name': 'A', 'unit': 'active', 'endpoint': 'http://127.0.0.1:1/v1'}, 'b': {'kind': 'image', 'name': 'B', 'unit': 'active', 'endpoint': 'http://127.0.0.1:2/v1'}}}")), {}, true, "b");
        QCOMPARE(found.state, QString("ready"));
        QCOMPARE(found.id, QString("b"));
        // Both are choices, by name, whichever is in use.
        QCOMPARE(found.choices.size(), 2);
        QCOMPARE(found.choices.first().toMap().value("id").toString(), QString("a"));
    }

    void choosingARunningModelNeedsNoEngine() {
        QTemporaryDir dir;
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"k", QJsonObject{{"kind", "image"}, {"name", "K"}, {"unit", "active"}, {"endpoint", "http://127.0.0.1:2/v1"}}},
            {"z", QJsonObject{{"kind", "image"}, {"name", "Z"}, {"unit", "active"}, {"endpoint", "http://127.0.0.1:1/v1"}}}}}}).toJson());
        write(state + "/list.json", "[]");
        // An engine command that always fails: a switch must not need it.
        Models models(state, state + "/key", "/bin/false");
        const QString other = models.modelId() == "k" ? "z" : "k";
        models.choose(other);
        QCOMPARE(models.modelId(), other);
        QVERIFY(!models.working());
        QVERIFY(models.error().isEmpty());
    }

    void holdsTheModelInUseAndStopsTheMediaModelsOnQuit() {
        QTemporaryDir dir;
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/list.json", "[]");
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"z", QJsonObject{{"kind", "image"}, {"name", "Z"}, {"unit", "active"}, {"endpoint", "http://127.0.0.1:1/v1"}}},
            {"a", QJsonObject{{"kind", "music"}, {"name", "A"}, {"unit", "active"}, {"endpoint", "http://127.0.0.1:2/v1"}}},
            {"k", QJsonObject{{"kind", "image"}, {"name", "K"}, {"unit", "inactive"}}},
            {"qwen", QJsonObject{{"name", "Qwen"}, {"unit", "active"}}}}}}).toJson());
        const QString command = dir.path() + "/engine";
        // Its hold lasts until its input closes, as the engine's does.
        write(command, "#!/bin/bash\necho \"$@\" >> '" + dir.path().toUtf8() + "/asked'\n"
                       "[ \"$1\" = hold ] && cat > /dev/null && echo released >> '" + dir.path().toUtf8() + "/asked'\n");
        QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        QSettings().setValue("model", "z");
        const auto asked = [&] {
            QFile file(dir.path() + "/asked");
            return (file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray()).replace("refresh --quiet\n", "");
        };

        Models models(state, state + "/key", command);
        QTRY_VERIFY(asked().contains("hold z\n"));
        // Held for as long as the app runs, and let go before anything is stopped.
        QTest::qWait(200);
        QVERIFY(!asked().contains("released"));
        // The running media models, held elsewhere or not, but never a text model.
        models.release();
        QTRY_VERIFY(asked().endsWith("hold z\nreleased\nstop --unless-used a z\n"));
        QSettings().remove("model");
    }

    void choosingAModelStopsTheOneInUseOnlyForRoom() {
        QTemporaryDir dir;
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/list.json", "[]");
        // An engine that notes what it's asked to do.
        const QString command = dir.path() + "/engine";
        write(command, "#!/bin/bash\necho \"$@\" >> '" + dir.path().toUtf8() + "/asked'\n");
        QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        const auto asked = [&] {
            QFile file(dir.path() + "/asked");
            QByteArrayList lines = file.open(QIODevice::ReadOnly) ? file.readAll().split('\n') : QByteArrayList();
            lines.removeAll("");
            lines.removeAll("refresh --quiet");
            lines.removeIf([](const QByteArray &line) { return line.startsWith("hold "); });
            return lines;
        };
        const auto status = [&](bool fits) {
            write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
                {"k", QJsonObject{{"kind", "image"}, {"name", "K"}, {"unit", "inactive"}, {"fits", fits},
                                   {"fit_reason", fits ? "" : "Not enough memory"}}},
                {"z", QJsonObject{{"kind", "image"}, {"name", "Z"}, {"unit", "active"}, {"endpoint", "http://127.0.0.1:1/v1"}}}}}}).toJson());
        };

        // With room for both, the one in use keeps running.
        status(true);
        {
            Models models(state, state + "/key", command);
            QCOMPARE(models.modelId(), QString("z"));
            models.choose("k");
            QTRY_VERIFY(!models.working());
            QCOMPARE(asked(), QByteArrayList{"start k"});
        }
        // Without it, the one in use makes way first.
        QFile::remove(dir.path() + "/asked");
        QSettings().remove("model");
        status(false);
        {
            Models models(state, state + "/key", command);
            QCOMPARE(models.modelId(), QString("z"));
            models.choose("k");
            QTRY_VERIFY(!models.working());
            QCOMPARE(asked(), (QByteArrayList{"stop z", "start k"}));
        }
        QSettings().remove("model");
    }

    void choosingAModelSaysWhenTheEngineCantBeRun() {
        QTemporaryDir dir;
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/list.json", "[]");
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"k", QJsonObject{{"kind", "image"}, {"name", "K"}, {"unit", "inactive"}}},
            {"z", QJsonObject{{"kind", "image"}, {"name", "Z"}, {"unit", "active"}, {"endpoint", "http://127.0.0.1:1/v1"}}}}}}).toJson());
        Models models(state, state + "/key", dir.path() + "/gone");
        models.choose("k");
        // Not left waiting on a start that never began.
        QTRY_VERIFY(!models.error().isEmpty());
        QVERIFY(models.switchingTo().isEmpty());
        QVERIFY(!models.working());
        QCOMPARE(models.modelId(), QString("z"));
    }

    void theEngineIsOmarchyModelsOnThePath() {
        QTemporaryDir dir;
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        QDir().mkpath(dir.path() + "/bin");
        QDir().mkpath(dir.path() + "/empty");
        write(state + "/list.json", "[]");
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"k", QJsonObject{{"kind", "image"}, {"name", "K"}, {"unit", "inactive"}}},
            {"z", QJsonObject{{"kind", "image"}, {"name", "Z"}, {"unit", "active"}, {"endpoint", "http://127.0.0.1:1/v1"}}}}}}).toJson());
        // An omarchy-models that notes what it's asked to do.
        const QString command = dir.path() + "/bin/omarchy-models";
        write(command, "#!/bin/bash\necho \"$@\" >> '" + dir.path().toUtf8() + "/asked'\n");
        QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        const QByteArray path = qgetenv("PATH");
        const auto restore = qScopeGuard([&] { qputenv("PATH", path); QSettings().remove("model"); });

        // With none on the path, a start says so rather than doing nothing.
        qputenv("PATH", (dir.path() + "/empty").toUtf8());
        {
            Models models(state, state + "/key", {});
            models.choose("k");
            QVERIFY(!models.error().isEmpty());
            QVERIFY(models.switchingTo().isEmpty());
            QVERIFY(!models.working());
        }
        QVERIFY(!QFile::exists(dir.path() + "/asked"));

        // The one on the path is the one that's run.
        qputenv("PATH", (dir.path() + "/bin:" + path).toUtf8());
        {
            Models models(state, state + "/key", {});
            models.choose("k");
            QTRY_VERIFY(!models.working());
            QVERIFY(models.error().isEmpty());
            QFile asked(dir.path() + "/asked");
            QVERIFY(asked.open(QIODevice::ReadOnly));
            QVERIFY(asked.readAll().split('\n').contains("start k"));
        }
    }

    void discoveryOffersAPairedHostsSharedImageModels() {
        QTemporaryDir dir;
        const QString state = dir.path() + "/state";
        QDir().mkpath(state + "/remotes");
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"z", QJsonObject{{"kind", "image"}, {"name", "Z"}, {"unit", "active"}, {"endpoint", "http://127.0.0.1:1/v1"}}}}}}).toJson());
        write(state + "/list.json", "[]");
        write(state + "/key", "local-key\n");
        write(state + "/remotes/spark.key", "spark-key\n");
        auto shared = [](const QString &recipe, bool paired, const QString &offline) {
            return QJsonObject{{"kind", "image"}, {"edit", true}, {"name", "Klein"}, {"unit", "active"}, {"host", "spark"},
                               {"recipe", recipe}, {"paired", paired}, {"offline", offline},
                               {"endpoint", "https://spark.tail.ts.net/local-ai/" + recipe + "/v1"}};
        };
        write(state + "/network.json", QJsonDocument(QJsonObject{{"hosts", QJsonObject{}}, {"models", QJsonObject{
            {"spark/klein", shared("klein", true, "")},
            {"spark/away", shared("away", true, "spark isn't reachable")},
            {"spark/other", shared("other", false, "")}}}}).toJson());

        Models models(state, state + "/key", "/bin/false");
        // This machine's own first, then the paired host's running one.
        QCOMPARE(models.choices().size(), 2);
        QCOMPARE(models.choices().at(1).toMap().value("name").toString(), QString("Klein on spark"));
        QCOMPARE(models.modelId(), QString("z"));
        QCOMPARE(models.key(), QByteArray("local-key"));
        // A change goes to it, the one that edits, with its host's key.
        QCOMPARE(models.editOrigin(), QString("https://spark.tail.ts.net/local-ai/klein"));
        QCOMPARE(models.editKey(), QByteArray("spark-key"));
        models.choose("spark/klein");
        QCOMPARE(models.origin(), QString("https://spark.tail.ts.net/local-ai/klein"));
        QCOMPARE(models.key(), QByteArray("spark-key"));
    }

    void aLaterOpenHandsItsRequestToTheOpenWindow() {
        QTemporaryDir dir;
        const QString path = dir.path() + "/fantasi.sock";
        // Nothing open: the launch opens a window of its own.
        QVERIFY(!Instance(path).forward({{"model", "klein"}}));
        // A socket a crashed window left behind is taken over: the first launch
        // becomes the window, and the next hands over to it.
        write(path, "");
        Instance open(path);
        QVERIFY(!open.handOver({{"model", "klein"}}));
        QSignalSpy requested(&open, &Instance::requested);
        QVERIFY(Instance(path).handOver({{"model", "z-image"}, {"prompt", "a calm lake"}}));
        QTRY_COMPARE(requested.count(), 1);
        const QJsonObject request = requested.first().first().toJsonObject();
        QCOMPARE(request.value("model").toString(), QString("z-image"));
        QCOMPARE(request.value("prompt").toString(), QString("a calm lake"));
    }

    void logoIsTheVendorsMarkFromOmarchy() {
        QTemporaryDir dir;
        const QString assets = dir.path() + "/shell/plugins/agents/assets/";
        QDir().mkpath(assets);
        for (const char *name : {"bfl.svg", "bfl-light.svg", "alibaba.svg", "local.svg"})
            write(assets + name, "<svg/>");
        qputenv("OMARCHY_PATH", dir.path().toUtf8());
        QCOMPARE(Models::logo("bfl", true), QUrl::fromLocalFile(assets + "bfl-light.svg").toString());
        // No dark version: the mark itself; no mark: the local model's.
        QCOMPARE(Models::logo("alibaba", true), QUrl::fromLocalFile(assets + "alibaba.svg").toString());
        QCOMPARE(Models::logo("stability", false), QUrl::fromLocalFile(assets + "local.svg").toString());
        QCOMPARE(Models::logo("../bfl", false), QUrl::fromLocalFile(assets + "local.svg").toString());
        qunsetenv("OMARCHY_PATH");
        QCOMPARE(Models::logo("bfl", false), QString());
    }

    void discoveryFindsAnEditModelForChanges() {
        // Z-Image is the one in use, but a change goes to Klein, which edits.
        const auto found = Models::discover(json(q("{'models': { 'z': {'kind': 'image', 'name': 'Z', 'unit': 'active', 'endpoint': 'http://127.0.0.1:1/v1'}, 'k': {'kind': 'image', 'name': 'K', 'unit': 'active', 'edit': true, 'endpoint': 'http://127.0.0.1:2/v1'}}}")), {}, true, "z");
        QCOMPARE(found.id, QString("z"));
        QCOMPARE(found.editEndpoint, QString("http://127.0.0.1:2/v1"));
    }

    void discoveryOffersToStartAnInstalledModel() {
        const auto found = Models::discover(json(q("{'models': {'z': {'kind': 'image', 'name': 'Z', 'unit': 'inactive'}}}")), {}, true);
        QCOMPARE(found.state, QString("installed"));
        QCOMPARE(found.id, QString("z"));
    }

    void discoveryNamesTheTextModelInTheWay() {
        const auto found = Models::discover(json(q("{'models': { 'z': {'kind': 'image', 'name': 'Z', 'unit': 'inactive', 'fits': false, 'fit_reason': 'Not enough memory'}, 'qwen': {'name': 'Qwen3.8 27B', 'unit': 'active'}}}")), {}, true);
        QCOMPARE(found.state, QString("blocked"));
        QCOMPARE(found.blockers, QStringList{"Qwen3.8 27B"});
        QCOMPARE(found.blockerIds, QStringList{"qwen"});
    }

    void discoveryOffersNoModelThatCantFitThisMachine() {
        // MiniMax needs more GPU memory than this machine gives, which no
        // stopping of other models changes; Z only waits for room.
        const auto found = Models::discover(json(q("{'models': { 'k': {'kind': 'image', 'name': 'K', 'unit': 'active', 'endpoint': 'http://127.0.0.1:1/v1'}, 'minimax': {'kind': 'video', 'name': 'MiniMax', 'unit': 'inactive', 'fits': false, 'fit_reason': 'Reboot to raise the GPU memory limit'}, 'z': {'kind': 'image', 'name': 'Z', 'unit': 'inactive', 'fits': false, 'fit_reason': 'Not enough memory'}}}")), {}, true, "minimax");
        QCOMPARE(found.id, QString("k"));
        QStringList ids;
        for (const QVariant &choice : found.choices)
            ids << choice.toMap().value("id").toString();
        QCOMPARE(ids, (QStringList{"k", "z"}));
    }

    void discoveryOffersTheBestModelThatRunsHere() {
        const auto found = Models::discover({}, jsonArray(q("[ {'id': 'big', 'kind': 'image', 'name': 'Big', 'available': false, 'reason': 'needs 128 GB'}, {'id': 'ok', 'kind': 'image', 'name': 'Ok', 'available': true}, {'id': 'best', 'kind': 'image', 'name': 'Best', 'available': true, 'best': true}]")), true);
        QCOMPARE(found.state, QString("installable"));
        QCOMPARE(found.id, QString("best"));
    }

    void discoverySaysWhyNothingRunsHere() {
        const auto found = Models::discover({}, jsonArray(q("[ {'id': 'big', 'kind': 'image', 'available': false, 'reason': 'needs 128 GB'}]")), true);
        QCOMPARE(found.state, QString("none"));
        QCOMPARE(found.reason, QString("needs 128 GB"));
    }

    void discoveryReadsASetupInProgressAndOffersItNoChoiceYet() {
        auto found = Models::discover(json(q("{'models': {'z': {'kind': 'image', 'name': 'Z', 'unit': 'installing', 'since_ms': 1000, 'expected_load_seconds': 4, 'error': '', 'install': {'phase': 'downloading', 'done_bytes': 300, 'total_bytes': 1000, 'rate_bytes_s': 50}}}}")), {}, true);
        QCOMPARE(found.state, QString("installing"));
        QCOMPARE(found.setupPhase, QString("downloading"));
        QCOMPARE(found.doneBytes, 300);
        QCOMPARE(found.totalBytes, 1000);
        QCOMPARE(found.rateBytes, 50);
        QCOMPARE(found.loadSeconds, 4.0);
        // Still downloading, it's nothing to pick.
        QVERIFY(found.choices.isEmpty());

        found = Models::discover(json(q("{'models': {'z': {'kind': 'image', 'name': 'Z', 'unit': 'installing', 'error': 'The download stopped', 'install': {'phase': 'failed'}}}}")), {}, true);
        QCOMPARE(found.setupPhase, QString("failed"));
        QCOMPARE(found.reason, QString("The download stopped"));
    }

    void theLibraryListsEveryMediaModelAndWhatItTakes() {
        Models::Memory memory;
        memory.total = 62;
        memory.free = 20;
        memory.held = {{"qwen", 40}, {"z", 9}};
        QStringList order;
        const QVariantMap library = Models::libraryFrom(
            json(q("{'models': {"
                   "'qwen': {'kind': 'text', 'name': 'Qwen3.8 27B', 'unit': 'active'},"
                   "'z': {'kind': 'image', 'name': 'Z', 'unit': 'active', 'update': {'weights': true, 'download_bytes': 1000}},"
                   "'m': {'kind': 'video', 'name': 'M', 'unit': 'inactive', 'fits': false},"
                   "'a': {'kind': 'music', 'name': 'A', 'unit': 'installing', 'error': '', 'install': {'phase': 'downloading', 'done_bytes': 3, 'total_bytes': 8}}}}")),
            jsonArray(q("[ {'id': 'qwen', 'kind': 'text', 'available': true, 'memory_gib': 42},"
                        "{'id': 'z', 'kind': 'image', 'name': 'Z', 'available': true, 'memory_gib': 14, 'download_gib': 10},"
                        "{'id': 'z-cuda', 'kind': 'image', 'name': 'Z', 'available': false, 'reason': 'runtime sdcpp-cuda cannot run here'},"
                        "{'id': 'k', 'kind': 'image', 'name': 'K', 'available': true, 'best': true, 'memory_gib': 70, 'download_gib': 8},"
                        "{'id': 'm', 'kind': 'video', 'name': 'M', 'available': true, 'memory_gib': 26},"
                        "{'id': 'w', 'kind': 'video', 'name': 'W', 'available': false, 'reason': 'needs 89 GiB'},"
                        "{'id': 'a', 'kind': 'music', 'name': 'A', 'available': true, 'memory_gib': 8}]")),
            memory, "z", &order);

        // Images, video, music, then what isn't for this machine: no text
        // models, and a variant for other graphics hides behind the one here.
        QCOMPARE(order, (QStringList{"z", "k", "m", "a", "w"}));
        QCOMPARE(library["z"].toMap()["state"], QVariant("running"));
        QCOMPARE(library["z"].toMap()["held"], QVariant(9.0));
        QVERIFY(library["z"].toMap()["inUse"].toBool());
        QVERIFY(library["z"].toMap()["update"].toBool());
        QCOMPARE(library["k"].toMap()["state"], QVariant("offer"));
        QCOMPARE(library["a"].toMap()["state"], QVariant("installing"));
        QCOMPARE(library["a"].toMap()["doneBytes"], QVariant(qint64(3)));
        QCOMPARE(library["w"].toMap()["state"], QVariant("unavailable"));
        QCOMPARE(library["w"].toMap()["reason"], QVariant("needs 89 GiB"));

        // M needs 6 GB more than is free: Z alone makes room, rather than the
        // coding model and its 40.
        const QVariantMap video = library["m"].toMap();
        QVERIFY(!video["fits"].toBool());
        QCOMPARE(video["room"].toList().size(), 1);
        QCOMPARE(video["room"].toList()[0].toMap()["name"], QVariant("Z"));
        QCOMPARE(video["shortBy"], QVariant(0.0));
        // K needs 50 more: both go, the biggest first, and it's still 1 short.
        const QVariantMap big = library["k"].toMap();
        QCOMPARE(big["room"].toList().size(), 2);
        QCOMPARE(big["room"].toList()[0].toMap()["name"], QVariant("Qwen3.8 27B"));
        QCOMPARE(big["shortBy"], QVariant(1.0));
    }

    void startingAModelStopsWhatsInItsWayFirst() {
        QTemporaryDir dir;
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/status.json", q("{'models': {"
                                        "'qwen': {'kind': 'text', 'name': 'Qwen3.8 27B', 'unit': 'active'},"
                                        "'z': {'kind': 'image', 'name': 'Z', 'unit': 'inactive', 'fits': false, 'fit_reason': 'Not enough memory'}}}"));
        write(state + "/list.json", q("[ {'id': 'qwen', 'kind': 'text', 'available': true, 'memory_gib': 40},"
                                      "{'id': 'z', 'kind': 'image', 'name': 'Z', 'available': true, 'memory_gib': 14}]"));
        // 10 GiB free of 64.
        write(dir.path() + "/meminfo", "MemTotal:       67108864 kB\nMemAvailable:    9437184 kB\nGPUReclaim:     1048576 kB\n");
        // An engine that notes what it's asked to do.
        const QString command = dir.path() + "/engine";
        write(command, "#!/bin/bash\necho \"$@\" >> '" + dir.path().toUtf8() + "/asked'\n");
        QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        const auto asked = [&] {
            QFile file(dir.path() + "/asked");
            QByteArrayList lines = file.open(QIODevice::ReadOnly) ? file.readAll().split('\n') : QByteArrayList();
            lines.removeAll("");
            lines.removeAll("refresh --quiet");
            lines.removeIf([](const QByteArray &line) { return line.startsWith("hold "); });
            return lines;
        };

        Models models(state, state + "/key", command);
        models.setMeminfoPath(dir.path() + "/meminfo");
        QCOMPARE(models.memoryTotal(), 64.0);
        QCOMPARE(models.memoryFree(), 10.0);
        QCOMPARE(models.blockers(), QStringList{"Qwen3.8 27B"});
        models.startModel("z");
        QTRY_VERIFY(!models.working());
        QCOMPARE(asked(), (QByteArrayList{"stop qwen", "start z"}));

        // With room to spare, it simply starts.
        QFile::remove(dir.path() + "/asked");
        write(dir.path() + "/meminfo", "MemTotal:       67108864 kB\nMemAvailable:   31457280 kB\n");
        models.readMemory();
        models.startModel("z");
        QTRY_VERIFY(!models.working());
        QCOMPARE(asked(), QByteArrayList{"start z"});
        QSettings().remove("model");
    }

    void aFirstRunOffersWhatFitsAndLastsUntilTheFirstPrompt() {
        QTemporaryDir dir;
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        // Images and music fit this machine; video doesn't.
        write(state + "/list.json", QJsonDocument(QJsonArray{
            QJsonObject{{"id", "klein"}, {"kind", "image"}, {"name", "FLUX.2 Klein 4B"}, {"vendor", "bfl"}, {"available", true}, {"best", true}, {"memory_gib", 11}, {"download_gib", 8.3}},
            QJsonObject{{"id", "ace"}, {"kind", "music"}, {"name", "ACE-Step"}, {"vendor", "ace-step"}, {"available", true}, {"memory_gib", 8}, {"download_gib", 7.57}},
            QJsonObject{{"id", "h3"}, {"kind", "video"}, {"name", "MiniMax H3"}, {"available", false}, {"memory_gib", 38}, {"download_gib", 22.64}}}).toJson());
        const auto status = [&](const QJsonObject &models) {
            write(state + "/status.json", QJsonDocument(QJsonObject{{"models", models}}).toJson());
        };
        // The engine command, recording what it's asked.
        const QString command = dir.path() + "/engine";
        write(command, QString("#!/bin/sh\necho \"$@\" >> %1/asked\n").arg(dir.path()).toUtf8());
        QFile(command).setPermissions(QFile::ExeOwner | QFile::ReadOwner);
        status({});

        Models models(state, state + "/key", command);
        QVERIFY(models.settingUp());
        QCOMPARE(models.offers().size(), 2);
        const QVariantMap image = models.offers().at(0).toMap();
        QCOMPARE(image.value("kind").toString(), QString("image"));
        QCOMPARE(image.value("phase").toString(), QString("offer"));
        QCOMPARE(image.value("downloadBytes").toLongLong(), qint64(8.3 * 1024 * 1024 * 1024));
        QCOMPARE(models.offers().at(1).toMap().value("kind").toString(), QString("music"));

        // Only an offer downloads, through the engine.
        models.download("h3");
        models.download("klein");
        QTRY_VERIFY(QFile::exists(dir.path() + "/asked"));
        QFile asked(dir.path() + "/asked");
        QVERIFY(asked.open(QIODevice::ReadOnly));
        const QByteArray said = asked.readAll();
        QVERIFY(said.contains("use klein --detach"));
        QVERIFY(!said.contains("h3"));

        // Its download, then ready: the first run carries on until the first prompt.
        status({{"klein", QJsonObject{{"kind", "image"}, {"unit", "installing"},
                                      {"install", QJsonObject{{"phase", "downloading"}, {"done_bytes", 100}, {"total_bytes", 400}}}}}});
        QTRY_COMPARE(models.offers().at(0).toMap().value("phase").toString(), QString("downloading"));
        QCOMPARE(models.offers().at(0).toMap().value("doneBytes").toLongLong(), 100);
        status({{"klein", QJsonObject{{"kind", "image"}, {"name", "FLUX.2 Klein 4B"}, {"unit", "active"}, {"endpoint", "http://127.0.0.1:1/v1"}}}});
        QTRY_COMPARE(models.state(), QString("ready"));
        QCOMPARE(models.offers().at(0).toMap().value("phase").toString(), QString("ready"));
        QVERIFY(models.settingUp());
        // Stopped before the first prompt, it's set up and can be started again.
        status({{"klein", QJsonObject{{"kind", "image"}, {"name", "FLUX.2 Klein 4B"}, {"unit", "inactive"}}}});
        QTRY_COMPARE(models.offers().at(0).toMap().value("phase").toString(), QString("installed"));
        QVERIFY(models.settingUp());
        models.endSetup();
        QVERIFY(!models.settingUp());

        // Opened with something set up, it's no first run.
        Models later(state, state + "/key", command);
        QVERIFY(!later.settingUp());
    }

    void modelsFollowTheEngineFiles() {
        QTemporaryDir dir;
        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        QCOMPARE(models.state(), QString("none"));
        // The engine writes its files whole, after the app has started.
        readyEngine(dir.path() + "/state", "http://127.0.0.1:4321");
        QTRY_COMPARE(models.state(), QString("ready"));
        QCOMPARE(models.origin(), QString("http://127.0.0.1:4321"));
        QCOMPARE(models.key(), QByteArray("secret"));
    }

    void fileNamesStartWithTheTime() {
        const QDateTime when(QDate(2026, 11, 18), QTime(15, 4, 5));
        QCOMPARE(Generator::fileName("A calm lake, at dusk! With mist over the water", when),
                 QString("20261118-150405-a-calm-lake-at-dusk-with"));
        QCOMPARE(Generator::fileName("!!!", when), QString("20261118-150405"));
    }

    void generatorSavesTheFinishedImageWithItsPreviews() {
        QTemporaryDir dir;
        FakeServer server;
        int polls = 0;
        const QByteArray image = png().toBase64();
        server.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (path == "/sdcpp/v1/capabilities")
                return {200, q("{'defaults_by_mode': {'img_gen': {'sample_params': {'sample_steps': 4, 'guidance': {'txt_cfg': 1.0}}}}}")};
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'job1', 'status': 'queued'}")};
            if (path == "/sdcpp/v1/jobs/job1") {
                ++polls;
                // Escaped, not raw: moc misreads a raw literal with a lone quote.
                const QByteArray step = QByteArray::number(polls);
                if (polls < 3)
                    return {200, "{\"status\": \"generating\", \"progress\": {\"stage\": \"sampling\", \"unit\": \"steps\", "
                                 "\"completed\": " + step + ", \"total\": 4}, \"preview\": {\"step\": " + step
                                     + ", \"total_steps\": 4, \"b64_json\": \"" + image + "\"}}"};
                return {200, "{\"status\": \"completed\", \"result\": {\"images\": [{\"index\": 0, \"b64_json\": \"" + image + "\"}]}}"};
            }
            return {404, "{}"};
        };
        readyEngine(dir.path() + "/state", server.origin());
        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        Generator generator(&models, dir.path() + "/out");
        QTRY_COMPARE(generator.defaultSteps(), 4);

        QSignalSpy saved(&generator, &Generator::saved);
        generator.generate("a lake", 1024, 768, 0, -1);
        QVERIFY(generator.busy());
        QTRY_VERIFY_WITH_TIMEOUT(saved.size() == 1, 10000);
        QVERIFY(!generator.busy());
        QVERIFY(generator.error().isEmpty());

        // The request carries the model's defaults under what the window set.
        const QJsonObject body = server.requests.at(1).second;
        QCOMPARE(server.requests.at(1).first, QString("POST /sdcpp/v1/img_gen"));
        QCOMPARE(body.value("width").toInt(), 1024);
        QCOMPARE(body.value("height").toInt(), 768);
        QCOMPARE(body.value("sample_params").toObject().value("sample_steps").toInt(), 4);
        QCOMPARE(body.value("sample_params").toObject().value("guidance").toObject().value("txt_cfg").toDouble(), 1.0);
        QCOMPARE(body.value("preview").toString(), QString("proj"));

        // Two steps were caught as they rendered; the rest were not.
        QCOMPARE(generator.previews().size(), 4);
        QVERIFY(generator.previews().at(0).startsWith("data:image/png;base64,"));
        QVERIFY(generator.previews().at(1).startsWith("data:image/png;base64,"));
        QVERIFY(generator.previews().at(2).isEmpty());

        const QString path = saved.first().first().toString();
        QVERIFY(QFileInfo(path).fileName().endsWith("-a-lake.png"));
        QCOMPARE(generator.image(), QUrl::fromLocalFile(path).toString());
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), QByteArray::fromBase64(image));
        // Nothing half-written is left beside it.
        QCOMPARE(QDir(dir.path() + "/out").entryList(QDir::Files | QDir::Hidden).size(), 1);
    }

    void generatorStartsFromABaseImageAtItsSize() {
        QTemporaryDir dir;
        FakeServer server;
        server.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'job4'}")};
            if (path == "/sdcpp/v1/jobs/job4")
                return {200, q("{'status': 'cancelled'}")};
            return {404, "{}"};
        };
        readyEngine(dir.path() + "/state", server.origin());
        QImage base(1344, 768, QImage::Format_RGB32);
        base.fill(Qt::darkBlue);
        QVERIFY(base.save(dir.filePath("base.png")));

        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        Generator generator(&models, dir.path() + "/out");
        generator.generate("the same, with snow", 1024, 1024, 0, -1, QStringList{QUrl::fromLocalFile(dir.filePath("base.png")).toString()});
        QTRY_VERIFY(!server.requests.isEmpty() && server.requests.last().first == "POST /sdcpp/v1/img_gen");
        const QJsonObject body = server.requests.last().second;
        QFile file(dir.filePath("base.png"));
        QVERIFY(file.open(QIODevice::ReadOnly));
        const QString sent = QString::fromLatin1(file.readAll().toBase64());
        QCOMPARE(body.value("init_image").toString(), sent);
        QCOMPARE(body.value("strength").toDouble(), Generator::baseStrength);
        QVERIFY(!body.contains("ref_images"));
        QCOMPARE(body.value("width").toInt(), 1344);
        QCOMPARE(body.value("height").toInt(), 768);
        QTRY_VERIFY(!generator.busy());

        // An edit model gets the image as a reference and the prompt as the change.
        generator.generate("include a red balloon", 1024, 1024, 0, -1, QStringList{QUrl::fromLocalFile(dir.filePath("base.png")).toString()}, true);
        QTRY_VERIFY(std::count_if(server.requests.begin(), server.requests.end(), [](const auto &r) { return r.first == "POST /sdcpp/v1/img_gen"; }) == 2);
        const QJsonObject edit = server.requests.last().second;
        QCOMPARE(edit.value("ref_images").toArray(), QJsonArray{sent});
        QVERIFY(!edit.contains("init_image") && !edit.contains("strength"));
        QCOMPARE(edit.value("width").toInt(), 1344);
        QTRY_VERIFY(!generator.busy());
    }

    void generatorCombinesPicturesOnlyWithAnEditModel() {
        QTemporaryDir dir;
        FakeServer server;
        server.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'job5'}")};
            if (path == "/sdcpp/v1/jobs/job5")
                return {200, q("{'status': 'cancelled'}")};
            return {404, "{}"};
        };
        readyEngine(dir.path() + "/state", server.origin());
        QStringList pictures;
        for (const char *name : {"cabin.png", "lighthouse.png"}) {
            write(dir.filePath(name), png(64));
            pictures << QUrl::fromLocalFile(dir.filePath(name)).toString();
        }
        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        Generator generator(&models, dir.path() + "/out");
        // A model that only redraws can't combine them.
        generator.generate("the cabin beside the lighthouse", 1024, 1024, 0, -1, pictures, false);
        QVERIFY(!generator.busy());
        QCOMPARE(generator.error(), QString("Only a model that edits can combine pictures"));
        // One that edits gets them all as references.
        generator.generate("the cabin beside the lighthouse", 1024, 1024, 0, -1, pictures, true);
        QTRY_VERIFY(!server.requests.isEmpty() && server.requests.last().first == "POST /sdcpp/v1/img_gen");
        QCOMPARE(server.requests.last().second.value("ref_images").toArray().size(), 2);
        QTRY_VERIFY(!generator.busy());
    }

    void generatorSendsAChangeToTheEditModelAndTheNextImageBack() {
        QTemporaryDir dir;
        FakeServer chosen, editor;
        bool cancelled = false;
        chosen.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (path == "/sdcpp/v1/capabilities")
                return {200, "{}"};
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'new1'}")};
            if (path == "/sdcpp/v1/jobs/new1")
                return {200, q("{'status': 'cancelled'}")};
            return {404, "{}"};
        };
        editor.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'edit1'}")};
            if (method == "POST" && path == "/sdcpp/v1/jobs/edit1/cancel") {
                cancelled = true;
                return {200, "{}"};
            }
            if (path == "/sdcpp/v1/jobs/edit1")
                return {200, cancelled ? q("{'status': 'cancelled'}") : q("{'status': 'generating'}")};
            return {404, "{}"};
        };
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"a", QJsonObject{{"kind", "image"}, {"name", "A"}, {"unit", "active"}, {"endpoint", chosen.origin() + "/v1"}}},
            {"b", QJsonObject{{"kind", "image"}, {"name", "B"}, {"unit", "active"}, {"edit", true}, {"endpoint", editor.origin() + "/v1"}}}}}}).toJson());
        write(state + "/list.json", "[]");
        write(state + "/key", "secret\n");
        write(dir.filePath("base.png"), png(64));

        Models models(state, state + "/key", "/bin/true");
        QCOMPARE(models.modelId(), QString("a"));
        Generator generator(&models, dir.path() + "/out");
        // The change goes to the model that edits, and so does its polling and cancelling.
        generator.generate("make it night", 1024, 1024, 0, -1, QStringList{QUrl::fromLocalFile(dir.filePath("base.png")).toString()}, false);
        QTRY_VERIFY(!editor.requests.isEmpty() && editor.requests.first().first == "POST /sdcpp/v1/img_gen");
        QVERIFY(editor.requests.first().second.contains("ref_images"));
        QTRY_VERIFY(std::any_of(editor.requests.begin(), editor.requests.end(), [](const auto &r) { return r.first == "GET /sdcpp/v1/jobs/edit1"; }));
        generator.cancel();
        QTRY_VERIFY(cancelled);
        QTRY_VERIFY(!generator.busy());
        // The next new image goes back to the chosen model; only it is asked for settings.
        generator.generate("a calm lake", 1024, 1024);
        QTRY_VERIFY(std::any_of(chosen.requests.begin(), chosen.requests.end(), [](const auto &r) { return r.first == "POST /sdcpp/v1/img_gen"; }));
        QTRY_VERIFY(!generator.busy());
        QVERIFY(std::none_of(editor.requests.begin(), editor.requests.end(), [](const auto &r) { return r.first.contains("capabilities"); }));
        QCOMPARE(std::count_if(editor.requests.begin(), editor.requests.end(), [](const auto &r) { return r.first == "POST /sdcpp/v1/img_gen"; }), 1);
    }

    void generatorAnimatesAPictureIntoAClipWithItsPoster() {
        QCOMPARE(Generator::fitVideo(1920, 1080), QSize(864, 480));
        QCOMPARE(Generator::fitVideo(1024, 1024), QSize(640, 640));
        QTemporaryDir dir;
        FakeServer images, video;
        images.answer = [](const QString &, const QString &) -> QPair<int, QByteArray> { return {200, "{}"}; };
        const QByteArray clip("a webm clip");
        video.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (path == "/sdcpp/v1/capabilities")
                return {200, q("{'loras': [{'path': 'turbo.safetensors'}]}")};
            if (method == "POST" && path == "/sdcpp/v1/vid_gen")
                return {202, q("{'id': 'clip1'}")};
            if (path == "/sdcpp/v1/jobs/clip1")
                return {200, QJsonDocument(QJsonObject{{"status", "completed"}, {"result", QJsonObject{{"b64_json", QString::fromLatin1(clip.toBase64())}}}}).toJson()};
            return {404, "{}"};
        };
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"klein", QJsonObject{{"kind", "image"}, {"name", "Klein"}, {"unit", "active"}, {"endpoint", images.origin() + "/v1"}}},
            {"h3", QJsonObject{{"kind", "video"}, {"name", "MiniMax H3"}, {"vendor", "minimax"}, {"unit", "active"}, {"endpoint", video.origin() + "/v1"}, {"max_seconds", 15}}}}}}).toJson());
        write(state + "/list.json", "[]");
        write(state + "/key", "secret\n");
        QImage picture(1024, 1024, QImage::Format_RGB32);
        picture.fill(Qt::darkRed);
        QVERIFY(picture.save(dir.filePath("cabin.png")));

        Models models(state, state + "/key", "/bin/true");
        // The video model is a choice like an image one; choosing it makes clips.
        QVERIFY(!models.video());
        models.choose("h3");
        QVERIFY(models.video());
        QCOMPARE(models.modelName(), QString("MiniMax H3"));
        QCOMPARE(models.vendor(), QString("minimax"));
        // As long as the engine says the model makes here, a GB300's 15 s included.
        QCOMPARE(models.clipLengths(), (QVariantList{2, 5, 10, 15}));
        QCOMPARE(Models::lengthsUpTo(6), (QList<int>{2, 5}));
        QCOMPARE(Models::lengthsUpTo(-1), (QList<int>{2, 5, 10}));
        QCOMPARE(Models::lengthsUpTo(0), (QList<int>{2}));
        Generator generator(&models, dir.path() + "/out");
        QSignalSpy saved(&generator, &Generator::saved);
        generator.makeVideo("snow falls", 1344, 768, QUrl::fromLocalFile(dir.filePath("cabin.png")).toString());
        QTRY_COMPARE(saved.count(), 1);
        // On the video model's server, with its LoRA, the picture as the first frame.
        const auto submit = std::find_if(video.requests.begin(), video.requests.end(), [](const auto &r) { return r.first == "POST /sdcpp/v1/vid_gen"; });
        QVERIFY(submit != video.requests.end());
        QCOMPARE(submit->second.value("lora").toArray().first().toObject().value("path").toString(), QString("turbo.safetensors"));
        QVERIFY(!submit->second.value("init_image").toString().isEmpty());
        QCOMPARE(submit->second.value("width").toInt(), 640);
        // Five seconds at 24 frames a second unless asked otherwise.
        QCOMPARE(submit->second.value("video_frames").toInt(), 120);
        QVERIFY(images.requests.isEmpty() || std::none_of(images.requests.begin(), images.requests.end(), [](const auto &r) { return r.first.contains("vid_gen"); }));
        // The clip, with a poster beside it that the history lists as the clip.
        const QString path = saved.first().first().toString();
        QVERIFY(path.endsWith(".webm"));
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), clip);
        const History::Entry entry = History::readEntry(path.chopped(5) + ".png");
        QCOMPARE(entry.video, path);
        QCOMPARE(entry.prompt, QString("snow falls"));
        // A poster naming anything but its own clip isn't one, so deleting it
        // trashes nothing else.
        for (const char *named : {"..", "cabin.png", "other.webm"}) {
            QImage poster(8, 8, QImage::Format_RGB32);
            poster.setText("fantasi-video", named);
            QVERIFY(poster.save(dir.filePath("forged.png")));
            QVERIFY2(History::readEntry(dir.filePath("forged.png")).video.isEmpty(), named);
        }
        // A GB300's 15 s clip asks for 360 frames, past the old 10 s limit.
        QTRY_VERIFY(!generator.busy());
        generator.makeVideo("snow falls", 1344, 768, "", 15);
        QTRY_COMPARE(saved.count(), 2);
        const auto longest = std::find_if(video.requests.rbegin(), video.requests.rend(), [](const auto &r) { return r.first == "POST /sdcpp/v1/vid_gen"; });
        QCOMPARE(longest->second.value("video_frames").toInt(), 360);
    }

    void songsGoByTheirChorus() {
        QCOMPARE(Generator::songTitle("[verse]\nBy the sea\n[Chorus - loud]\nTake me home,\nagain", "x"), QString("Take me home"));
        QCOMPARE(Generator::songTitle("[Intro]\n\n[verse 1]\nTyping at midnight!", "x"), QString("Typing at midnight"));
        // A pre-chorus leads up to the chorus, and isn't it.
        QCOMPARE(Generator::songTitle("[Verse]\nOne\n[Pre-Chorus]\nAlmost there\n[Chorus]\nHere we are", "x"), QString("Here we are"));
        // Without words, what was asked for, up to its first comma.
        QCOMPARE(Generator::songTitle("[Instrumental]", "calm ambient piano, slow"), QString("calm ambient piano"));
        QCOMPARE(Generator::songTitle("", QString(80, 'a')).size(), 48);
        // Its shape: each bar as loud as its share of the song, against the loudest.
        QByteArray samples(Generator::waveBars * 2 * 2, '\0');
        samples[1] = 0x20;                    // the first bar, half as loud
        samples[samples.size() - 1] = 0x40;   // as the last
        const QByteArray wave = Generator::songWave(samples);
        QCOMPARE(wave.size(), int(Generator::waveBars));
        QCOMPARE(uchar(wave.front()), uchar(127));
        QCOMPARE(uchar(wave.back()), uchar(255));
        QCOMPARE(Generator::songWave({}), QByteArray(Generator::waveBars, '\0'));
    }

    void generatorWritesASongThenRendersItWithItsPoster() {
        QTemporaryDir dir;
        FakeServer music;
        // Bytes that look like a part's end, but aren't the boundary.
        const QByteArray song("an mp3 song\r\n--not the boundary\r\n\r\n");
        music.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/lm")
                return {200, q("{'id': 'w1'}")};
            if (path == "/job?id=w1" || path == "/job?id=r1")
                return {200, q("{'status': 'done'}")};
            if (path == "/job?id=w1&result=1")
                return {200, q("[{'caption': 'A warm folk song', 'lyrics': '[verse]\\nBy the sea\\n[chorus]\\nMy dog swims', 'audio_codes': '1,2,3'}]")};
            if (method == "POST" && path == "/synth")
                return {200, q("{'id': 'r1'}")};
            if (path == "/job?id=r1&result=1")
                return {200, "--b\r\nContent-Type: audio/mpeg\r\n\r\n" + song + "\r\n--b\r\nContent-Type: application/octet-stream\r\n\r\nlatent\r\n--b--\r\n"};
            return {404, "{}"};
        };
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{{"ace", QJsonObject{
            {"kind", "music"}, {"name", "ACE-Step"}, {"unit", "active"}, {"endpoint", music.origin() + "/v1"}}}}}}).toJson());
        write(state + "/list.json", "[]");
        write(state + "/key", "secret\n");

        // A music model is a choice like an image one; in use, it makes songs.
        Models models(state, state + "/key", "/bin/true");
        QVERIFY(models.music());
        QVERIFY(models.choices().first().toMap().value("music").toBool());
        Generator generator(&models, dir.path() + "/out", dir.path() + "/music");
        QSignalSpy saved(&generator, &Generator::saved);
        // With nowhere to put its poster, the song isn't saved yet: the
        // history couldn't list it. It can be tried again.
        QDir().mkpath(dir.path() + "/out");
        QFile::setPermissions(dir.path() + "/out", QFile::ReadOwner | QFile::ExeOwner);
        generator.makeSong("a folk song about a dog", "", 30, "pt-BR");
        QTRY_VERIFY(!generator.busy());
        QCOMPARE(saved.count(), 0);
        QVERIFY(generator.unsaved());
        QVERIFY(!generator.error().isEmpty());
        QFile::setPermissions(dir.path() + "/out", QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        // Its poster never replaces an image that took the name meanwhile.
        const QString taken = dir.path() + "/out/" + QFileInfo(QDir(dir.path() + "/music").entryList({"*.mp3"}).value(0)).completeBaseName() + ".png";
        QVERIFY(write(taken, "an image"));
        generator.retrySave();
        QCOMPARE(saved.count(), 0);
        QVERIFY(generator.unsaved());
        QFile image(taken);
        QVERIFY(image.open(QIODevice::ReadOnly));
        QCOMPARE(image.readAll(), QByteArray("an image"));
        image.close();
        QVERIFY(image.remove());
        generator.retrySave();
        QCOMPARE(saved.count(), 1);
        QVERIFY(!generator.unsaved());
        QCOMPARE(generator.error(), QString());
        // Written first, in the language's plain code, then rendered as written.
        const auto request = [&](const QString &what) {
            const auto found = std::find_if(music.requests.begin(), music.requests.end(), [&](const auto &r) { return r.first == what; });
            return found == music.requests.end() ? QJsonObject() : found->second;
        };
        QCOMPARE(request("POST /lm").value("caption").toString(), QString("a folk song about a dog"));
        QCOMPARE(request("POST /lm").value("duration").toInt(), 30);
        QCOMPARE(request("POST /lm").value("vocal_language").toString(), QString("pt"));
        QCOMPARE(request("POST /synth").value("audio_codes").toString(), QString("1,2,3"));
        // The MP3, whole, with the music, and a poster among the images that
        // the history lists as the song, by its chorus.
        const QString path = saved.first().first().toString();
        QVERIFY(path.startsWith(dir.path() + "/music/") && path.endsWith(".mp3"));
        QFile file(path);
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(), song);
        const History::Entry entry = History::readEntry(dir.path() + "/out/" + QFileInfo(path).completeBaseName() + ".png", dir.path() + "/music");
        QCOMPARE(entry.audio, path);
        // The window finds a song's title and shape by its file.
        History history(dir.path() + "/out", dir.path() + "/music");
        QTRY_COMPARE(history.count(), 1);
        QCOMPARE(history.song(QUrl::fromLocalFile(path).toString()).value("title").toString(), QString("My dog swims"));
        QCOMPARE(history.song("file:///elsewhere.mp3").value("title").toString(), QString());
        QCOMPARE(entry.title, QString("My dog swims"));
        QCOMPARE(entry.wave.size(), int(Generator::waveBars));
        QCOMPARE(entry.prompt, QString("a folk song about a dog"));
        // An image model makes no songs.
        readyEngine(state, music.origin());
        QTRY_VERIFY(!models.music());
        generator.makeSong("another");
        QVERIFY(!generator.busy());
        QCOMPARE(generator.error(), QString("No music model is running"));
    }

    void aMusicModelTurnsTheBarToSongs() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{{"ace", QJsonObject{
            {"kind", "music"}, {"name", "ACE-Step"}, {"unit", "active"}, {"endpoint", "http://127.0.0.1:9/v1"}}}}}}).toJson());
        write(state + "/list.json", "[]");
        write(state + "/key", "secret\n");
        Backend backend({state, state + "/key", "/bin/true", dir.path() + "/out", "/bin/true", {}});

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

        // No picture to start from and no shape: a song has lyrics and a length.
        QTRY_VERIFY(window->property("musicMode").toBool());
        auto *lyricsChoice = item(window->contentItem(), "lyricsChoice");
        auto *length = item(window->contentItem(), "songLength");
        auto *lyricsBar = item(window->contentItem(), "lyricsBar");
        QVERIFY(lyricsChoice && length && lyricsBar);
        QVERIFY(lyricsChoice->isVisible() && length->isVisible());
        QVERIFY(!item(window->contentItem(), "size")->isVisible());
        QVERIFY(!item(window->contentItem(), "startFrom")->isVisible());
        // The lyrics are the model's until asked for: then there's room to
        // write them, and after that none at all.
        QVERIFY(!lyricsBar->isVisible());
        QCOMPARE(lyricsChoice->property("label").toString(), QString("Lyrics written for you"));
        QMetaObject::invokeMethod(lyricsChoice, "clicked");
        QTRY_VERIFY(lyricsBar->isVisible());
        QCOMPARE(lyricsChoice->property("label").toString(), QString("Your own lyrics"));
        QMetaObject::invokeMethod(lyricsChoice, "clicked");
        QTRY_VERIFY(!lyricsBar->isVisible());
        QCOMPARE(lyricsChoice->property("label").toString(), QString("No lyrics, only music"));
        // A minute, then longer with each click.
        QCOMPARE(length->property("text").toString(), QString("1:00"));
        QMetaObject::invokeMethod(length, "clicked");
        QCOMPARE(length->property("text").toString(), QString("2:00"));

        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }

    void anInstrumentalMusicModelSkipsLyrics() {
        QTemporaryDir dir;
        FakeServer music;
        const QByteArray song("an instrumental mp3");
        music.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/synth")
                return {200, q("{'id': 's1'}")};
            if (path == "/job?id=s1")
                return {200, q("{'status': 'done'}")};
            if (path == "/job?id=s1&result=1")
                return {200, "--b\r\nContent-Type: audio/mpeg\r\n\r\n" + song + "\r\n--b--\r\n"};
            return {404, "{}"};
        };
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{{"sa3", QJsonObject{
            {"kind", "music"}, {"vocals", false}, {"vendor", "stability"}, {"name", "Stable Audio 3 Medium"},
            {"unit", "active"}, {"endpoint", music.origin() + "/v1"}}}}}}).toJson());
        write(state + "/list.json", QJsonDocument(QJsonArray{QJsonObject{
            {"id", "sa3"}, {"kind", "music"}, {"vocals", false}, {"vendor", "stability"},
            {"name", "Stable Audio 3 Medium"}, {"available", true}, {"download_gib", 2.56}, {"memory_gib", 4}}}).toJson());
        write(state + "/key", "secret\n");

        Models models(state, state + "/key", "/bin/true");
        QVERIFY(models.music());
        QVERIFY(!models.vocals());
        QCOMPARE(models.offers().first().toMap().value("vocals").toBool(), false);

        Generator generator(&models, dir.path() + "/out", dir.path() + "/music");
        QSignalSpy saved(&generator, &Generator::saved);
        generator.makeSong("warm analog synthwave, driving beat", "ignored lyrics", 60, "en");
        QTRY_COMPARE(saved.count(), 1);
        QVERIFY(std::none_of(music.requests.begin(), music.requests.end(), [](const auto &r) { return r.first == "POST /lm"; }));
        const auto synth = std::find_if(music.requests.begin(), music.requests.end(), [](const auto &r) { return r.first == "POST /synth"; });
        QVERIFY(synth != music.requests.end());
        QCOMPARE(synth->second.value("caption").toString(), QString("warm analog synthwave, driving beat"));
        QCOMPARE(synth->second.value("duration").toInt(), 60);
        const QString path = saved.first().first().toString();
        const History::Entry entry = History::readEntry(dir.path() + "/out/" + QFileInfo(path).completeBaseName() + ".png", dir.path() + "/music");
        QCOMPARE(entry.title, QString("warm analog synthwave"));

        // The window hides the lyrics controls while keeping the song length.
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        Backend backend({state, state + "/key", "/bin/true", dir.path() + "/out", "/bin/true", {}});
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/Main.qml"));
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window && QTest::qWaitForWindowExposed(window));
        QTRY_VERIFY(window->property("musicMode").toBool());
        QVERIFY(!item(window->contentItem(), "lyricsChoice")->isVisible());
        QVERIFY(!item(window->contentItem(), "lyricsBar")->isVisible());
        QVERIFY(item(window->contentItem(), "songLength")->isVisible());
        QCoreApplication::removeTranslator(&translator);
    }

    void aSongsWaveFormsThenSettlesIntoItsShape() {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QQmlEngine engine;
        engine.rootContext()->setContextProperty("theme", &theme);
        QQmlComponent component(&engine, QUrl("qrc:/SongPlayer.qml"));
        std::unique_ptr<QQuickItem> player(qobject_cast<QQuickItem *>(component.create()));
        QVERIFY2(player, qPrintable(component.errorString()));
        player->setSize(QSizeF(960, 320));
        auto level = [&](const char *function, const QVariantList &arguments) {
            QVariant result;
            if (arguments.size() == 1)
                QMetaObject::invokeMethod(player.get(), function, Q_RETURN_ARG(QVariant, result), Q_ARG(QVariant, arguments[0]));
            else
                QMetaObject::invokeMethod(player.get(), function, Q_RETURN_ARG(QVariant, result), Q_ARG(QVariant, arguments[0]),
                                          Q_ARG(QVariant, arguments[1]), Q_ARG(QVariant, arguments[2]), Q_ARG(QVariant, arguments[3]));
            return result.toDouble();
        };
        const int columns = Generator::waveBars;

        // A forming wave stays within the frame at every moment, moves from
        // one moment to the next, and stands taller the further the work is.
        auto tallest = [&](double time, double formed) {
            double most = 0;
            for (int i = 0; i < columns; ++i) {
                const double height = level("formingLevel", {i, columns, time, formed});
                if (height < 0 || height > 1)
                    return -1.0;
                most = std::max(most, height);
            }
            return most;
        };
        for (double time : {0.0, 0.3, 1.7, 42.0}) {
            const double begun = tallest(time, 0), gathered = tallest(time, 1);
            QVERIFY(begun > 0 && gathered > 0);
            QVERIFY2(gathered > begun * 2, qPrintable(QString("%1 after %2 at %3 s").arg(gathered).arg(begun).arg(time)));
        }
        QVERIFY(level("formingLevel", {40, columns, 1.0, 0.5}) != level("formingLevel", {40, columns, 1.2, 0.5}));

        // A song being made has a finished song's columns already.
        QCOMPARE(player->property("columns").toInt(), 0);
        player->setProperty("forming", true);
        QCOMPARE(player->property("columns").toInt(), columns);
        QVERIFY(player->property("live").toBool());

        // Done, the columns settle onto the song's own shape, wherever they were.
        QVariantList wave;
        for (int i = 0; i < columns; ++i)
            wave << (i % 8) / 8.0;
        player->setProperty("wave", wave);
        player->setProperty("source", QUrl::fromLocalFile(dir.path() + "/song.mp3"));
        player->setProperty("forming", false);
        QVERIFY(player->property("live").toBool());
        QTRY_VERIFY(!player->property("live").toBool());
        for (int i = 0; i < columns; ++i)
            QCOMPARE(level("columnLevel", {i}), wave.at(i).toDouble());

        // Given up, with no song to become, the wave fades away, and the
        // next song shown is in its own shape at once.
        player->setProperty("source", QUrl());
        player->setProperty("wave", QVariantList());
        player->setProperty("forming", true);
        player->setProperty("forming", false);
        QVERIFY(player->property("live").toBool());
        QTRY_VERIFY(!player->property("live").toBool());
        QCOMPARE(player->property("presence").toDouble(), 1.0);
    }

    void openingAnotherModelTurnsTheWindowToMakingSomethingWithIt() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        // Two image models running: the window starts on the first.
        const auto running = [](const QString &name) {
            return QJsonObject{{"kind", "image"}, {"name", name}, {"unit", "active"}, {"port", 1}};
        };
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{
            {"a", running("Model A")}, {"b", running("Model B")}}}}).toJson());
        write(state + "/list.json", "[]");
        write(state + "/key", "secret\n");
        QSettings().setValue("model", "a");
        Backend backend({state, state + "/key", "/bin/true", dir.path() + "/out", "/bin/true", {}});

        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/Main.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(QTest::qWaitForWindowExposed(window));

        // Something made earlier is in the frame with its prompt, as after
        // picking it from the history.
        QDir().mkpath(dir.path() + "/out");
        write(dir.path() + "/out/20260101-120000-a-lake.png", png(64));
        auto *prompt = item(window->contentItem(), "prompt");
        QVERIFY(prompt);
        prompt->setProperty("text", QString("a lake"));
        backend.generator()->show(QUrl::fromLocalFile(dir.path() + "/out/20260101-120000-a-lake.png").toString());
        window->setProperty("composing", false);
        QVERIFY(!window->property("shownFile").toString().isEmpty());
        // The agents panel opens the other model: it's the one in use, with an
        // empty frame and an empty prompt to make something with it.
        backend.open("b", {});
        QCOMPARE(QSettings().value("model").toString(), QString("b"));
        QVERIFY(window->property("composing").toBool());
        QCOMPARE(window->property("shownFile").toString(), QString());
        QCOMPARE(prompt->property("text").toString(), QString());
        // A prompt being written when it's opened stays.
        prompt->setProperty("text", QString("a hill"));
        backend.open("a", {});
        QCOMPARE(prompt->property("text").toString(), QString("a hill"));

        QSettings().remove("model");
        QCoreApplication::removeTranslator(&translator);
    }

    void aModelSetUpButNotRunningWaitsInARingForAClickToStartIt() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/status.json", QJsonDocument(QJsonObject{{"models", QJsonObject{{"z", QJsonObject{
            {"kind", "image"}, {"name", "Z-Image Turbo"}, {"unit", "inactive"}}}}}}).toJson());
        write(state + "/list.json", "[]");
        write(state + "/key", "secret\n");
        // An engine that notes what it's asked to do.
        const QString command = dir.path() + "/engine";
        write(command, "#!/bin/bash\necho \"$@\" >> '" + dir.path().toUtf8() + "/asked'\n");
        QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        Backend backend({state, state + "/key", command, dir.path() + "/out", "/bin/true", {}});

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

        // The ring offers the start; the bar waits, greyed, with nothing to send.
        auto *ring = item(window->contentItem(), "starting");
        auto *wake = item(window->contentItem(), "wake");
        auto *prompt = item(window->contentItem(), "prompt");
        auto *action = item(window->contentItem(), "action");
        QVERIFY(ring && wake && prompt && action);
        QTRY_VERIFY(window->property("asleep").toBool());
        QVERIFY(ring->isVisible() && ring->property("offer").toBool());
        QCOMPARE(window->property("wakeText").toString(), QString("Start Z-Image Turbo"));
        QVERIFY(prompt->property("readOnly").toBool());
        QVERIFY(!action->isEnabled());
        QVERIFY(action->property("round").toBool());

        // A click on the ring starts the model, and the ring turns to starting.
        QTest::mouseClick(window, Qt::LeftButton, {}, wake->mapToScene(QPointF(wake->width() / 2, wake->height() / 2)).toPoint());
        const auto asked = [&] {
            QFile file(dir.path() + "/asked");
            return file.open(QIODevice::ReadOnly) ? file.readAll().split('\n') : QByteArrayList();
        };
        QTRY_VERIFY(asked().contains("start z"));

        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }

    void theModelsMarkOpensEveryModelToRemoveOne() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        const QString state = dir.path() + "/state";
        QDir().mkpath(state);
        write(state + "/status.json", q("{'models': {"
                                        "'z': {'kind': 'image', 'name': 'Z-Image Turbo', 'unit': 'active', 'endpoint': 'http://127.0.0.1:1/v1'},"
                                        "'k': {'kind': 'image', 'name': 'Klein', 'unit': 'inactive'}}}"));
        write(state + "/list.json", q("[ {'id': 'k', 'kind': 'image', 'name': 'Klein', 'available': true, 'download_gib': 8}]"));
        write(state + "/key", "secret\n");
        const QString command = dir.path() + "/engine";
        write(command, "#!/bin/bash\necho \"$@\" >> '" + dir.path().toUtf8() + "/asked'\n");
        QFile::setPermissions(command, QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        Backend backend({state, state + "/key", command, dir.path() + "/out", "/bin/true", {}});

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
        const auto click = [&](QQuickItem *button) {
            QTest::mouseClick(window, Qt::LeftButton, {}, button->mapToScene(QPointF(button->width() / 2, button->height() / 2)).toPoint());
        };

        // A click on the mark in use lists every model.
        auto *mark = item(window->contentItem(), "model");
        QVERIFY(mark);
        click(mark);
        auto *library = window->findChild<QObject *>("library");
        QVERIFY(library);
        QTRY_VERIFY(library->property("opened").toBool());
        auto *panel = qvariant_cast<QQuickItem *>(library->property("contentItem"));
        auto *klein = item(panel, "row-k");
        QVERIFY(klein && item(panel, "row-z"));

        // Removing asks first.
        click(item(klein, "remove"));
        QTRY_VERIFY(item(klein, "confirmRemove")->isVisible());
        click(item(klein, "confirmRemove"));
        const auto asked = [&] {
            QFile file(dir.path() + "/asked");
            return file.open(QIODevice::ReadOnly) ? file.readAll().split('\n') : QByteArrayList();
        };
        QTRY_VERIFY(asked().contains("remove k"));

        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }

    void generatorEstimatesTheTimeLeftFromTheLastOneLikeIt() {
        // From nothing remembered, even when a run before stopped halfway.
        QSettings().remove("durations");
        QTemporaryDir dir;
        FakeServer server;
        server.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'slow'}")};
            if (path == "/sdcpp/v1/jobs/slow")
                return {200, q("{'status': 'generating', 'progress': {'stage': 'sampling', 'unit': 'steps', 'completed': 0, 'total': 8}}")};
            return {404, "{}"};
        };
        readyEngine(dir.path() + "/state", server.origin());
        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        Generator generator(&models, dir.path() + "/out");
        // Nothing like it yet, and no step done: not known.
        generator.generate("a lake", 1024, 1024);
        QTRY_VERIFY(generator.busy());
        QCOMPARE(generator.remainingSeconds(), -1);
        QCOMPARE(generator.timeProgress(), -1.0);
        // The last one like it took 120 seconds: about that long is left.
        QSettings().setValue("durations/z-image-turbo/image/1024x1024", 120.0);
        Generator next(&models, dir.path() + "/out");
        next.generate("a lake", 1024, 1024);
        QTRY_VERIFY(next.busy());
        QVERIFY2(next.remainingSeconds() > 115 && next.remainingSeconds() <= 120, qPrintable(QString::number(next.remainingSeconds())));
        // And its share gone by fills from there, held short of whole.
        QVERIFY2(next.timeProgress() >= 0 && next.timeProgress() < 0.05, qPrintable(QString::number(next.timeProgress())));
        QSettings().setValue("durations/z-image-turbo/image/1024x1024", 0.001);
        Generator late(&models, dir.path() + "/out");
        late.generate("a lake", 1024, 1024);
        QTRY_VERIFY(late.busy());
        QTRY_COMPARE(late.timeProgress(), 0.97);
        QSettings().remove("durations");
    }

    void generatorCancelsAndSavesNothing() {
        QTemporaryDir dir;
        FakeServer server;
        bool cancelled = false;
        server.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'job2'}")};
            if (path == "/sdcpp/v1/jobs/job2/cancel") {
                cancelled = true;
                return {200, q("{'cancel_requested': true}")};
            }
            if (path == "/sdcpp/v1/jobs/job2")
                return {200, cancelled ? q("{'status': 'cancelled'}") : q("{'status': 'generating', 'progress': {'stage': 'sampling'}}")};
            return {404, "{}"};
        };
        readyEngine(dir.path() + "/state", server.origin());
        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        Generator generator(&models, dir.path() + "/out");
        generator.generate("a lake", 512, 512, 4, 7);
        QTRY_VERIFY(!server.requests.isEmpty());
        QTRY_VERIFY(generator.stage() == "sampling");
        generator.cancel();
        QTRY_VERIFY_WITH_TIMEOUT(!generator.busy(), 10000);
        QVERIFY(cancelled);
        QVERIFY(generator.error().isEmpty());
        QVERIFY(!QFileInfo::exists(dir.path() + "/out") || QDir(dir.path() + "/out").isEmpty());
    }

    void generatorSaysWhyAnImageFailed() {
        QTemporaryDir dir;
        FakeServer server;
        server.answer = [&](const QString &method, const QString &path) -> QPair<int, QByteArray> {
            if (method == "POST" && path == "/sdcpp/v1/img_gen")
                return {202, q("{'id': 'job3'}")};
            if (path == "/sdcpp/v1/jobs/job3")
                return {200, q("{'status': 'failed', 'error': {'code': 'generation_failed', 'message': 'out of memory'}}")};
            return {404, "{}"};
        };
        readyEngine(dir.path() + "/state", server.origin());
        Models models(dir.path() + "/state", dir.path() + "/state/key", "/bin/true");
        Generator generator(&models, dir.path() + "/out");
        generator.generate("a lake", 512, 512, 4, -1);
        QTRY_COMPARE_WITH_TIMEOUT(generator.error(), QString("out of memory"), 10000);
        QVERIFY(!generator.busy());
    }

    void historyReadsWhatTheImagesCarry() {
        QTemporaryDir dir;
        QImage image(4, 4, QImage::Format_RGB32);
        image.fill(Qt::red);
        image.setText("parameters", "a lake\nat dusk\nSteps: 8, Sampler: Euler, CFG scale: 1.0, Seed: 42, Size: 1024x768, Model: z");
        QVERIFY(image.save(dir.filePath("old.png")));
        QFile old(dir.filePath("old.png"));
        QVERIFY(old.open(QIODevice::ReadWrite));
        QVERIFY(old.setFileTime(QDateTime::currentDateTime().addSecs(-60), QFileDevice::FileModificationTime));
        old.close();
        QVERIFY(write(dir.filePath("new.png"), png()));
        QVERIFY(write(dir.filePath(".fantasi-partial.png"), "half"));

        const QList<History::Entry> entries = History::scan(dir.path());
        QCOMPARE(entries.size(), 2);
        QCOMPARE(QFileInfo(entries.at(0).path).fileName(), QString("new.png"));
        QCOMPARE(entries.at(1).prompt, QString("a lake\nat dusk"));
        QCOMPARE(entries.at(1).seed, 42);
        QCOMPARE(entries.at(1).size, QString("1024x768"));
        // Qt writes a text that fits Latin-1 as Latin-1, and any other as UTF-8.
        for (const QString &prompt : {QString("tô no lago"), QString("湖 ô")}) {
            image.setText("parameters", prompt + "\nSteps: 8");
            QVERIFY(image.save(dir.filePath("accent.png")));
            QCOMPARE(History::readEntry(dir.filePath("accent.png")).prompt, prompt);
        }
        // stable-diffusion.cpp writes UTF-8 into plain tEXt, and other writers
        // compress either encoding: each chunk, set before the pixels.
        const auto carries = [&](const QByteArray &type, QByteArray text) {
            if (type == "zTXt")
                text = '\0' + qCompress(text).mid(4);
            const QByteArray body = "parameters" + QByteArray(1, '\0') + text;
            QByteArray chunk(4, '\0');
            qToBigEndian(quint32(body.size()), chunk.data());
            QByteArray bytes = png();
            bytes.insert(33, chunk + type + body + QByteArray(4, '\0'));
            return write(dir.filePath("chunk.png"), bytes) ? History::readEntry(dir.filePath("chunk.png")).prompt : QString();
        };
        for (const QByteArray type : {"tEXt", "zTXt"}) {
            QCOMPARE(carries(type, QString("湖 ô\nSteps: 8").toUtf8()), QString("湖 ô"));
            QCOMPARE(carries(type, QString("tô\nSteps: 8").toLatin1()), QString("tô"));
        }
    }

    void saveAsCopiesTheImageWhereThePickerSays() {
        QTemporaryDir dir;
        QVERIFY(write(dir.filePath("made.png"), png()));
        auto *picker = new FakePicker;
        Backend backend({dir.path() + "/state", {}, "/bin/true", dir.path() + "/out", "/bin/true", {}}, picker);
        picker->setParent(&backend);

        picker->answer = QUrl::fromLocalFile(dir.filePath("copy.png"));
        backend.saveAs(QUrl::fromLocalFile(dir.filePath("made.png")).toString());
        QVERIFY(picker->suggested.toLocalFile().endsWith("/made.png"));
        QVERIFY(backend.error().isEmpty());
        QFile copy(dir.filePath("copy.png"));
        QVERIFY(copy.open(QIODevice::ReadOnly));
        QCOMPARE(copy.readAll(), png());

        // A folder that isn't there: said so, and nothing half-written.
        picker->answer = QUrl::fromLocalFile(dir.filePath("missing/copy.png"));
        backend.saveAs(QUrl::fromLocalFile(dir.filePath("made.png")).toString());
        QVERIFY(backend.error().startsWith("Couldn't save the image as"));
        QVERIFY(!QFileInfo::exists(dir.filePath("missing")));
    }

    void aPictureOfOnesOwnBecomesABaseTheModelWorksIn() {
        QTemporaryDir dir;
        // A camera's picture: any size, any shape, a JPEG.
        QImage photo(4000, 3000, QImage::Format_RGB32);
        photo.fill(Qt::darkGreen);
        QVERIFY(photo.save(dir.filePath("photo.jpg")));
        const Generator::Base base = Generator::prepareBase(dir.filePath("photo.jpg"));
        QCOMPARE(base.size, QSize(1152, 896));
        QImage sent;
        QVERIFY(sent.loadFromData(base.png, "PNG"));
        QCOMPARE(sent.size(), QSize(1152, 896));

        // Fantasi's own image goes as it is, byte for byte.
        QVERIFY(write(dir.filePath("made.png"), png(1024)));
        QCOMPARE(Generator::prepareBase(dir.filePath("made.png")).png, png(1024));
        QVERIFY(Generator::prepareBase(dir.filePath("missing.png")).png.isEmpty());
    }

    void aPictureChosenInTheDialogReachesTheWindow() {
        QTemporaryDir dir;
        auto *picker = new FakePicker;
        Backend backend({dir.path() + "/state", {}, "/bin/true", dir.path() + "/out", "/bin/true", {}}, picker);
        picker->setParent(&backend);
        picker->answer = QUrl::fromLocalFile(dir.filePath("mine.jpg"));
        QSignalSpy chosen(&backend, &Backend::pictureChosen);
        backend.openPicture();
        QCOMPARE(chosen.size(), 1);
        QCOMPARE(chosen.first().first().toString(), picker->answer.toString());
    }

    void screenSizeIsAMegapixelInTheMonitorsShape() {
        QCOMPARE(Generator::fitMegapixel(2560, 1440), QSize(1344, 768));
        QCOMPARE(Generator::fitMegapixel(1440, 2560), QSize(768, 1344));
        QCOMPARE(Generator::fitMegapixel(1000, 1000), QSize(1024, 1024));
    }

    void themeFallsBack() {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QColor("#FFD60A"));
        QCOMPARE(theme.accentForeground(), QColor("black"));
        QVERIFY(!theme.light());
        QCOMPARE(theme.radius(), 0);
        QCOMPARE(theme.inactiveBorder(), QColor(0x59, 0x59, 0x59, 0xaa));
    }

    void themeReadsThePalette() {
        QTemporaryDir dir;
        QVERIFY(QDir(dir.path()).mkpath("theme"));
        QVERIFY(write(dir.path() + "/theme/colors.toml", "mode = \"light\"\n"
                                                         "theme_type = \"dark\"\n"
                                                         "accent = \"#112233\"\n"
                                                         "bg = #fafafa # paper\n"
                                                         "foreground = '#202020'\n"
                                                         "color1 = \"#aa0000\"\n"
                                                         "hyprland_inactive_border = \"rgba(584e51aa) rgba(000000ff) 45deg\"\n"));

        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QColor("#112233"));
        QCOMPARE(theme.accentForeground(), QColor("white"));
        QCOMPARE(theme.background(), QColor("#fafafa"));
        QCOMPARE(theme.foreground(), QColor("#202020"));
        QCOMPARE(theme.colors().value("red").value<QColor>(), QColor("#aa0000"));
        QCOMPARE(theme.inactiveBorder(), QColor(0x58, 0x4e, 0x51, 0xaa));
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

    void fShowsTheFrameFullScreenAndArrowsMoveThroughTheHistory() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        readyEngine(dir.path() + "/state", "http://127.0.0.1:9");
        // Two images made before, newest first in the history.
        QDir().mkpath(dir.path() + "/out");
        write(dir.path() + "/out/20260101-120000-a-lake.png", png(64));
        write(dir.path() + "/out/20260102-120000-a-hill.png", png(64));
        Backend backend({dir.path() + "/state", dir.path() + "/state/key", "/bin/true", dir.path() + "/out", "/bin/true", {}});

        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/Main.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(QTest::qWaitForWindowExposed(window));
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        QTRY_COMPARE(window->property("modelStatus").toString(), QString("Z-Image Turbo is ready"));
        auto *list = item(window->contentItem(), "history");
        auto *rail = item(window->contentItem(), "rail");
        auto *prompt = item(window->contentItem(), "prompt");
        QVERIFY(list && rail && prompt);
        QTRY_COMPARE(list->property("count").toInt(), 2);

        // With the prompt empty, down and up step through the history.
        QTest::keyClick(window, Qt::Key_Down);
        QTRY_COMPARE(list->property("currentIndex").toInt(), 0);
        QTest::keyClick(window, Qt::Key_Down);
        QTRY_COMPARE(list->property("currentIndex").toInt(), 1);
        QTest::keyClick(window, Qt::Key_Up);
        QTRY_COMPARE(list->property("currentIndex").toInt(), 0);

        // F shows it alone on the whole screen, and Escape brings it all back.
        QTest::keyClick(window, Qt::Key_F);
        QVERIFY(window->property("fullView").toBool());
        QTRY_COMPARE(window->visibility(), QWindow::FullScreen);
        QVERIFY(!rail->isVisible());
        QTest::keyClick(window, Qt::Key_Escape);
        QVERIFY(!window->property("fullView").toBool());
        QTRY_VERIFY(window->visibility() != QWindow::FullScreen);
        QVERIFY(rail->isVisible());
        // The button beside the + does the same.
        auto *button = item(window->contentItem(), "fullScreen");
        QVERIFY(button && button->isVisible());
        QMetaObject::invokeMethod(button, "click");
        QVERIFY(window->property("fullView").toBool());
        QTest::keyClick(window, Qt::Key_Escape);
        QVERIFY(!window->property("fullView").toBool());

        // In a prompt being written, F is a letter and the arrows stay there.
        QTest::keyClick(window, Qt::Key_N, Qt::ControlModifier);
        QTRY_VERIFY(prompt->property("activeFocus").toBool());
        QTest::keyClick(window, 'f');
        QCOMPARE(prompt->property("text").toString(), QString("f"));
        QVERIFY(!window->property("fullView").toBool());
        const int index = list->property("currentIndex").toInt();
        QTest::keyClick(window, Qt::Key_Down);
        QCOMPARE(list->property("currentIndex").toInt(), index);

        // A result arriving ends the writing as onSaved does: the hidden prompt
        // lets the keyboard go, so F shows the result.
        window->setProperty("composing", false);
        QVERIFY(!prompt->property("activeFocus").toBool());
        QTest::keyClick(window, Qt::Key_F);
        QVERIFY(window->property("fullView").toBool());
        // Starting to write from the full view leaves it, so the prompt being
        // typed in is in sight.
        QTest::keyClick(window, Qt::Key_N, Qt::ControlModifier);
        QVERIFY(!window->property("fullView").toBool());
        QTRY_VERIFY(prompt->isVisible() && prompt->property("activeFocus").toBool());

        QCoreApplication::removeTranslator(&translator);
    }

    void windowLoadsAndAnswersTheKeyboard() {
        // A temp language and theme, so the test never depends on the desktop's.
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        // A ready model at an address nothing answers, so nothing is made.
        readyEngine(dir.path() + "/state", "http://127.0.0.1:9");
        // One image made before, to pick from the history.
        QDir().mkpath(dir.path() + "/out");
        write(dir.path() + "/out/20260101-120000-a-lake.png", png(64));
        Backend backend({dir.path() + "/state", dir.path() + "/state/key", "/bin/true", dir.path() + "/out", "/bin/true", {}});

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

        auto *model = item(window->contentItem(), "model");
        auto *action = item(window->contentItem(), "action");
        QVERIFY(model && action);
        QTRY_COMPARE(window->property("modelStatus").toString(), QString("Z-Image Turbo is ready"));
        QCOMPARE(action->property("text").toString(), QString("Generate"));
        // Nothing to make until there's a prompt, which takes the keyboard.
        QVERIFY(!action->property("enabled").toBool());
        for (const char c : QByteArray("a calm lake"))
            QTest::keyClick(window, c);
        QCOMPARE(item(window->contentItem(), "prompt")->property("text").toString(), QString("a calm lake"));
        QVERIFY(action->property("enabled").toBool());
        // Enter sends the prompt; this engine's model is at an address nothing
        // answers, so sending shows up as the error it gets back.
        QTest::keyClick(window, Qt::Key_Return);
        QTRY_VERIFY(!backend.generator()->error().isEmpty() || backend.generator()->busy());
        QCOMPARE(item(window->contentItem(), "prompt")->property("text").toString(), QString("a calm lake"));

        // The caption reads on the accent: black on the fallback yellow.
        QCOMPARE(action->property("contentItem").value<QQuickItem *>()->property("color").value<QColor>(),
                 theme.accentForeground());

        // The size buttons pick one of three.
        // One button steps through the shapes; Ctrl+3 goes straight to portrait.
        auto *shape = item(window->contentItem(), "size");
        QVERIFY(shape);
        // Nothing changes while something is made: wait for the one sent above.
        QTRY_VERIFY(!backend.generator()->busy());
        QTest::keyClick(window, Qt::Key_3, Qt::ControlModifier);
        QCOMPARE(shape->property("current").toMap().value("name").toString(), QString("Portrait"));
        QMetaObject::invokeMethod(shape, "clicked");
        QCOMPARE(shape->property("current").toMap().value("name").toString(), QString("Screen"));

        auto *help = window->findChild<QObject *>("help");
        QTest::keyClick(window, Qt::Key_F1);
        QTRY_VERIFY(help->property("opened").toBool());
        // A Material popup animates out: `opened` drops at once, `visible` after.
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(!help->property("visible").toBool());

        // A picked image offers what's next; a new one empties the prompt
        // and the frame; Esc goes back to the image.
        auto *nextBar = item(window->contentItem(), "next");
        auto *prompt = item(window->contentItem(), "prompt");
        QVERIFY(nextBar && prompt);
        QTRY_VERIFY(backend.history()->count() == 1);
        // The history shows once there's an image, and Ctrl+B hides and shows it.
        auto *rail = item(window->contentItem(), "rail");
        QVERIFY(rail);
        QTRY_VERIFY(rail->isVisible());
        QTest::keyClick(window, Qt::Key_B, Qt::ControlModifier);
        QTRY_VERIFY(!rail->isVisible());
        QTest::keyClick(window, Qt::Key_B, Qt::ControlModifier);
        QTRY_VERIFY(rail->isVisible());
        QTest::keyClick(window, Qt::Key_Down, Qt::ControlModifier);
        QTRY_VERIFY(nextBar->isVisible());
        QVERIFY(!prompt->isVisible());
        QTest::keyClick(window, Qt::Key_N, Qt::ControlModifier);
        QTRY_VERIFY(prompt->isVisible());
        QVERIFY(!nextBar->isVisible());
        // A second Ctrl+N keeps the image Esc goes back to.
        QTest::keyClick(window, Qt::Key_N, Qt::ControlModifier);
        QCOMPARE(prompt->property("text").toString(), QString());
        QCOMPARE(backend.generator()->image(), QString());
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(nextBar->isVisible());
        QVERIFY(backend.generator()->image().endsWith("a-lake.png"));
        // Change it: back to writing, with the picture to change.
        QTest::keyClick(window, Qt::Key_E, Qt::ControlModifier);
        QTRY_VERIFY(prompt->isVisible());
        QVERIFY(window->property("changing").toBool());
        // Esc lets the change go; a new image again, for what follows.
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(nextBar->isVisible());
        QTest::keyClick(window, Qt::Key_N, Qt::ControlModifier);
        QTRY_VERIFY(prompt->isVisible());

        // Each control in the prompt bar names itself in a tooltip on hover.
        for (const char *name : {"startFrom", "size", "model"}) {
            auto *control = item(window->contentItem(), name);
            QVERIFY2(control && control->isVisible(), name);
            const QPointF centre = control->mapToScene(QPointF(control->width() / 2, control->height() / 2));
            QTest::mouseMove(window, centre.toPoint());
            QTRY_VERIFY2(control->property("hovered").toBool(), name);
            QTRY_VERIFY2(QQmlProperty(control, "ToolTip.visible", qmlContext(control)).read().toBool(), name);
        }

        // Delete asks first: Esc keeps the image, Enter moves it to the trash
        // and goes on to the next one. While a prompt takes the keyboard,
        // Delete is the prompt's.
        // A newer one, which Esc lands on, with the lake next after it.
        write(dir.path() + "/out/20260102-120000-a-river.png", png(64));
        QTRY_COMPARE(backend.history()->count(), 2);
        auto *trash = window->findChild<QObject *>("trash");
        QVERIFY(trash);
        QTest::keyClick(window, Qt::Key_Delete);
        QVERIFY(!trash->property("opened").toBool());
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(nextBar->isVisible());
        QTest::keyClick(window, Qt::Key_Delete);
        QTRY_VERIFY(trash->property("opened").toBool());
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(!trash->property("visible").toBool());
        QCOMPARE(backend.history()->count(), 2);
        // A trash of the test's own, on the same disk as the image: test mode
        // keeps data under ~/.qttest/share, and Qt makes only the Trash in it.
        const QByteArray home = qgetenv("HOME");
        qputenv("HOME", dir.path().toUtf8());
        QVERIFY(QDir().mkpath(dir.path() + "/.qttest/share"));
        QTest::keyClick(window, Qt::Key_Delete);
        QTRY_VERIFY(trash->property("opened").toBool());
        QTest::keyClick(window, Qt::Key_Return);
        QTRY_COMPARE(backend.history()->count(), 1);
        QTRY_VERIFY(backend.generator()->image().endsWith("a-lake.png"));
        QVERIFY(nextBar->isVisible());
        // The last one goes back to the prompt.
        QTest::keyClick(window, Qt::Key_Delete);
        QTRY_VERIFY(trash->property("opened").toBool());
        QTest::keyClick(window, Qt::Key_Return);
        QTRY_COMPARE(backend.history()->count(), 0);
        qputenv("HOME", home);
        QVERIFY(QDir(dir.path() + "/.qttest/share/Trash/files").exists());
        // The prompt is back, and takes the keyboard.
        QTRY_VERIFY(prompt->isVisible());
        QTest::keyClick(window, Qt::Key_A);
        QTRY_COMPARE(prompt->property("text").toString(), QString("a"));

        QVERIFY2(warnings.isEmpty(), qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }
};

QTEST_MAIN(FantasiTests)
#include "fantasi_tests.moc"

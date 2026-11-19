#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QTemporaryDir>
#include <QtTest>

#include "backend.h"
#include "figures.h"
#include "sculptgeometry.h"
#include "surfacetexture.h"
#include <QQuick3D>
#include <algorithm>
#include <functional>
#include <map>
#include <utility>
#include <cstring>
#include <cmath>
#include <limits>
#include <QJsonArray>
#include <QVector3D>
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

} // namespace

class CheckmateTests : public QObject {
    Q_OBJECT

private slots:
    void init() { QTest::failOnWarning(); }

    void initTestCase() { QSurfaceFormat::setDefaultFormat(QQuick3D::idealSurfaceFormat()); QQuickStyle::setStyle("Material"); qmlRegisterType<SculptGeometry>("Checkmate",1,0,"SculptGeometry"); qmlRegisterType<SurfaceTexture>("Checkmate",1,0,"SurfaceTexture"); }

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

    void initialMoveTree() {
        const auto p = Chess::Position::initial();
        QCOMPARE(Chess::perft(p,1), uint64_t(20));
        QCOMPARE(Chess::perft(p,2), uint64_t(400));
        QCOMPARE(Chess::perft(p,3), uint64_t(8902));
        QCOMPARE(Chess::perft(p,4), uint64_t(197281));
    }

    void fenCountersCannotOverflow() {
        auto p=Chess::Position::fromFen("4k3/8/8/8/8/8/8/4K3 b - - 2147483647 2147483647");
        auto legal=p.legal();
        QVERIFY(!legal.empty());
        auto next=p.after(legal.front());
        QCOMPARE(next.halfmove,std::numeric_limits<int>::max());
        QCOMPARE(next.fullmove,std::numeric_limits<int>::max());
    }

    void fenDescribesAPositionThatCouldArise() {
        // The side that just moved cannot be in check, and nothing follows the sixth field.
        QVERIFY_THROWS_EXCEPTION(std::invalid_argument,Chess::Position::fromFen("4k3/8/8/8/8/8/4R3/4K3 w - - 0 1"));
        QVERIFY_THROWS_EXCEPTION(std::invalid_argument,Chess::Position::fromFen("4k3/8/8/8/8/8/8/4K3 w - - 0 1 extra"));
        QVERIFY(Chess::Position::fromFen("4k3/8/8/8/8/8/4R3/4K3 b - - 0 1").check(false));
        // A right to castle needs its king and rook at home.
        QCOMPARE(Chess::Position::fromFen("4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1").castle,0);
        QCOMPARE(Chess::Position::fromFen("r3k3/8/8/8/8/8/8/4K2R w KQkq - 0 1").castle,1|8);
        QCOMPARE(Chess::Position::fromFen("4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1").fen(),std::string("4k3/8/8/8/8/8/8/4K3 w - - 0 1"));
        // An en passant square is empty, with the pawn that passed it standing just beyond.
        QVERIFY_THROWS_EXCEPTION(std::invalid_argument,Chess::Position::fromFen("4k3/8/3b4/3pP3/8/8/8/4K3 w - d6 0 1"));
        QVERIFY_THROWS_EXCEPTION(std::invalid_argument,Chess::Position::fromFen("4k3/8/8/4P3/8/8/8/4K3 w - d6 0 1"));
        const auto passing=Chess::Position::fromFen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1");
        QCOMPARE(passing.after({36,43}).board[35].kind,int(Chess::Empty));
    }

    void theComputerKnowsHowAGameEnds() {
        const auto never=std::make_shared<std::atomic_bool>(false);
        // A mate on the last move the fifty-move rule allows is still a mate.
        const auto lastChance=Chess::Position::fromFen("7k/8/5KQ1/8/8/8/8/8 w - - 99 1");
        for (int level : {1,2}) {
            const auto next=lastChance.after(Chess::bestMove(lastChance,level,never));
            QVERIFY(next.check(false) && next.legal().empty());
        }
        // Taking the rook with the queen is stalemate, and a won game thrown away.
        const auto trap=Chess::Position::fromFen("7k/Q4r2/6K1/8/8/8/8/8 w - - 0 1");
        QVERIFY(trap.after({48,53}).legal().empty() && !trap.after({48,53}).check(false));
        for (int level : {0,1,2}) for (int again=0;again<5;++again) {
            const auto next=trap.after(Chess::bestMove(trap,level,never));
            QVERIFY(next.check(false) || !next.legal().empty());
        }
        // Losing, with a third repetition one step away, every level takes the draw.
        std::vector<Chess::Position> history{Chess::Position::fromFen("7k/8/5K2/8/8/8/8/1Q6 w - - 0 1")};
        for (const auto &move : std::vector<Chess::Move>{{1,9},{63,62},{9,1},{62,63},{1,9},{63,62},{9,1}}) history.push_back(history.back().after(move));
        for (int level : {0,1,2}) {
            const auto reply=Chess::bestMove(history.back(),level,never,history);
            QCOMPARE(reply,(Chess::Move{62,63}));
            QCOMPARE(history.back().after(reply).key(),history.front().key());
        }
    }

    void specialMoveTrees() {
        const auto castle = Chess::Position::fromFen("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1");
        QCOMPARE(Chess::perft(castle,1), uint64_t(48));
        QCOMPARE(Chess::perft(castle,2), uint64_t(2039));
        QCOMPARE(Chess::perft(castle,3), uint64_t(97862));
        const auto ep = Chess::Position::fromFen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1");
        QCOMPARE(Chess::perft(ep,3), uint64_t(2812));
        const auto promotion = Chess::Position::fromFen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1");
        QCOMPARE(Chess::perft(promotion,3), uint64_t(9467));
    }

    void mateAndUndo() {
        Backend game(":memory:");
        game.newGame(false,0);
        QVERIFY(game.move(13,21));
        QVERIFY(game.move(52,36));
        QVERIFY(game.move(14,30));
        QVERIFY(game.move(59,31));
        QCOMPARE(game.outcome(),QString("black-wins"));
        // The ring under a king in check knows where that king stands.
        QCOMPARE(game.checkSquare(),4);
        QCOMPARE(game.moves().last(),QString("Qh4#"));
        QVERIFY(!game.move(12,20));
        game.undo();
        QVERIFY(!game.finished());
        QCOMPARE(game.moves().size(),3);
        QCOMPARE(game.checkSquare(),-1);
    }

    void enPassantAndCastling() {
        auto p = Chess::Position::fromFen("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1");
        auto next = p.after({36,43});
        QCOMPARE(next.board[35].kind,int(Chess::Empty));
        QCOMPARE(next.board[43].kind,int(Chess::Pawn));
        QCOMPARE(p.san({36,43}),std::string("exd6"));
        auto castle = Chess::Position::fromFen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
        auto castled = castle.after({4,6});
        QCOMPARE(castled.board[5].kind,int(Chess::Rook));
        QCOMPARE(castled.board[6].kind,int(Chess::King));
        QCOMPARE(castled.castle,12);
        QCOMPARE(castle.san({4,6}),std::string("O-O"));
        const auto pinned = Chess::Position::fromFen("4r1k1/8/8/3pP3/8/8/8/4K3 w - d6 0 1");
        const auto legal = pinned.legal();
        QVERIFY(std::find(legal.begin(),legal.end(),Chess::Move{36,43}) == legal.end());
    }

    void promotionAndDraws() {
        auto p = Chess::Position::fromFen("4k3/P7/8/8/8/8/8/4K3 w - - 0 1");
        int promotions=0;
        for (auto m : p.legal()) if (m.from == 48 && m.to == 56) ++promotions;
        QCOMPARE(promotions,4);
        QCOMPARE(p.after({48,56,Chess::Knight}).board[56].kind,int(Chess::Knight));
        QVERIFY(Chess::Position::fromFen("4k3/8/8/8/8/8/8/4KB2 w - - 0 1").insufficient());
        QVERIFY(!Chess::Position::fromFen("4k3/8/8/8/8/8/8/4KBN1 w - - 0 1").insufficient());
        auto stale = Chess::Position::fromFen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1");
        QVERIFY(stale.legal().empty());
        QVERIFY(!stale.check(false));
        Backend game(":memory:");
        game.newGame(false,0);
        for (int i=0;i<2;++i) {
            QVERIFY(game.move(6,21)); QVERIFY(game.move(62,45));
            QVERIFY(game.move(21,6)); QVERIFY(game.move(45,62));
        }
        QCOMPARE(game.outcome(),QString("repetition"));
    }

    void saveAndResume() {
        QTemporaryDir dir;
        QString fen;
        {
            Backend game(dir.filePath("game.json"));
            game.newGame(false,1);
            QVERIFY(game.move(12,28));
            QVERIFY(game.move(52,36));
            game.setPieceSet(3); game.setReducedMotion(true); game.setMovesOpen(true);
            fen = game.fen();
        }
        Backend restored(dir.filePath("game.json"));
        QCOMPARE(restored.fen(),fen);
        QCOMPARE(restored.moves(),QStringList({"e4","e5"}));
        QCOMPARE(restored.pieceSet(),3);
        // Stilled motion is a test's switch, not a preference, so it does not come back with the game.
        QVERIFY(!restored.reducedMotion());
        QVERIFY(restored.movesOpen());
        QVERIFY(!Backend(dir.filePath("fresh.json")).movesOpen());
        restored.undo();
        QCOMPARE(restored.moves().size(),1);
    }

    void saveHasOneOwner() {
        QTemporaryDir dir;
        const QString path=dir.filePath("game.json");
        Backend owner(path);
        owner.newGame(false,0);
        QVERIFY(owner.move(12,28));
        QFile original(path); QVERIFY(original.open(QIODevice::ReadOnly));
        const auto bytes=original.readAll(); original.close();
        Backend other(path);
        QVERIFY(!other.ownsSave());
        QVERIFY(!other.error().isEmpty());
        QVERIFY(other.move(12,28));
        other.newGame(false,1); other.setPieceSet(3);
        // It may start afresh, unsaved, and goes on saying why.
        QVERIFY(other.moves().isEmpty());
        QVERIFY(!other.error().isEmpty());
        QVERIFY(!other.saveHealthy());
        QVERIFY(other.saveContended());
        QVERIFY(original.open(QIODevice::ReadOnly));
        QCOMPARE(original.readAll(),bytes);
    }

    void damagedSaveSurvivesPreferences() {
        QTemporaryDir dir;
        const QString path=dir.filePath("game.json");
        QVERIFY(write(path,"{broken"));
        Backend game(path);
        QVERIFY(!game.error().isEmpty());
        game.setPieceSet(2);
        game.setReducedMotion(true);
        QFile file(path); QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(file.readAll(),QByteArray("{broken")); file.close();
        game.newGame(false,0);
        QVERIFY(game.error().isEmpty());
        QVERIFY(file.open(QIODevice::ReadOnly));
        QVERIFY(QJsonDocument::fromJson(file.readAll()).isObject());
    }

    void failedSavePreservesPreviousGame() {
        QTemporaryDir dir;
        const QString path=dir.filePath("game.json");
        Backend game(path); game.newGame(false,0);
        QFile file(path); QVERIFY(file.open(QIODevice::ReadOnly));
        const auto bytes=file.readAll(); file.close();
        QVERIFY(QFile::setPermissions(dir.path(),QFile::ReadOwner|QFile::ExeOwner));
        const bool moved=game.move(12,28);
        QVERIFY(QFile::setPermissions(dir.path(),QFile::ReadOwner|QFile::WriteOwner|QFile::ExeOwner));
        QVERIFY(moved); QVERIFY(!game.saveHealthy());
        QVERIFY(!game.error().isEmpty());
        game.dismissError(); QVERIFY(!game.saveHealthy());
        QVERIFY(file.open(QIODevice::ReadOnly)); QCOMPARE(file.readAll(),bytes); file.close();
        QVERIFY(game.move(52,36)); QVERIFY(game.saveHealthy());
        QVERIFY(file.open(QIODevice::ReadOnly));
        QCOMPARE(QJsonDocument::fromJson(file.readAll()).object()["moves"].toArray().size(),2);
    }

    void restoreRejectsMovesAfterDraw() {
        QTemporaryDir dir;
        QJsonArray moves;
        for (int i=0;i<2;++i) {
            moves.append(QJsonArray{6,21,0}); moves.append(QJsonArray{62,45,0});
            moves.append(QJsonArray{21,6,0}); moves.append(QJsonArray{45,62,0});
        }
        moves.append(QJsonArray{12,28,0});
        QJsonDocument data(QJsonObject{{"version",1},{"moves",moves}});
        QVERIFY(write(dir.filePath("game.json"),data.toJson()));
        Backend game(dir.filePath("game.json"));
        QVERIFY(!game.error().isEmpty());
        QVERIFY(game.moves().isEmpty());
    }

    void repetitionKeysIncludeOnlyLegalEnPassant() {
        auto p=Chess::Position::fromFen("4r1k1/8/8/3pP3/8/8/8/4K3 w - d6 0 1");
        auto noEp=p; noEp.ep=-1;
        QCOMPARE(p.key(),noEp.key());
        p=Chess::Position::fromFen("6k1/8/8/3pP3/8/8/8/4K3 w - d6 0 1");
        noEp=p; noEp.ep=-1;
        QVERIFY(p.key()!=noEp.key());
        auto rights=Chess::Position::initial();
        auto lost=rights; lost.castle=0;
        QVERIFY(rights.key()!=lost.key());
    }

    void secondLaunchWaitsForStartingOwner() {
        QTemporaryDir dir;
        Backend owner(dir.filePath("checkmate/game.json"));
        owner.newGame(false,0);
        QProcessEnvironment environment=QProcessEnvironment::systemEnvironment();
        environment.insert("XDG_DATA_HOME",dir.path());
        environment.insert("XDG_RUNTIME_DIR",dir.path());
        QLocalServer server;
        QTimer::singleShot(600,&server,[&] { server.listen(dir.filePath("checkmate.sock")); });
        QProcess second;
        second.setProcessEnvironment(environment);
        second.start(QCoreApplication::applicationDirPath()+"/checkmate",{"open"});
        QTRY_COMPARE_WITH_TIMEOUT(second.state(),QProcess::NotRunning,4000);
        QCOMPARE(second.exitCode(),0);
        QVERIFY(server.hasPendingConnections());
    }

    void aSaveOutOfReachStillOpensAWindow() {
        // Another process holds the save and never answers the socket. The launch waits its two seconds for one
        // that is still starting, then opens a window that says the game is not being saved, rather than giving up unseen.
        QTemporaryDir dir;
        Backend owner(dir.filePath("checkmate/game.json"));
        owner.newGame(false,0);
        QProcessEnvironment environment=QProcessEnvironment::systemEnvironment();
        environment.insert("XDG_DATA_HOME",dir.path());
        environment.insert("XDG_RUNTIME_DIR",dir.path());
        QProcess second;
        second.setProcessEnvironment(environment);
        second.start(QCoreApplication::applicationDirPath()+"/checkmate",{"open"});
        QVERIFY(second.waitForStarted());
        // Listening on the socket is the last thing done before the window is loaded.
        QTRY_VERIFY_WITH_TIMEOUT(QFile::exists(dir.filePath("checkmate.sock")),15000);
        const bool stillOpen=second.state()==QProcess::Running;
        // What it says arrives in its own time, so it is gathered until the reason has come through.
        QByteArray said;
        QTRY_VERIFY_WITH_TIMEOUT((said+=second.readAllStandardError()).contains("owns this saved game") || second.state()!=QProcess::Running,5000);
        second.kill();
        QVERIFY(second.waitForFinished());
        QVERIFY(stillOpen);
        QVERIFY2(said.contains("owns this saved game"),said.constData());
    }

    void headlessCommandsReadSavedGames() {
        QTemporaryDir dir;
        Backend game(dir.filePath("checkmate/game.json"));
        game.newGame(false,0);
        QVERIFY(game.move(12,28)); QVERIFY(game.move(52,36));
        QProcessEnvironment environment=QProcessEnvironment::systemEnvironment();
        environment.remove("DISPLAY"); environment.remove("WAYLAND_DISPLAY");
        environment.insert("XDG_DATA_HOME",dir.path());
        QProcess process;
        process.setProcessEnvironment(environment);
        const QString binary=QCoreApplication::applicationDirPath()+"/checkmate";
        process.start(binary,{"inspect","--json"});
        QVERIFY(process.waitForFinished()); QCOMPARE(process.exitCode(),0);
        auto inspected=QJsonDocument::fromJson(process.readAllStandardOutput()).object();
        QCOMPARE(inspected["fen"].toString(),game.fen());
        QCOMPARE(inspected["moves"].toArray().size(),2);
        process.start(binary,{"export","--json"});
        QVERIFY(process.waitForFinished()); QCOMPARE(process.exitCode(),0);
        QVERIFY(QJsonDocument::fromJson(process.readAllStandardOutput()).object()["pgn"].toString().contains("1. e4 e5 *"));
        process.start(binary,{"legal","--json"});
        QVERIFY(process.waitForFinished()); QCOMPARE(process.exitCode(),0);
        QCOMPARE(QJsonDocument::fromJson(process.readAllStandardOutput()).object()["moves"].toArray().size(),20);
        process.start(binary,{"legal","invalid","--json"});
        QVERIFY(process.waitForFinished()); QCOMPARE(process.exitCode(),1);
        QVERIFY(!process.readAllStandardError().isEmpty());
    }

    void computerMovesAndCancels() {
        Backend game(":memory:");
        game.newGame(true,0);
        QVERIFY(game.move(12,28));
        QTRY_COMPARE_WITH_TIMEOUT(game.moves().size(),2,5000);
        QVERIFY(game.whiteTurn());
        game.undo();
        QCOMPARE(game.moves().size(),0);
        game.newGame(true,2,false);
        QVERIFY(game.thinking());
        game.newGame(false,0);
        QTest::qWait(200);
        QCOMPARE(game.moves().size(),0);
        QVERIFY(!game.thinking());
        const auto p = Chess::Position::fromFen("7k/8/5KQ1/8/8/8/8/8 w - - 0 1");
        auto move = Chess::bestMove(p,1,std::make_shared<std::atomic_bool>(false));
        auto next = p.after(move);
        QVERIFY(next.check(false));
        QVERIFY(next.legal().empty());
    }

    void everyPieceOfAKindWearsOneGeometry() {
        Sculptures sculptures;
        auto *pawn=sculptures.geometry(0,1,0,0);
        QVERIFY(pawn);
        QVERIFY(!pawn->vertexData().isEmpty());
        // Asked for again, it is the same object, so the GPU holds one mesh however many pieces wear it.
        QCOMPARE(sculptures.geometry(0,1,0,0),pawn);
        // Only Moss & Myth paints its two sides differently.
        QCOMPARE(sculptures.geometry(0,1,0,1),pawn);
        QVERIFY(sculptures.geometry(2,1,0,1)!=sculptures.geometry(2,1,0,0));
        QVERIFY(sculptures.geometry(0,2,0,0)!=pawn);
        QVERIFY(sculptures.geometry(1,1,0,0)!=pawn);
    }

    void sculptedSurfacesFaceTheirNormals() {
        SculptGeometry geometry;
        for(int design=0;design<4;++design) for(int kind=1;kind<=6;++kind) for(int part=0;part<6;++part) {
            geometry.setDesign(design); geometry.setKind(kind); geometry.setPart(part);
            const auto data=geometry.vertexData(),indices=geometry.indexData();
            const int stride=geometry.stride();
            QVERIFY(stride>=int(6*sizeof(float)));
            // Carved figures share vertices through an index buffer; every other part lists its triangles outright.
            const qsizetype corners=indices.isEmpty() ? data.size()/stride : indices.size()/qsizetype(sizeof(quint32));
            for(qsizetype first=0;first+3<=corners;first+=3) {
                QVector3D positions[3],normals[3];
                for(int vertex=0;vertex<3;++vertex) {
                    quint32 index=quint32(first+vertex);
                    if(!indices.isEmpty()) std::memcpy(&index,indices.constData()+(first+vertex)*qsizetype(sizeof(quint32)),sizeof(index));
                    QVERIFY((qsizetype(index)+1)*stride<=data.size());
                    float values[6]; std::memcpy(values,data.constData()+qsizetype(index)*stride,sizeof(values));
                    for(float value:values) QVERIFY(std::isfinite(value));
                    positions[vertex]={values[0],values[1],values[2]};
                    normals[vertex]={values[3],values[4],values[5]};
                    for(int axis=0;axis<3;++axis) {
                        QVERIFY(positions[vertex][axis]>=geometry.boundsMin()[axis]-.00001f);
                        QVERIFY(positions[vertex][axis]<=geometry.boundsMax()[axis]+.00001f);
                    }
                }
                const auto face=QVector3D::crossProduct(positions[1]-positions[0],positions[2]-positions[0]);
                QVERIFY(QVector3D::dotProduct(face,normals[0]+normals[1]+normals[2])>=-.000001f);
                if(face.lengthSquared()>1e-12f) for(const auto &normal:normals) QVERIFY(normal.lengthSquared()>.9f);
            }
        }
    }

    void woodlandFiguresAreClosedPaintedCarvings() {
        SculptGeometry geometry;
        geometry.setDesign(2);
        for(int kind=1;kind<=6;++kind) for(int tone=0;tone<2;++tone) {
            geometry.setKind(kind); geometry.setTone(tone); geometry.setPart(0);
            const auto data=geometry.vertexData(),indices=geometry.indexData();
            const int stride=geometry.stride();
            QCOMPARE(stride,int(12*sizeof(float)));
            const qsizetype corners=indices.size()/qsizetype(sizeof(quint32));
            QVERIFY(corners>9000 && corners%3==0);
            // Every edge is shared by an even number of triangles, so a figure has no open seams.
            std::map<std::pair<quint32,quint32>,int> edges;
            for(qsizetype first=0;first<corners;first+=3) {
                quint32 corner[3]; std::memcpy(corner,indices.constData()+first*qsizetype(sizeof(quint32)),sizeof(corner));
                for(int side=0;side<3;++side) {
                    const quint32 from=corner[side],to=corner[(side+1)%3];
                    QVERIFY((qsizetype(from)+1)*stride<=data.size());
                    ++edges[{std::min(from,to),std::max(from,to)}];
                }
            }
            for(const auto &edge:edges) QVERIFY(edge.second%2==0);
            for(qsizetype offset=0;offset+stride<=data.size();offset+=stride) {
                float paint[4]; std::memcpy(paint,data.constData()+offset+8*qsizetype(sizeof(float)),sizeof(paint));
                for(float channel:paint) QVERIFY(channel>=0 && channel<=1);
            }
            // A figure stands on its own square, and is no taller than the king's antlers.
            QVERIFY(geometry.boundsMin().y()>-.05f && geometry.boundsMax().y()>.9f && geometry.boundsMax().y()<2.3f);
            QVERIFY(geometry.boundsMin().x()>-.55f && geometry.boundsMax().x()<.55f);
            QVERIFY(geometry.boundsMin().z()>-.55f && geometry.boundsMax().z()<.55f);
        }
    }

    void castSetsAreClosedSolidsWithARoyalSilhouette() {
        SculptGeometry geometry;
        for(int design:{0,1,3}) {
            float height[7]={};
            for(int kind=1;kind<=6;++kind) for(int part=0;part<4;++part) {
                geometry.setDesign(design); geometry.setKind(kind); geometry.setPart(part);
                const auto data=geometry.vertexData(),indices=geometry.indexData();
                const int stride=geometry.stride();
                QCOMPARE(stride,int(12*sizeof(float)));
                const qsizetype corners=indices.size()/qsizetype(sizeof(quint32));
                // Every piece has a sculpted body; metalwork, inlay and a second colour only where the design calls for them.
                if(part==0) QVERIFY(corners>6000);
                if(corners==0) continue;
                QVERIFY(corners%3==0);
                // Each part is cast as closed solids: every edge is shared by an even number of triangles.
                std::map<std::pair<quint32,quint32>,int> edges;
                for(qsizetype first=0;first<corners;first+=3) {
                    quint32 corner[3]; std::memcpy(corner,indices.constData()+first*qsizetype(sizeof(quint32)),sizeof(corner));
                    for(int side=0;side<3;++side) {
                        const quint32 from=corner[side],to=corner[(side+1)%3];
                        QVERIFY((qsizetype(from)+1)*stride<=data.size());
                        ++edges[{std::min(from,to),std::max(from,to)}];
                    }
                }
                for(const auto &edge:edges) QVERIFY(edge.second%2==0);
                // Recesses are shaded, never blacked out or brightened.
                for(qsizetype offset=0;offset+stride<=data.size();offset+=stride) {
                    float shade[4]; std::memcpy(shade,data.constData()+offset+8*qsizetype(sizeof(float)),sizeof(shade));
                    for(float channel:shade) QVERIFY(channel>=.3f && channel<=1);
                }
                // A piece stands on its own square, low enough to see and click the rank behind it.
                QVERIFY(geometry.boundsMin().y()>-.05f && geometry.boundsMax().y()<1.9f);
                QVERIFY(geometry.boundsMin().x()>-.5f && geometry.boundsMax().x()<.5f);
                QVERIFY(geometry.boundsMin().z()>-.5f && geometry.boundsMax().z()<.5f);
                height[kind]=std::max(height[kind],geometry.boundsMax().y());
            }
            // Rank reads from the silhouette: pawns lowest, the queen above her officers, the king above all.
            for(int kind=2;kind<=6;++kind) QVERIFY(height[1]<height[kind]);
            for(int kind=2;kind<=4;++kind) QVERIFY(height[kind]<height[5]);
            QVERIFY(height[5]<height[6]);
        }
    }

    void tautOutlinesThrowNoLip() {
        // The brass shoe's own outline: a long flat sole running into a short chamfer.
        const std::initializer_list<std::pair<float,float>> shoe{{0,-.022f},{.346f,-.022f},{.361f,-.012f},{.365f,.005f},{.365f,.05f},{.359f,.066f},{.34f,.075f},{0,.075f}};
        // Left loose, the spline swings past its widest knot into a lip thinner than any cell; drawn taut it cannot.
        QVERIFY(Clay::Lathe(shoe).reach>.372f);
        QVERIFY(Clay::Lathe(shoe,true).reach<.367f);
    }

    void atelierBrassFollowsItsMoulds() {
        for(int kind=1;kind<=6;++kind) {
            const auto moulds=Atelier::moulds(kind,1);
            const SculptFigure figure=Figures::part(1,kind,1);
            QVERIFY(!figure.indices.empty() && figure.indices.size()%3==0);
            // Turned shoes and rings hold to their mould all the way round, with no teeth cut across a rim.
            // The king's cross is carved, and may ease its arrises by a little more.
            const float allowed=kind==6 ? .0015f : .0008f;
            float worst=0;
            for(size_t first=0;first<figure.indices.size();first+=3) {
                QVector3D middle;
                for(int corner=0;corner<3;++corner) middle+=figure.vertices[figure.indices[first+corner]].position/3;
                float distance=1e9f;
                for(const auto &mould:moulds) distance=std::min(distance,mould.field({middle.x(),middle.y(),middle.z()}));
                worst=std::max(worst,std::abs(distance));
            }
            QVERIFY2(worst<allowed,qPrintable(QString("kind %1 strays %2 from its mould").arg(kind).arg(worst)));
        }
    }

    void orbitalDecksRunTrueAllRound() {
        const float rank[]={0,.82f,.95f,.92f,.98f,1,1};
        for(int kind=1;kind<=6;++kind) {
            const auto moulds=Orbital::moulds(kind,0);
            const SculptFigure figure=Figures::part(0,kind,0);
            QVERIFY(!figure.indices.empty() && figure.indices.size()%3==0);
            // The deck's rounded rim is finer than any grid cell; turned, it holds to its mould with no wobble.
            float worst=0;
            for(size_t first=0;first<figure.indices.size();first+=3) {
                QVector3D middle;
                for(int corner=0;corner<3;++corner) middle+=figure.vertices[figure.indices[first+corner]].position/3;
                if(std::hypot(middle.x(),middle.z())<.29f*rank[kind]) continue;
                // Only the deck is judged here; a carved hull may reach out over it.
                const Clay::P at{middle.x(),middle.y(),middle.z()};
                const float deck=std::abs(moulds.front().field(at));
                bool carved=false;
                for(size_t other=1;other<moulds.size();++other) carved=carved || std::abs(moulds[other].field(at))<deck;
                if(!carved) worst=std::max(worst,deck);
            }
            QVERIFY2(worst<.0008f,qPrintable(QString("kind %1's deck strays %2 from its mould").arg(kind).arg(worst)));
        }
    }

    void turnedCapsKeepDirectionalContactShading() {
        const SculptFigure king=Figures::part(1,6,0);
        std::map<float,std::pair<float,float>> rings;
        for(const auto &vertex:king.vertices) {
            if(vertex.position.y()<1.25f) continue;
            const float shade=vertex.color.x();
            auto [ring,inserted]=rings.try_emplace(vertex.position.y(),shade,shade);
            if(!inserted) {
                ring->second.first=std::min(ring->second.first,shade);
                ring->second.second=std::max(ring->second.second,shade);
            }
        }
        float variation=0;
        for(const auto &ring:rings) variation=std::max(variation,ring.second.second-ring.second.first);
        // The flat cross shades the cap differently along its arms and across its thickness.
        QVERIFY(variation>.01f);
    }

    void piecesComeBackWithTheirSet() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        Theme theme(dir.path());
        Backend backend(":memory:");
        backend.newGame(false,0);
        backend.setReducedMotion(true);
        Sculptures sculptures;
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("translator",&translator);
        engine.rootContext()->setContextProperty("theme",&theme);
        engine.rootContext()->setContextProperty("backend",&backend);
        engine.rootContext()->setContextProperty("sculptures",&sculptures);
        engine.load(QUrl("qrc:/Main.qml"));
        QVERIFY(!engine.rootObjects().isEmpty());
        auto *window=qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window && QTest::qWaitForWindowExposed(window));
        // How much of the frame differs from the bare board: an empty board has nothing standing on it.
        QTest::qWait(400);
        const QImage first=window->grabWindow();
        auto differs=[&](const QImage &other) {
            qint64 changed=0;
            for (int y=0;y<first.height();y+=4) for (int x=0;x<first.width();x+=4) {
                const QColor a=first.pixelColor(x,y),b=other.pixelColor(x,y);
                if (std::abs(a.red()-b.red())+std::abs(a.green()-b.green())+std::abs(a.blue()-b.blue())>30) ++changed;
            }
            return double(changed)/((first.width()/4)*(first.height()/4));
        };
        // Every set in turn and back to the first: its pieces stand where they stood.
        for (int set : {1,2,3,0}) { backend.setPieceSet(set); QTest::qWait(400); }
        const double away=differs(window->grabWindow());
        QVERIFY2(away<.01,qPrintable(QString("%1 of the frame changed after a round of sets").arg(away)));
    }

    void windowLoadsAndAnswersTheKeyboard() {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language");
        QCoreApplication::installTranslator(&translator);
        Theme theme(dir.path());
        Backend backend(":memory:");
        backend.newGame(false,0);
        backend.setReducedMotion(true);
        // Declared before the engine, so it is still there while the scene that borrows from it is torn down.
        Sculptures sculptures;
        QQmlApplicationEngine engine;
        QStringList warnings;
        connect(&engine,&QQmlEngine::warnings,this,[&](const QList<QQmlError> &errors) {
            for (const auto &error : errors) warnings << error.toString();
        });
        engine.rootContext()->setContextProperty("translator",&translator);
        engine.rootContext()->setContextProperty("theme",&theme);
        engine.rootContext()->setContextProperty("backend",&backend);
        engine.rootContext()->setContextProperty("sculptures",&sculptures);
        engine.load(QUrl("qrc:/Main.qml"));
        QVERIFY2(!engine.rootObjects().isEmpty(),qPrintable(warnings.join('\n')));
        auto *window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        window->requestActivate();
        QVERIFY(QTest::qWaitForWindowActive(window));
        QTest::keyClick(window,Qt::Key_Space);
        QCOMPARE(backend.selected(),12);
        QTest::keyClick(window,Qt::Key_Up);
        QTest::keyClick(window,Qt::Key_Up);
        QTest::keyClick(window,Qt::Key_Space);
        QCOMPARE(backend.moves(),QStringList{"e4"});
        QTest::keyClick(window,Qt::Key_Z,Qt::ControlModifier);
        QVERIFY(backend.moves().isEmpty());
        for (int set = 0; set < 4; ++set) {
            backend.setPieceSet(set);
            QTest::qWait(80);
        }
        QTest::keyClick(window,'?');
        auto *help = window->findChild<QObject *>("help");
        QTRY_VERIFY(help->property("opened").toBool());
        QTest::keyClick(window,Qt::Key_Escape);
        QTRY_VERIFY(!help->property("visible").toBool());
        QTest::keyClick(window,Qt::Key_N);
        auto *dialog = window->findChild<QObject *>("newGameDialog");
        QTRY_VERIFY(dialog->property("opened").toBool());
        QTest::keyClick(window,Qt::Key_Escape);
        QTRY_VERIFY(!dialog->property("visible").toBool());
        auto *board=window->findChild<QQuickItem *>("board");
        QVERIFY(board);
        {
            // A narrow window pulls the camera back until the whole frame is in view.
            const QSize original=window->size();
            auto *view=window->findChild<QObject *>("scene");
            QVERIFY(view);
            for (const QSize size : {QSize(1280,850),QSize(760,1240)}) {
                window->resize(size);
                QTest::qWait(150);
                for (int set=0;set<4;++set) {
                    backend.setPieceSet(set);
                    // The view answers from the last frame it drew, and a slow renderer takes its time over one.
                    QString stray;
                    auto framed=[&] {
                        stray.clear();
                        for (float x : {-4.55f,4.55f}) for (float z : {-4.55f,4.55f}) {
                            QVector3D point;
                            if (!QMetaObject::invokeMethod(view,"mapFrom3DScene",Q_RETURN_ARG(QVector3D,point),Q_ARG(QVector3D,QVector3D(x,0,z)))) return false;
                            if (point.x()<0 || point.x()>board->width() || point.y()<0 || point.y()>board->height())
                                stray=QString("set %1 at %2x%3: corner %4,%5 lands at %6,%7").arg(set).arg(size.width()).arg(size.height())
                                          .arg(x).arg(z).arg(point.x()).arg(point.y());
                        }
                        return stray.isEmpty();
                    };
                    QTRY_VERIFY2_WITH_TIMEOUT(framed(),qPrintable(stray),10000);
                }
            }
            backend.setPieceSet(0);
            window->resize(original);
            QTest::qWait(100);
        }
        {
            // Everything that isn't the board is in one slim footer under it.
            auto *footer=window->findChild<QQuickItem *>("footer");
            QVERIFY(footer && footer->isVisible());
            QCOMPARE(footer->height(),42.0);
            QCOMPARE(board->width(),qreal(window->width()));
            QCOMPARE(board->height(),qreal(window->height())-42);
            // Delegates live only in the visual tree, so walk it rather than the object tree.
            std::function<QQuickItem *(QQuickItem *,const QString &)> find=[&](QQuickItem *item,const QString &name) -> QQuickItem * {
                if (item->objectName()==name) return item;
                for (auto *child : item->childItems()) if (auto *hit=find(child,name)) return hit;
                return nullptr;
            };
            auto press=[&](QQuickItem *item) { QTest::mouseClick(window,Qt::LeftButton,{},item->mapToScene(QPointF(item->width()/2,item->height()/2)).toPoint()); };
            for (const char *name : {"wordmark","set-0","set-3","movesButton","undoButton","newGameButton","status"}) {
                auto *control=find(window->contentItem(),name);
                QVERIFY2(control && control->isVisible(),name);
                const QPointF corner=control->mapToItem(footer,QPointF(0,0));
                QVERIFY2(corner.x()>=0 && corner.y()>=0 && corner.x()+control->width()<=footer->width() && corner.y()+control->height()<=footer->height(),name);
            }
            {
                // What the footer says keeps to the gap between its two groups of buttons, however little room there is.
                auto *say=window->findChild<QQuickItem *>("say");
                auto *lastSet=find(window->contentItem(),"set-3");
                auto *firstAction=find(window->contentItem(),"movesButton");
                QVERIFY(say && lastSet && firstAction);
                auto clear=[&] {
                    const qreal left=lastSet->mapToItem(footer,QPointF(lastSet->width(),0)).x(), right=firstAction->mapToItem(footer,QPointF(0,0)).x();
                    return say->x()>=left && say->x()+say->width()<=right;
                };
                QVERIFY(clear());
                // With room to spare it is dead centre.
                QVERIFY(qAbs(say->x()+say->width()/2-footer->width()/2)<1);
                const QSize wide=window->size();
                window->resize(window->minimumWidth(),wide.height());
                QTRY_COMPARE(footer->width(),qreal(window->minimumWidth()));
                QTRY_VERIFY(clear());
                // Squeezed far below anything it would be given, it shortens rather than spilling over the buttons.
                const qreal natural=say->implicitWidth();
                const qreal before=lastSet->mapToItem(footer,QPointF(lastSet->width(),0)).x(), after=footer->width()-firstAction->mapToItem(footer,QPointF(0,0)).x();
                footer->setWidth(before+after+32+natural*.6);
                QTRY_VERIFY(say->width()<natural);
                QVERIFY(clear());
                window->resize(wide);
                QTRY_COMPARE(footer->width(),qreal(wide.width()));
                QTRY_VERIFY(qAbs(say->x()+say->width()/2-footer->width()/2)<1);
            }
            // The four sets are picked from their signs.
            backend.setPieceSet(0);
            press(find(window->contentItem(),"set-3"));
            QCOMPARE(backend.pieceSet(),3);
            press(find(window->contentItem(),"set-0"));
            QCOMPARE(backend.pieceSet(),0);
            // The name opens the shortcuts, and the plus a new game.
            press(find(window->contentItem(),"wordmark"));
            QTRY_VERIFY(help->property("opened").toBool());
            QTest::keyClick(window,Qt::Key_Escape);
            QTRY_VERIFY(!help->property("visible").toBool());
            press(find(window->contentItem(),"newGameButton"));
            QTRY_VERIFY(dialog->property("opened").toBool());
            QTest::keyClick(window,Qt::Key_Escape);
            QTRY_VERIFY(!dialog->property("visible").toBool());
            // The moves stay out of the way until asked for, then lie over a corner of the board without moving it.
            auto *moves=window->findChild<QQuickItem *>("moves");
            QVERIFY(moves && !moves->isVisible());
            QVERIFY(!backend.movesOpen());
            press(find(window->contentItem(),"movesButton"));
            QVERIFY(backend.movesOpen());
            QTRY_VERIFY(moves->isVisible());
            QCOMPARE(board->width(),qreal(window->width()));
            const QPointF corner=moves->mapToItem(board,QPointF(0,0));
            QVERIFY(corner.x()>=0 && corner.y()>=0 && corner.x()+moves->width()<=board->width() && corner.y()+moves->height()<=board->height());
            // A press on the moves never reaches the board beneath them.
            backend.selectSquare(12);
            QCOMPARE(backend.selected(),12);
            press(moves);
            QCOMPARE(backend.selected(),12);
            QVERIFY(backend.moves().isEmpty());
            backend.cancelSelection();
            // B puts them away and brings them back.
            QTest::keyClick(window,Qt::Key_B);
            QVERIFY(!backend.movesOpen());
            QTRY_VERIFY(!moves->isVisible());
            QTest::keyClick(window,Qt::Key_B);
            QTRY_VERIFY(moves->isVisible());
            // Tab clears the footer and the moves away for a bare board, and brings them back.
            QTest::keyClick(window,Qt::Key_Tab);
            QTRY_VERIFY(!footer->isVisible());
            QVERIFY(!moves->isVisible());
            QVERIFY(backend.movesOpen());
            QTRY_COMPARE(board->height(),qreal(window->height()));
            QTest::keyClick(window,Qt::Key_Tab);
            QTRY_VERIFY(footer->isVisible());
            QVERIFY(moves->isVisible());
            QTRY_COMPARE(board->height(),qreal(window->height())-42);
            QTest::keyClick(window,Qt::Key_B);
            QVERIFY(!backend.movesOpen());
        }
        board->setProperty("cursorSquare",28);
        QTest::keyClick(window,Qt::Key_F);
        QTest::keyClick(window,Qt::Key_Right);
        QCOMPARE(board->property("cursorSquare").toInt(),27);
        QTest::keyClick(window,Qt::Key_R);

        // The board keeps its seat through a two-player game; only the player turns it.
        QVERIFY(backend.move(12,28));
        QCOMPARE(board->property("azimuth").toDouble(),0.0);
        board->setProperty("manualAzimuth",30.0);
        backend.selectSquare(52);
        QCOMPARE(board->property("azimuth").toDouble(),30.0);
        QTest::keyClick(window,Qt::Key_R);
        QCOMPARE(board->property("azimuth").toDouble(),0.0);
        backend.newGame(false,0);
        backend.setReducedMotion(false);
        QTest::qWait(450);
        auto *pawn=window->findChild<QObject *>("figure-20");
        QVERIFY(pawn);
        QVERIFY(backend.move(12,28));
        // A slow renderer may draw the whole journey in a frame or two, so nothing is sampled in mid-air:
        // the journey has started, it is aimed up the board, and it ends on the square.
        QVERIFY(pawn->findChild<QObject *>("leap")->property("running").toBool());
        QVERIFY(qAbs(pawn->property("leanZ").toDouble())>.9);
        QTRY_VERIFY_WITH_TIMEOUT(qFuzzyCompare(pawn->property("z").toFloat(),.5f),5000);
        backend.undo();
        // Quick 3D coordinates use float precision, including the final animation setter.
        QTRY_VERIFY_WITH_TIMEOUT(qFuzzyCompare(pawn->property("z").toFloat(),2.5f),8000);
        QTRY_COMPARE_WITH_TIMEOUT(pawn->property("lift").toDouble(),0.0,8000);
        auto *leap=pawn->findChild<QObject *>("leap");
        auto *perk=pawn->findChild<QObject *>("perk");
        QVERIFY(leap && perk);
        QVERIFY(backend.move(12,28));
        QVERIFY(leap->property("running").toBool());
        backend.setReducedMotion(true);
        QVERIFY(!leap->property("running").toBool());
        QCOMPARE(pawn->property("lift").toDouble(),0.0);
        QCOMPARE(pawn->property("z").toDouble(),.5);

        // Every set picks a piece up to its own height, carries it in an arc that leans into the journey, and settles it squarely.
        for (int set=0;set<4;++set) {
            backend.newGame(false,0);
            backend.setPieceSet(set);
            backend.setReducedMotion(false);
            QTRY_VERIFY(board->property("clock").toDouble()>0);
            backend.selectSquare(12);
            QVERIFY(perk->property("running").toBool());
            const double raised=std::vector<double>{.2,.14,.17,.17}[set];
            QTRY_VERIFY(qAbs(pawn->property("raise").toDouble()-raised)<.001);
            // A move made mid-shake, or a pick-up mid-skip, leaves nothing of the interrupted pose behind.
            pawn->setProperty("wiggle",8.0);
            pawn->setProperty("lift",.05);
            backend.selectSquare(12);
            backend.selectSquare(12);
            QTRY_COMPARE(pawn->property("lift").toDouble(),0.0);
            pawn->setProperty("wiggle",8.0);
            QVERIFY(backend.move(12,28));
            QVERIFY(leap->property("running").toBool());
            QVERIFY(qAbs(pawn->property("leanZ").toDouble())>.9);
            QVERIFY(leap->property("height").toDouble()>0);
            // A captured piece waits for its captor, then goes.
            QVERIFY(backend.move(51,35));
            auto *taken=window->findChild<QObject *>("figure-"+QString::number(backend.position().board[35].id));
            QVERIFY(taken);
            QVERIFY(backend.move(28,35));
            QCOMPARE(taken->property("presence").toDouble(),1.0);
            QTRY_COMPARE_WITH_TIMEOUT(taken->property("presence").toDouble(),0.0,8000);
            QTRY_VERIFY_WITH_TIMEOUT(!leap->property("running").toBool(),8000);
            QCOMPARE(pawn->property("lean").toDouble(),0.0);
            QCOMPARE(pawn->property("stretch").toDouble(),1.0);
            QCOMPARE(pawn->property("lift").toDouble(),0.0);
            QCOMPARE(pawn->property("wiggle").toDouble(),0.0);
            // A long capture is waited out: the taken piece is still whole when a short one would already have gone.
            QVERIFY(backend.move(59,35));
            auto *queen=window->findChild<QObject *>("figure-"+QString::number(backend.position().board[35].id));
            auto *far=window->findChild<QObject *>("figure-"+QString::number(backend.position().board[7].id));
            QVERIFY(queen && far);
            QVERIFY(backend.move(14,22));
            QVERIFY(backend.move(35,7));
            QVERIFY(far->property("reprieve").toInt()>taken->property("reprieve").toInt()+150);
            QCOMPARE(far->property("presence").toDouble(),1.0);
            // Changing sets mid-journey starts the new one from rest.
            backend.setPieceSet((set+1)%4);
            QVERIFY(!queen->findChild<QObject *>("leap")->property("running").toBool());
            QCOMPARE(queen->property("lean").toDouble(),0.0);
            backend.setReducedMotion(true);
            QCOMPARE(far->property("presence").toDouble(),0.0);
        }
        // Moss & Myth is alive: it breathes, perks up in the hand, draws its neighbours' eyes, and leaps.
        backend.newGame(false,0);
        backend.setPieceSet(2);
        backend.setReducedMotion(false);
        QTRY_VERIFY(board->property("clock").toDouble()>0);
        QTRY_VERIFY(qAbs(pawn->property("tall").toDouble()-1)>.002);
        auto *neighbour=window->findChild<QObject *>("figure-"+QString::number(backend.position().board[11].id));
        QVERIFY(neighbour);
        backend.selectSquare(12);
        QVERIFY(perk->property("running").toBool());
        QTRY_VERIFY(qAbs(pawn->property("raise").toDouble()-.17)<.001);
        QTRY_VERIFY(qAbs(neighbour->property("look").toDouble())>5);
        QVERIFY(backend.move(12,28));
        QVERIFY(leap->property("running").toBool());
        QVERIFY(qAbs(pawn->property("leanZ").toDouble())>.9);
        QVERIFY(leap->property("height").toDouble()>0);
        QTRY_VERIFY_WITH_TIMEOUT(!leap->property("running").toBool(),2000);
        QVERIFY(qFuzzyCompare(pawn->property("z").toFloat(),.5f));
        QCOMPARE(pawn->property("lean").toDouble(),0.0);
        QCOMPARE(pawn->property("stretch").toDouble(),1.0);
        QTRY_COMPARE(neighbour->property("look").toDouble(),0.0);
        // Reduced motion stills a leap in flight and every idle stir with it.
        backend.undo();
        QVERIFY(leap->property("running").toBool());
        backend.selectSquare(11);
        backend.setReducedMotion(true);
        QVERIFY(!leap->property("running").toBool());
        QCOMPARE(pawn->property("tall").toDouble(),1.0);
        QCOMPARE(pawn->property("look").toDouble(),0.0);
        QCOMPARE(pawn->property("z").toDouble(),2.5);
        QCOMPARE(pawn->property("y").toFloat(),.12f);
        QCOMPARE(neighbour->property("y").toFloat(),.29f);
        backend.setPieceSet(3);

        backend.newGame(false,0);
        QTest::qWait(100);
        auto *scene=window->findChild<QObject *>("scene");
        QVERIFY(scene);
        auto clickSquare = [&](int square) {
            QVector3D point;
            const QVector3D world(square%8-3.5f,backend.position().board[square].kind ? .7f : .12f,3.5f-square/8);
            const bool mapped=QMetaObject::invokeMethod(scene,"mapFrom3DScene",Q_RETURN_ARG(QVector3D,point),Q_ARG(QVector3D,world));
            if (!mapped) return false;
            const auto location=board->mapToScene(QPointF(point.x(),point.y()));
            QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,location.toPoint());
            return true;
        };
        for (int set=0;set<4;++set) {
            backend.newGame(false,0);
            backend.setPieceSet(set);
            QTest::qWait(150);
            QVERIFY(clickSquare(12));
            QCOMPARE(backend.selected(),12);
            QVERIFY(clickSquare(28));
            QCOMPARE(backend.moves(),QStringList{"e4"});
        }

        for (int promotion : {5,4,3,2}) {
            backend.newGame(false,0);
            for (const auto &move : std::vector<Chess::Move>{{8,24},{55,39},{24,32},{39,31},{32,40},{31,23},{40,49},{23,14}})
                QVERIFY(backend.move(move.from,move.to));
            QVERIFY(backend.move(49,56));
            auto *promotionDialog=window->findChild<QObject *>("promotionDialog");
            QTRY_VERIFY(promotionDialog->property("opened").toBool());
            const QString name="promotion-"+QString::number(promotion);
            std::function<QQuickItem *(QQuickItem *)> findVisual = [&](QQuickItem *item) -> QQuickItem * {
                if (item->objectName()==name) return item;
                for (auto child : item->childItems()) if (auto found=findVisual(child)) return found;
                return nullptr;
            };
            auto *button=findVisual(window->contentItem());
            QVERIFY(button);
            const auto point=button->mapToScene(QPointF(button->width()/2,button->height()/2));
            QTest::mouseClick(window,Qt::LeftButton,Qt::NoModifier,point.toPoint());
            QTRY_VERIFY(!backend.promotionPending());
            QCOMPARE(backend.position().board[56].kind,promotion);
            // The figure on the board becomes what the pawn was promoted to.
            auto *promoted=window->findChild<QObject *>("figure-"+QString::number(backend.position().board[56].id));
            QVERIFY(promoted);
            QTRY_COMPARE(promoted->property("shownKind").toInt(),promotion);
            QTRY_VERIFY(!promotionDialog->property("visible").toBool());
        }
        QVERIFY2(warnings.isEmpty(),qPrintable(warnings.join('\n')));
        QCoreApplication::removeTranslator(&translator);
    }
};

QTEST_MAIN(CheckmateTests)
#include "checkmate_tests.moc"

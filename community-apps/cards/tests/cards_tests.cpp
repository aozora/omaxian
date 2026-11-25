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
#include <QJsonArray>
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

using namespace Klondike;

// Every pile, card by card, with the hidden ones in lower case.
QString layout(const Game &game) {
    QString text;
    for (int pile = 0; pile < Piles; ++pile) {
        for (const Card &card : game.pile(pile)) text += QString::number(card.id) + (card.up ? "U " : "d ");
        text += "| ";
    }
    return text;
}

// The rules a position always keeps: fifty-two different cards, columns that
// run down in alternating colors once they show, foundations that run up in suit.
bool sound(const Game &game) {
    QSet<int> seen;
    int total = 0;
    for (int pile = 0; pile < Piles; ++pile) {
        const auto &cards = game.pile(pile);
        for (size_t i = 0; i < cards.size(); ++i) {
            seen << cards[i].id;
            ++total;
            if (cards[i].id < 0 || cards[i].id > 51) return false;
            if (pile == Stock && cards[i].up) return false;
            if (pile == Waste && !cards[i].up) return false;
            if (pile >= Foundation && pile < Tableau && (cards[i].suit() != pile - Foundation || cards[i].rank() != int(i) || !cards[i].up)) return false;
            if (pile >= Tableau && i > 0) {
                if (cards[i - 1].up && !cards[i].up) return false;
                if (cards[i - 1].up && (cards[i - 1].red() == cards[i].red() || cards[i - 1].rank() != cards[i].rank() + 1)) return false;
            }
            if (pile >= Tableau && i + 1 == cards.size() && !cards[i].up) return false;
        }
    }
    return seen.size() == 52 && total == 52;
}

// The first deal that the hints alone play to the end.
quint32 winnable() {
    static quint32 found = 0;
    for (quint32 seed = 1; !found && seed < 5000; ++seed) {
        Game game(seed);
        for (int step = 0; step < 1500 && !game.finishable() && !game.won(); ++step) {
            const auto hint = game.hint();
            if (!hint || !game.play(hint->from, hint->to, hint->count)) break;
        }
        if (game.finishable()) found = seed;
    }
    return found;
}

// The first deal whose opening hint moves a single card between two columns.
quint32 transferSeed() {
    static quint32 found = 0;
    for (quint32 seed = 1; !found && seed < 5000; ++seed) {
        const auto hint = Game(seed).hint();
        if (hint && hint->from >= Tableau && hint->to >= Tableau && hint->count == 1 && !Game(seed).pile(hint->to).empty()) found = seed;
    }
    return found;
}

// The first deal the hints play until they have nothing left to offer, short of winning.
quint32 stuckSeed() {
    static quint32 found = 0;
    for (quint32 seed = 1; !found && seed < 5000; ++seed) {
        Game game(seed);
        for (int step = 0; step < 3000; ++step) {
            const auto hint = game.hint();
            if (!hint) { if (!game.won()) found = seed; break; }
            if (!game.play(hint->from, hint->to, hint->count)) break;
            while (game.finishStep()) { }
        }
    }
    return found;
}

// What is in a file now, opened afresh, so a file replaced under the same name is seen.
QByteArray contents(const QString &path) {
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray("(unreadable)");
}

// A save file's text for a game as it stands.
QByteArray saved(const Game &game, const QByteArray &extraMoves = {}) {
    QByteArray moves;
    for (const Move &move : game.moves()) moves += QByteArray(moves.isEmpty() ? "" : ",") + "[" + QByteArray::number(move.from) + "," + QByteArray::number(move.to) + "," + QByteArray::number(move.count) + "]";
    return "{\"version\":1,\"seed\":" + QByteArray::number(game.seed()) + ",\"moves\":[" + moves + extraMoves + "]}";
}

// Follows the hints until nothing is hidden, then waits while the game plays itself out.
bool playOut(Backend &backend) {
    for (int step = 0; step < 2000 && !backend.won() && !backend.game().finishable(); ++step) {
        const Move move = *backend.game().hint();
        if (move.from == Stock || move.to == Stock) backend.draw();
        else if (!backend.drop(move.from, int(backend.game().pile(move.from).size()) - move.count, move.to)) return false;
    }
    return QTest::qWaitFor([&] { return backend.won(); }, 10000);
}

// Delegates live only in the visual tree, so walk it rather than the object tree.
QQuickItem *findItem(QQuickItem *root, const QString &name) {
    if (root->objectName() == name) return root;
    for (QQuickItem *child : root->childItems())
        if (QQuickItem *found = findItem(child, name)) return found;
    return nullptr;
}

// The real window over a real backend that saves nowhere, with a theme and a
// language read from a temp directory rather than the desktop's own.
struct Stage {
    Translator translator;
    Theme theme;
    Backend backend;
    QQmlApplicationEngine engine;
    QStringList warnings;
    QQuickWindow *window = nullptr;
    explicit Stage(const QString &directory, const QString &save = ":memory:") : translator(directory + "/language"), theme(directory), backend(save) {
        QCoreApplication::installTranslator(&translator);
        if (save == ":memory:") backend.newGame(9);
        QObject::connect(&engine, &QQmlEngine::warnings, &engine, [this](const QList<QQmlError> &errors) {
            for (const auto &error : errors) warnings << error.toString();
        });
        QObject::connect(&translator, &Translator::changed, &engine, &QQmlEngine::retranslate);
        engine.rootContext()->setContextProperty("translator", &translator);
        engine.rootContext()->setContextProperty("theme", &theme);
        engine.rootContext()->setContextProperty("backend", &backend);
        engine.load(QUrl("qrc:/Main.qml"));
        if (engine.rootObjects().isEmpty()) return;
        window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        if (!window || !QTest::qWaitForWindowExposed(window)) { window = nullptr; return; }
        window->requestActivate();
        if (!QTest::qWaitForWindowActive(window)) { window = nullptr; return; }
        // Cards land at once, so a test finds each where it belongs without waiting out a glide.
        window->findChild<QObject *>("table")->setProperty("motion", false);
    }
    ~Stage() { QCoreApplication::removeTranslator(&translator); }
};

} // namespace

class CardsTests : public QObject {
    Q_OBJECT

private slots:
    void init() { QTest::failOnWarning(); }

    void initTestCase() { QQuickStyle::setStyle("Material"); }


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

    void dealsAreTheSameForASeed() {
        const Game first(42), second(42), other(43);
        QSet<int> seen;
        bool differs = false;
        for (int pile = 0; pile < Piles; ++pile) {
            QCOMPARE(first.pile(pile).size(), second.pile(pile).size());
            for (size_t i = 0; i < first.pile(pile).size(); ++i) {
                QCOMPARE(first.pile(pile)[i].id, second.pile(pile)[i].id);
                seen << first.pile(pile)[i].id;
                differs = differs || other.pile(pile)[i].id != first.pile(pile)[i].id;
            }
        }
        QCOMPARE(seen.size(), 52);
        QVERIFY(differs);
        QCOMPARE(int(first.pile(Stock).size()), 24);
        for (int column = 0; column < 7; ++column) {
            const auto &pile = first.pile(Tableau + column);
            QCOMPARE(int(pile.size()), column + 1);
            for (int row = 0; row <= column; ++row) QCOMPARE(pile[row].up, row == column);
        }
    }

    void stockTurnsAndComesBackRound() {
        Game game(5);
        const QString start = layout(game);
        QVERIFY(!game.play(Waste, Stock, 0));
        for (int turn = 0; turn < 8; ++turn) QVERIFY(game.drawStock());
        QVERIFY(game.pile(Stock).empty());
        QCOMPARE(int(game.pile(Waste).size()), 24);
        for (const Card &card : game.pile(Waste)) QVERIFY(card.up);
        QVERIFY(game.drawStock());
        QCOMPARE(layout(game), start);
        QCOMPARE(int(game.moves().size()), 9);
        while (game.undo()) { }
        QCOMPARE(layout(game), start);
        // The stock turns three at a time, no fewer while it has them.
        QVERIFY(!game.play(Stock, Waste, 1));
        QVERIFY(game.play(Stock, Waste, 3));
        QCOMPARE(int(game.pile(Waste).size()), 3);
    }

    void movesFollowTheRules() {
        for (quint32 seed = 1; seed <= 60; ++seed) {
            const Game game(seed);
            for (int from = Tableau; from < Piles; ++from) {
                const int top = int(game.pile(from).size()) - 1;
                const Card card = game.pile(from)[top];
                // Hidden cards, the stock, and a pile onto itself never move.
                QVERIFY(!game.canMove(from, top - 1, Tableau));
                QVERIFY(!game.canMove(Stock, 0, Tableau));
                QVERIFY(!game.canMove(from, top, from));
                QVERIFY(!game.canMove(from, top, Stock));
                QVERIFY(!game.canMove(from, top, Waste));
                for (int to = Tableau; to < Piles; ++to) {
                    if (to == from) continue;
                    const Card onto = game.pile(to).back();
                    QCOMPARE(game.canMove(from, top, to), onto.red() != card.red() && onto.rank() == card.rank() + 1);
                }
                for (int home = Foundation; home < Tableau; ++home)
                    QCOMPARE(game.canMove(from, top, home), card.rank() == 0 && card.suit() == home - Foundation);
            }
        }
    }

    void hintsPlayLegalGamesThatUndoCleanly() {
        int won = 0;
        for (quint32 seed = 1; seed <= 40; ++seed) {
            Game game(seed);
            const QString start = layout(game);
            for (int step = 0; step < 700 && !game.won(); ++step) {
                const auto hint = game.hint();
                if (!hint) break;
                QVERIFY2(game.play(hint->from, hint->to, hint->count), qPrintable(QString("seed %1 step %2").arg(seed).arg(step)));
                while (game.finishStep()) { }
                QVERIFY2(sound(game), qPrintable(QString("seed %1 step %2").arg(seed).arg(step)));
            }
            won += game.won();
            while (game.undo()) { }
            QCOMPARE(layout(game), start);
        }
        QVERIFY(won > 0);
    }

    void aGameWithNothingHiddenFinishesItself() {
        Game game(winnable());
        while (!game.finishable()) {
            const auto hint = game.hint();
            QVERIFY(hint);
            QVERIFY(game.play(hint->from, hint->to, hint->count));
        }
        QVERIFY(!game.won());
        while (game.finishStep()) { }
        QVERIFY(game.won());
        QCOMPARE(game.home(), 52);
        QVERIFY(!game.hint());
        QVERIFY(!game.finishable());
    }

    void sendingACardPrefersHome() {
        // Any ace on top of a column goes home rather than onto a two.
        int aces = 0;
        for (quint32 seed = 1; seed <= 400; ++seed) {
            const Game game(seed);
            for (int from = Tableau; from < Piles; ++from) {
                const int top = int(game.pile(from).size()) - 1;
                if (game.pile(from)[top].rank() != 0) continue;
                QCOMPARE(game.bestTarget(from, top), Foundation + game.pile(from)[top].suit());
                ++aces;
            }
        }
        QVERIFY(aces > 20);
    }

    void positionsFoundInPlayKeepTheFinerRules() {
        // Positions no deal starts in, reached by playing: each rule is counted
        // so the test fails if the search stops finding the position it is about.
        int kingsAtFoot = 0, wasteHome = 0, buriedWaste = 0, homeTops = 0, comeDown = 0;
        for (quint32 seed = 1; seed <= 150; ++seed) {
            Game game(seed);
            for (int step = 0; step < 400 && !game.won(); ++step) {
                // Only the last card of the waste or a foundation moves, and only by itself.
                for (int pile = Waste; pile < Tableau; ++pile) {
                    const int size = int(game.pile(pile).size());
                    for (int index = 0; index < size - 1; ++index) {
                        QVERIFY(game.targets(pile, index).empty());
                        QCOMPARE(game.bestTarget(pile, index), -1);
                        buriedWaste += pile == Waste;
                    }
                    if (pile >= Foundation && size > 0) {
                        // A card that is home can be carried back to a column, never to another foundation.
                        for (int to : game.targets(pile, size - 1)) QVERIFY(to >= Tableau);
                        comeDown += !game.targets(pile, size - 1).empty();
                        ++homeTops;
                    }
                }
                if (!game.pile(Waste).empty()) {
                    const int top = int(game.pile(Waste).size()) - 1;
                    const int home = Foundation + game.pile(Waste)[top].suit();
                    if (game.canMove(Waste, top, home)) { QCOMPARE(game.bestTarget(Waste, top), home); ++wasteHome; }
                }
                // A king alone at the foot of its column is not sent to another empty one.
                bool space = false;
                for (int pile = Tableau; pile < Piles; ++pile) space = space || game.pile(pile).empty();
                for (int pile = Tableau; space && pile < Piles; ++pile) {
                    if (game.pile(pile).empty() || game.pile(pile)[0].rank() != 12 || !game.pile(pile)[0].up) continue;
                    bool onto = false;
                    for (int to : game.targets(pile, 0)) onto = onto || !game.pile(to).empty();
                    if (!onto) { QCOMPARE(game.bestTarget(pile, 0), -1); ++kingsAtFoot; }
                }
                const auto hint = game.hint();
                if (!hint) break;
                QVERIFY(game.play(hint->from, hint->to, hint->count));
            }
        }
        QVERIFY2(kingsAtFoot > 0 && wasteHome > 0 && buriedWaste > 0 && homeTops > 0 && comeDown > 0,
                 qPrintable(QString("%1 %2 %3 %4 %5").arg(kingsAtFoot).arg(wasteHome).arg(buriedWaste).arg(homeTops).arg(comeDown)));
    }

    void hintsGiveUpOnlyWhenThereIsNothingToFind() {
        int wins = 0, stuck = 0;
        for (quint32 seed = 1; seed <= 200; ++seed) {
            Game game(seed);
            int step = 0;
            for (; step < 3000 && !game.won(); ++step) {
                const auto hint = game.hint();
                if (!hint) break;
                QVERIFY(game.play(hint->from, hint->to, hint->count));
                while (game.finishStep()) { }
            }
            // No game is left turning the stock for ever: it is won, or the hints say there is nothing.
            QVERIFY2(step < 3000, qPrintable(QString("seed %1 never settles").arg(seed)));
            if (game.won()) { ++wins; continue; }
            ++stuck;
            // Nothing can go home, and nothing on the waste has a place.
            for (int from = Waste; from < Piles; from = from == Waste ? int(Tableau) : from + 1) {
                const int top = int(game.pile(from).size()) - 1;
                if (top < 0) continue;
                QVERIFY2(!game.canMove(from, top, Foundation + game.pile(from)[top].suit()), qPrintable(QString("seed %1").arg(seed)));
            }
            // No part of a run can move so that the card under it goes home or turns over.
            for (int from = Tableau; from < Piles; ++from) {
                const auto &pile = game.pile(from);
                for (int index = 1; index < int(pile.size()); ++index) {
                    if (!pile[index].up) continue;
                    const Card under = pile[index - 1];
                    const bool frees = !under.up || under.rank() == int(game.pile(Foundation + under.suit()).size());
                    for (int to : game.targets(from, index))
                        QVERIFY2(!(frees && to >= Tableau && !game.pile(to).empty()), qPrintable(QString("seed %1: %2 from %3").arg(seed).arg(index).arg(from)));
                }
            }
            // A whole turn of the stock shows nothing that can be played.
            Game turning = game;
            const int turns = int(game.pile(Stock).size() + game.pile(Waste).size()) / 3 + 3;
            for (int turn = 0; turn < 2 * turns && turning.drawStock(); ++turn) {
                const int top = int(turning.pile(Waste).size()) - 1;
                if (top >= 0) QVERIFY2(turning.targets(Waste, top).empty(), qPrintable(QString("seed %1").arg(seed)));
            }
        }
        QVERIFY2(wins > 10 && stuck > 10, qPrintable(QString("%1 won, %2 stuck").arg(wins).arg(stuck)));
    }

    void clicksPickUpAndPutDown() {
        Backend backend(":memory:");
        backend.newGame(transferSeed());
        const Move move = *backend.game().hint();
        const int index = int(backend.game().pile(move.from).size()) - move.count;
        const QVariantList before = backend.cards();
        // Picking a card up moves nothing, so the table is not laid out again for it.
        QSignalSpy laidOut(&backend, &Backend::changed), marked(&backend, &Backend::marksChanged);
        backend.activate(move.from, index);
        QCOMPARE(laidOut.count(), 0);
        QCOMPARE(marked.count(), 1);
        QCOMPARE(backend.selectedPile(), move.from);
        QCOMPARE(backend.selectedIndex(), index);
        QVERIFY(backend.targets().contains(move.to));
        // The same card again puts it back.
        backend.activate(move.from, index);
        QCOMPARE(backend.selectedPile(), -1);
        QVERIFY(backend.targets().isEmpty());
        backend.activate(move.from, index);
        backend.activate(move.to, int(backend.game().pile(move.to).size()) - 1);
        QCOMPARE(backend.moves(), 1);
        QCOMPARE(backend.selectedPile(), -1);
        QVERIFY(backend.cards() != before);
        QVERIFY(backend.canUndo());
        backend.undo();
        QCOMPARE(backend.cards(), before);
        QVERIFY(!backend.canUndo());
        // A drop where the cards may not go leaves them where they were.
        QVERIFY(!backend.drop(move.from, index, move.from));
        QVERIFY(!backend.drop(move.from, index, Stock));
        QVERIFY(backend.drop(move.from, index, move.to));
        QCOMPARE(backend.moves(), 1);
        // A hidden card cannot be picked up.
        backend.activate(Tableau + 6, 0);
        QCOMPARE(backend.selectedPile(), -1);
    }

    void theStockDrawsOnAClick() {
        Backend backend(":memory:");
        backend.newGame(9);
        QCOMPARE(backend.stock(), 24);
        backend.activate(Stock, 23);
        QCOMPARE(backend.stock(), 21);
        // Three drawn cards lie side by side, and only the last can be taken.
        const auto &waste = backend.game().pile(Waste);
        for (int i = 0; i < 3; ++i) QCOMPARE(backend.cards()[waste[i].id].toMap()["fan"].toInt(), i);
        backend.activate(Waste, 0);
        QCOMPARE(backend.selectedIndex(), 2);
        backend.cancelSelection();
        for (int turn = 0; turn < 7; ++turn) backend.draw();
        QCOMPARE(backend.stock(), 0);
        backend.activate(Stock, -1);
        QCOMPARE(backend.stock(), 24);
        QCOMPARE(backend.piles()[Waste].toMap()["count"].toInt(), 0);
        // A new game deals at once, and a different one each time.
        const QString dealt = layout(backend.game());
        backend.newGame();
        QCOMPARE(backend.moves(), 0);
        QCOMPARE(backend.stock(), 24);
        QVERIFY(layout(backend.game()) != dealt);
    }

    void hintsPointAtAMove() {
        Backend backend(":memory:");
        backend.newGame(transferSeed());
        const Move move = *backend.game().hint();
        backend.hint();
        QCOMPARE(backend.hintFrom(), move.from);
        QCOMPARE(backend.hintTo(), move.to);
        QCOMPARE(backend.hintIndex(), int(backend.game().pile(move.from).size()) - move.count);
        QVERIFY(!backend.stuck());
        // Any move clears it, and so does taking one back.
        backend.draw();
        QCOMPARE(backend.hintFrom(), -1);
        QCOMPARE(backend.hintTo(), -1);
        backend.hint();
        QVERIFY(backend.hintFrom() >= 0);
        backend.undo();
        QCOMPARE(backend.hintFrom(), -1);
        backend.activate(move.from, int(backend.game().pile(move.from).size()) - move.count);
        QCOMPARE(backend.selectedPile(), move.from);
        QVERIFY(!backend.targets().isEmpty());
        backend.draw();
        backend.activate(move.from, int(backend.game().pile(move.from).size()) - move.count);
        backend.undo();
        QCOMPARE(backend.selectedPile(), -1);
        QVERIFY(backend.targets().isEmpty());
    }

    void aHintWithNothingToOfferSaysSo() {
        Backend backend(":memory:");
        backend.newGame(stuckSeed());
        while (const auto move = backend.game().hint()) {
            if (move->from == Stock || move->to == Stock) backend.draw();
            else QVERIFY(backend.drop(move->from, int(backend.game().pile(move->from).size()) - move->count, move->to));
        }
        QVERIFY(!backend.won());
        QVERIFY(!backend.stuck());
        backend.hint();
        QVERIFY(backend.stuck());
        QCOMPARE(backend.hintFrom(), -1);
        QCOMPARE(backend.hintTo(), -1);
        // It goes away with the next thing done.
        backend.cancelSelection();
        QVERIFY(!backend.stuck());
        backend.hint();
        QVERIFY(backend.stuck());
        backend.undo();
        QVERIFY(!backend.stuck());
    }

    void aCardThatIsHomeComesBackOnlyByHand() {
        Backend backend(":memory:");
        // Play until a card on a foundation could be set back on a column.
        int home = -1, to = -1;
        for (quint32 seed = 1; seed < 200 && home < 0; ++seed) {
            backend.newGame(seed);
            for (int step = 0; step < 300 && home < 0; ++step) {
                const auto move = backend.game().hint();
                if (!move) break;
                if (move->from == Stock || move->to == Stock) backend.draw();
                else if (!backend.drop(move->from, int(backend.game().pile(move->from).size()) - move->count, move->to)) break;
                for (int pile = Foundation; pile < Tableau && home < 0; ++pile) {
                    const int top = int(backend.game().pile(pile).size()) - 1;
                    if (top < 0) continue;
                    const auto targets = backend.game().targets(pile, top);
                    if (!targets.empty()) { home = pile; to = targets.front(); }
                }
            }
        }
        QVERIFY(home >= 0);
        const int top = int(backend.game().pile(home).size()) - 1;
        const int moves = backend.moves(), cards = backend.home();
        // A double click or F leaves it where it is.
        QVERIFY(!backend.autoPlay(home, top));
        QCOMPARE(backend.moves(), moves);
        // Picked up and put down, or dragged, it goes.
        backend.activate(home, top);
        QCOMPARE(backend.selectedPile(), home);
        backend.activate(to, int(backend.game().pile(to).size()) - 1);
        QCOMPARE(backend.moves(), moves + 1);
        QCOMPARE(backend.home(), cards - 1);
    }

    void winningEndsTheGame() {
        Backend backend(":memory:");
        backend.setActive(true);
        backend.newGame(winnable());
        backend.draw();
        QTRY_VERIFY_WITH_TIMEOUT(backend.elapsed() >= 1, 2500);
        backend.undo();
        QVERIFY(playOut(backend));
        QVERIFY(backend.won());
        QCOMPARE(backend.home(), 52);
        // The clock stops with the last card.
        const int time = backend.elapsed();
        QVERIFY(time >= 1);
        QTest::qWait(1200);
        QCOMPARE(backend.elapsed(), time);
        const int moves = backend.moves();
        backend.draw();
        backend.activate(Foundation, 12);
        backend.hint();
        QCOMPARE(backend.moves(), moves);
        QCOMPARE(backend.selectedPile(), -1);
        QVERIFY(!backend.stuck());
        backend.undo();
        QVERIFY(!backend.won());
        backend.newGame(winnable());
        QCOMPARE(backend.moves(), 0);
        QCOMPARE(layout(backend.game()), layout(Game(winnable())));
    }

    void finishingPlaysOutCardByCard() {
        Backend backend(":memory:");
        backend.newGame(winnable());
        while (!backend.game().finishable()) {
            const Move move = *backend.game().hint();
            if (move.from == Stock || move.to == Stock) backend.draw();
            else QVERIFY(backend.drop(move.from, int(backend.game().pile(move.from).size()) - move.count, move.to));
        }
        // The last move starts it; nothing else can be played meanwhile, and undo stops it.
        QVERIFY(!backend.won());
        const int moves = backend.moves();
        int pile = Tableau;
        while (backend.game().pile(pile).empty() || !backend.game().canMove(pile, int(backend.game().pile(pile).size()) - 1, Foundation + backend.game().pile(pile).back().suit())) ++pile;
        const int top = int(backend.game().pile(pile).size()) - 1, home = Foundation + backend.game().pile(pile).back().suit();
        QVERIFY(!backend.drop(pile, top, home));
        QVERIFY(!backend.autoPlay(pile, top));
        backend.activate(pile, top);
        QCOMPARE(backend.selectedPile(), -1);
        backend.hint();
        QCOMPARE(backend.hintFrom(), -1);
        QCOMPARE(backend.moves(), moves);
        QTRY_VERIFY(backend.moves() > moves + 1);
        backend.undo();
        const int stopped = backend.moves();
        QTest::qWait(300);
        QCOMPARE(backend.moves(), stopped);
        QVERIFY(!backend.won());
    }

    void aGameLeftWhileFinishingCarriesOn() {
        QTemporaryDir dir;
        int cards = 0;
        {
            Backend backend(dir.filePath("game.json"));
            backend.newGame(winnable());
            while (!backend.game().finishable()) {
                const Move move = *backend.game().hint();
                if (move.from == Stock || move.to == Stock) backend.draw();
                else QVERIFY(backend.drop(move.from, int(backend.game().pile(move.from).size()) - move.count, move.to));
            }
            cards = backend.home();
        }
        Backend restored(dir.filePath("game.json"));
        QVERIFY(restored.home() >= cards);
        QVERIFY(!restored.won());
        QTRY_VERIFY_WITH_TIMEOUT(restored.won(), 10000);
    }

    void theClockRunsOnlyWhileTheGameIsInFront() {
        Backend backend(":memory:");
        backend.newGame(9);
        // Until the window says it is in front, the clock waits, moves or not.
        QVERIFY(!backend.active());
        backend.draw();
        QTest::qWait(1200);
        QCOMPARE(backend.elapsed(), 0);
        backend.newGame(9);
        backend.setActive(true);
        // And in front, it waits for the first move.
        QTest::qWait(1200);
        QCOMPARE(backend.elapsed(), 0);
        backend.draw();
        QTRY_VERIFY_WITH_TIMEOUT(backend.elapsed() >= 1, 2500);
        backend.setActive(false);
        const int paused = backend.elapsed();
        QTest::qWait(1200);
        QCOMPARE(backend.elapsed(), paused);
        backend.setActive(true);
        QTRY_VERIFY_WITH_TIMEOUT(backend.elapsed() > paused, 2500);
        backend.newGame(9);
        QCOMPARE(backend.elapsed(), 0);
    }

    void saveAndResume() {
        QTemporaryDir dir;
        QString state;
        {
            Backend game(dir.filePath("game.json"));
            game.newGame(transferSeed());
            const Move move = *game.game().hint();
            QVERIFY(game.drop(move.from, int(game.game().pile(move.from).size()) - move.count, move.to));
            game.draw();
            game.setSeries(3);
            state = layout(game.game());
            // Time that passes after the last move is kept too, written as the game is put away.
            game.setActive(true);
            QTRY_VERIFY_WITH_TIMEOUT(game.elapsed() >= 1, 2500);
            QCOMPARE(readCatalog(dir.filePath("game.json"))["elapsed"].toInt(), 0);
        }
        QVERIFY(readCatalog(dir.filePath("game.json"))["elapsed"].toInt() >= 1);
        Backend restored(dir.filePath("game.json"));
        QVERIFY(restored.elapsed() >= 1);
        QCOMPARE(layout(restored.game()), state);
        QCOMPARE(restored.moves(), 2);
        QCOMPARE(restored.series(), 3);
        QVERIFY(restored.saveHealthy());
        restored.undo();
        QCOMPARE(restored.moves(), 1);
    }

    void saveHasOneOwner() {
        QTemporaryDir dir;
        Backend owner(dir.filePath("game.json"));
        owner.newGame(9);
        owner.draw();
        Backend second(dir.filePath("game.json"));
        QVERIFY(owner.ownsSave());
        QVERIFY(!second.ownsSave());
        QVERIFY(!second.saveHealthy());
        QVERIFY(!second.error().isEmpty());
        second.newGame(5);
        second.setSeries(2);
        QCOMPARE(readCatalog(dir.filePath("game.json"))["seed"].toInt(), 9);
        QCOMPARE(readCatalog(dir.filePath("game.json"))["series"].toInt(), 0);
    }

    void damagedSaveSurvivesPreferences() {
        QTemporaryDir dir;
        const QString path = dir.filePath("game.json");
        // A game that goes on after it was won, and one longer than is ever written.
        Game won(winnable());
        while (!won.won()) {
            if (won.finishStep()) continue;
            const Move move = *won.hint();
            QVERIFY(won.play(move.from, move.to, move.count));
        }
        Game endless(9);
        while (int(endless.moves().size()) <= 100000) QVERIFY(endless.drawStock());
        for (const QByteArray &damaged : {QByteArray("not json"), QByteArray(R"({"version":1,"seed":9,"moves":[[6,6,1]]})"),
                                          QByteArray(R"({"version":1,"seed":0,"moves":[]})"), QByteArray(R"({"version":1,"seed":4294967296,"moves":[]})"),
                                          QByteArray(R"({"version":1,"seed":9,"moves":[[0,1]]})"), QByteArray(R"({"version":1,"seed":9,"moves":{}})"),
                                          QByteArray(R"({"version":2,"seed":9,"moves":[]})"), saved(won, ",[12,11,1]"), saved(endless),
                                          QByteArray(2 * 1024 * 1024 + 1, ' ')}) {
            QVERIFY(write(path, damaged));
            Backend backend(path);
            QVERIFY(!backend.error().isEmpty());
            QVERIFY(!backend.saveHealthy());
            QCOMPARE(backend.moves(), 0);
            backend.setSeries(2);
            backend.draw();
            QCOMPARE(contents(path), damaged);
            // Dismissing the message changes nothing about the game not being saved.
            backend.dismissError();
            QVERIFY(backend.error().isEmpty());
            QVERIFY(!backend.saveHealthy());
            backend.draw();
            QCOMPARE(contents(path), damaged);
            // Only an explicit new game replaces it.
            backend.newGame(9);
            QVERIFY(backend.saveHealthy());
            QVERIFY(backend.error().isEmpty());
            QCOMPARE(readCatalog(path)["seed"].toInt(), 9);
        }
    }

    void theLongestGameStillOpens() {
        QTemporaryDir dir;
        const QString path = dir.filePath("game.json");
        // What the app writes for a game at its limit is under the size it will read.
        Game longest(9);
        while (int(longest.moves().size()) < 100000) QVERIFY(longest.drawStock());
        QVERIFY(write(path, saved(longest)));
        {
            Backend backend(path);
            QVERIFY2(backend.error().isEmpty(), qPrintable(backend.error()));
            QCOMPARE(backend.moves(), 100000);
            // It takes no more moves, so it can always be read back; undo still works.
            backend.draw();
            QCOMPARE(backend.moves(), 100000);
            backend.undo();
            QCOMPARE(backend.moves(), 99999);
            backend.draw();
            QCOMPARE(backend.moves(), 100000);
        }
        QVERIFY(QFileInfo(path).size() < 2 * 1024 * 1024);
        Backend again(path);
        QVERIFY(again.error().isEmpty());
        QCOMPARE(again.moves(), 100000);
    }

    void failedSavePreservesPreviousGame() {
        QTemporaryDir dir;
        const QString path = dir.filePath("save/game.json");
        Backend backend(path);
        backend.newGame(9);
        backend.draw();
        const QByteArray before = contents(path);
        QVERIFY(before.contains("\"seed\":9"));
        // A folder that takes no new files fails the save rather than rewriting the game in place.
        QVERIFY(QFile::setPermissions(dir.filePath("save"), QFile::ReadOwner | QFile::ExeOwner));
        backend.draw();
        QVERIFY(!backend.saveHealthy());
        QVERIFY(!backend.error().isEmpty());
        QCOMPARE(contents(path), before);
        QVERIFY(QFile::setPermissions(dir.filePath("save"), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner));
        backend.draw();
        QVERIFY(backend.saveHealthy());
        QVERIFY(backend.error().isEmpty());
        QVERIFY(contents(path) != before);
    }

    void secondLaunchWaitsForStartingOwner() {
        QTemporaryDir dir;
        Backend owner(dir.filePath("cards/game.json"));
        owner.newGame(9);
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert("XDG_DATA_HOME", dir.path());
        environment.insert("XDG_RUNTIME_DIR", dir.path());
        QLocalServer server;
        QTimer::singleShot(600, &server, [&] { server.listen(dir.filePath("cards.sock")); });
        QProcess second;
        second.setProcessEnvironment(environment);
        second.start(QCoreApplication::applicationDirPath() + "/cards", {"open"});
        QTRY_COMPARE_WITH_TIMEOUT(second.state(), QProcess::NotRunning, 4000);
        QCOMPARE(second.exitCode(), 0);
        QVERIFY(server.hasPendingConnections());
    }

    void headlessCommandsNeedNoDisplay() {
        QTemporaryDir dir;
        {
            Backend game(dir.filePath("cards/game.json"));
            game.newGame(9);
            game.draw();
            game.draw();
        }
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.remove("DISPLAY"); environment.remove("WAYLAND_DISPLAY"); environment.remove("QT_QPA_PLATFORM");
        environment.insert("XDG_DATA_HOME", dir.path());
        QProcess process;
        process.setProcessEnvironment(environment);
        const QString binary = QCoreApplication::applicationDirPath() + "/cards";
        auto run = [&](const QStringList &arguments) {
            process.start(binary, arguments);
            return process.waitForFinished() && process.exitStatus() == QProcess::NormalExit ? process.exitCode() : -1;
        };
        QCOMPARE(run({"inspect", "--json"}), 0);
        auto state = QJsonDocument::fromJson(process.readAllStandardOutput()).object();
        QCOMPARE(state["moves"].toInt(), 2);
        QCOMPARE(state["stock"].toInt(), 18);
        QCOMPARE(state["waste"].toArray().size(), 6);
        QCOMPARE(state["seed"].toInt(), 9);
        QCOMPARE(run({"inspect"}), 0);
        QVERIFY(process.readAllStandardOutput().startsWith("Stock 18"));
        QCOMPARE(run({"deal", "42", "--json"}), 0);
        state = QJsonDocument::fromJson(process.readAllStandardOutput()).object();
        QCOMPARE(state["stock"].toInt(), 24);
        QCOMPARE(state["tableau"].toArray().size(), 7);
        const Game dealt(42);
        const QJsonArray last = state["tableau"].toArray()[6].toArray();
        QCOMPARE(last.size(), 7);
        QCOMPARE(last[0].toString(), QString("??"));
        const Card shown = dealt.pile(Tableau + 6).back();
        QCOMPARE(last[6].toString(), QString(QStringList{"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}[shown.rank()]) + "SHDC"[shown.suit()]);
        QCOMPARE(run({"deal"}), 0);
        QCOMPARE(run({"deal", "0"}), 1);
        QVERIFY(!process.readAllStandardError().isEmpty());
        QCOMPARE(run({"deal", "1", "2"}), 1);
        QCOMPARE(run({"shuffle"}), 1);
        // The app carries no version of its own; the package it came in has one.
        QCOMPARE(run({"--version"}), 1);
        QCOMPARE(run({"--help"}), 0);
        environment.insert("XDG_DATA_HOME", dir.filePath("nothing"));
        process.setProcessEnvironment(environment);
        QCOMPARE(run({"inspect"}), 1);
    }

    void windowLoadsAndAnswersTheKeyboard() {
        QTemporaryDir dir;
        Stage stage(dir.path());
        QVERIFY2(stage.window, qPrintable(stage.warnings.join('\n')));
        Backend &backend = stage.backend;
        QQuickWindow *window = stage.window;
        auto *table = window->findChild<QQuickItem *>("table");
        QVERIFY(table);

        // D turns the stock, and Ctrl+Z turns it back.
        QTest::keyClick(window, Qt::Key_D);
        QCOMPARE(backend.stock(), 21);
        QTest::keyClick(window, Qt::Key_Z, Qt::ControlModifier);
        QCOMPARE(backend.stock(), 24);

        // The cursor starts on the first column: Space picks its card up, Escape puts it back.
        QTest::keyClick(window, Qt::Key_Space);
        QCOMPARE(backend.selectedPile(), int(Tableau));
        QVERIFY(table->property("keyboard").toBool());
        QTest::keyClick(window, Qt::Key_Escape);
        QCOMPARE(backend.selectedPile(), -1);
        // Up from the first column is the stock, where Enter draws.
        QTest::keyClick(window, Qt::Key_Up);
        QCOMPARE(table->property("cursorPile").toInt(), int(Stock));
        QTest::keyClick(window, Qt::Key_Return);
        QCOMPARE(backend.stock(), 21);
        QTest::keyClick(window, Qt::Key_Right);
        QCOMPARE(table->property("cursorPile").toInt(), int(Waste));
        QCOMPARE(table->property("cursorIndex").toInt(), 2);
        QTest::keyClick(window, Qt::Key_Down);
        QCOMPARE(table->property("cursorPile").toInt(), Tableau + 1);
        for (int press = 0; press < 9; ++press) QTest::keyClick(window, Qt::Key_Right);
        QCOMPARE(table->property("cursorPile").toInt(), Tableau + 6);
        // Up stops at the first card that shows, then leaves for the foundations.
        QCOMPARE(table->property("cursorIndex").toInt(), 6);
        QTest::keyClick(window, Qt::Key_Up);
        QCOMPARE(table->property("cursorPile").toInt(), Foundation + 3);
        QCOMPARE(table->property("cursorIndex").toInt(), -1);

        // Taking the draw back leaves the waste empty, and the cursor follows it there.
        QTest::keyClick(window, Qt::Key_Left);
        for (int press = 0; press < 5; ++press) QTest::keyClick(window, Qt::Key_Left);
        QTest::keyClick(window, Qt::Key_Right);
        QCOMPARE(table->property("cursorPile").toInt(), int(Waste));
        QCOMPARE(table->property("cursorIndex").toInt(), 2);
        auto *under = findItem(window->contentItem(), QString("card-%1").arg(backend.game().pile(Waste).back().id));
        QVERIFY(under && under->findChild<QQuickItem *>("cursorRing")->isVisible());
        QTest::keyClick(window, Qt::Key_Z, Qt::ControlModifier);
        QCOMPARE(backend.stock(), 24);
        QCOMPARE(table->property("cursorIndex").toInt(), -1);
        QVERIFY(!under->findChild<QQuickItem *>("cursorRing")->isVisible());

        // The hint key marks a move, and F sends the card under the cursor on its way.
        backend.newGame(transferSeed());
        const Move move = *backend.game().hint();
        QTest::keyClick(window, Qt::Key_H);
        QCOMPARE(backend.hintFrom(), move.from);
        auto *hintRing = findItem(window->contentItem(), "hintRing");
        auto *hintTargetRing = findItem(window->contentItem(), "hintTargetRing");
        QVERIFY(hintRing && hintRing->isVisible() && hintTargetRing && hintTargetRing->isVisible());
        QVERIFY(qAbs(hintRing->x() + hintRing->width() / 2 - table->property("cardWidth").toReal() / 2
                     - findItem(window->contentItem(), QString("slot-%1").arg(move.from))->x()) < 1);
        QVERIFY(qAbs(hintTargetRing->x() - findItem(window->contentItem(), QString("slot-%1").arg(move.to))->x()) < 6);
        QVERIFY(QMetaObject::invokeMethod(table, "navigate", Q_ARG(QVariant, 0), Q_ARG(QVariant, 1)));
        table->setProperty("cursorPile", move.from);
        table->setProperty("cursorIndex", int(backend.game().pile(move.from).size()) - move.count);
        QTest::keyClick(window, Qt::Key_F);
        QCOMPARE(backend.moves(), 1);

        // Every series draws without complaint, at any size, in a light theme too.
        for (int series = 0; series < 4; ++series) {
            QTest::keyClick(window, Qt::Key_1 + series);
            QCOMPARE(backend.series(), series);
            QTest::qWait(60);
        }
        const QSize original = window->size();
        for (const QSize size : {QSize(720, 540), QSize(1600, 700), QSize(800, 1300)}) {
            window->resize(size);
            QTest::qWait(200);
            // The last card of the longest column stays on the table.
            auto *last = findItem(window->contentItem(), QString("card-%1").arg(backend.game().pile(Tableau + 6).back().id));
            QVERIFY(last);
            QVERIFY2(last->y() + last->height() <= table->height() && last->x() + last->width() <= table->width() && last->x() >= 0,
                     qPrintable(QString("%1x%2: card at %3,%4").arg(size.width()).arg(size.height()).arg(last->x()).arg(last->y())));
        }
        window->resize(original);
        QVERIFY(QDir(dir.path()).mkpath("theme"));
        QVERIFY(write(dir.path() + "/theme/colors.toml", "mode = \"light\"\naccent = \"#aa3311\"\nbackground = \"#fafafa\"\nforeground = \"#202020\"\n"));
        QTRY_VERIFY(stage.theme.light());
        backend.setSeries(0);
        QTest::qWait(100);
        // Phosphor is made of the theme: its cards take the new background.
        auto *card = findItem(window->contentItem(), QString("card-%1").arg(backend.game().pile(Tableau + 6).back().id));
        QVERIFY(card);
        auto *face = card->findChild<QQuickItem *>("face");
        QVERIFY(face && face->isVisible());
        QCOMPARE(face->property("color").value<QColor>(), QColor("#fafafa"));
        QCOMPARE(window->property("phosphorRed").value<QColor>(), QColor("#aa3311"));
        // A theme whose accent is its text color would leave the suits looking alike, so its red stands in.
        QVERIFY(write(dir.path() + "/theme/colors.toml", "mode = \"dark\"\naccent = \"#dcd7ba\"\nbackground = \"#1f1f28\"\nforeground = \"#dcd7ba\"\nred = \"#c34043\"\n"));
        QTRY_VERIFY(!stage.theme.light());
        QTRY_COMPARE(window->property("phosphorRed").value<QColor>(), QColor("#c34043"));

        // The footer is one slim line, and the table has the rest of the window.
        auto *footer = window->findChild<QQuickItem *>("footer");
        QVERIFY(footer && footer->isVisible());
        QVERIFY(footer->height() <= 44);
        QCOMPARE(table->height() + footer->height(), qreal(window->height()));

        // The shortcuts open from the keyboard and close on Escape.
        {
            QTest::keyClick(window, Qt::Key('?'));
            auto *dialog = window->findChild<QObject *>("help");
            QVERIFY(dialog);
            QTRY_VERIFY(dialog->property("opened").toBool());
            // Single keys belong to the dialog while it is open.
            const int stock = backend.stock();
            QTest::keyClick(window, Qt::Key_D);
            QCOMPARE(backend.stock(), stock);
            QTest::keyClick(window, Qt::Key_Escape);
            QTRY_VERIFY(!dialog->property("visible").toBool());
        }
        // The shortcuts overlay lists every key in a row of its own, none cut short.
        QTest::keyClick(window, Qt::Key('?'));
        auto *help = window->findChild<QObject *>("help");
        QTRY_VERIFY(help->property("opened").toBool());
        QQuickItem *previous = nullptr;
        for (int row = 0; row < 11; ++row) {
            auto *shortcut = findItem(window->contentItem(), QString("shortcut-%1").arg(row));
            QVERIFY2(shortcut, qPrintable(QString::number(row)));
            QVERIFY(shortcut->width() > 300);
            if (previous) QVERIFY(shortcut->mapToScene(QPointF(0, 0)).y() >= previous->mapToScene(QPointF(0, previous->height())).y());
            QVERIFY(shortcut->mapToScene(QPointF(0, shortcut->height())).y() < window->height());
            previous = shortcut;
        }
        QVERIFY(!findItem(window->contentItem(), "shortcut-11"));
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(!help->property("visible").toBool());
        // The name in the footer opens the same overlay, and the stats sit in the middle.
        auto *wordmark = window->findChild<QQuickItem *>("wordmark");
        QVERIFY(wordmark);
        QTest::mouseClick(window, Qt::LeftButton, {}, wordmark->mapToScene(QPointF(wordmark->width() / 2, wordmark->height() / 2)).toPoint());
        QTRY_VERIFY(help->property("opened").toBool());
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(!help->property("visible").toBool());
        auto *time = window->findChild<QQuickItem *>("timeStat");
        auto *movesStat = window->findChild<QQuickItem *>("movesStat");
        auto *stockStat = window->findChild<QQuickItem *>("stockStat");
        QVERIFY(time && movesStat && stockStat);
        auto left = [](QQuickItem *item) { return item->mapToScene(QPointF(0, 0)).x(); };
        auto right = [](QQuickItem *item) { return item->mapToScene(QPointF(item->width(), 0)).x(); };
        // The clock sits dead centre, with the moves before it and the stock after.
        QVERIFY(qAbs((left(time) + right(time)) / 2 - window->width() / 2.0) <= 1);
        QVERIFY(right(movesStat) < left(time));
        QVERIFY(left(stockStat) > right(time));
        // None of the three moves as the numbers change: more moves, more time, a smaller stock.
        const qreal places[] = {left(movesStat), left(time), right(time), left(stockStat)};
        for (int turn = 0; turn < 12; ++turn) backend.draw();
        QTRY_VERIFY_WITH_TIMEOUT(backend.elapsed() >= 1, 2500);
        QVERIFY(backend.moves() >= 12);
        QTest::qWait(50);
        QCOMPARE(left(movesStat), places[0]);
        QCOMPARE(left(time), places[1]);
        QCOMPARE(right(time), places[2]);
        QCOMPARE(left(stockStat), places[3]);
        // Nothing in the footer runs into anything else, even at the narrowest window.
        window->resize(720, 540);
        QTest::qWait(150);
        auto *lastSwatch = findItem(window->contentItem(), "series-3");
        auto *undo = window->findChild<QQuickItem *>("undoButton");
        QVERIFY(lastSwatch && undo);
        QVERIFY(right(lastSwatch) + 8 <= left(movesStat));
        QVERIFY(right(stockStat) + 8 <= left(undo));
        window->resize(original);
        QTest::qWait(150);
        // A long column closes up to stay on the table, even in the smallest window.
        {
            int longest = -1;
            for (quint32 seed = 1; seed < 400 && longest < 0; ++seed) {
                backend.newGame(seed);
                for (int step = 0; step < 300 && longest < 0; ++step) {
                    const auto next = backend.game().hint();
                    if (!next || backend.game().finishable()) break;
                    if (next->from == Stock || next->to == Stock) backend.draw();
                    else QVERIFY(backend.drop(next->from, int(backend.game().pile(next->from).size()) - next->count, next->to));
                    for (int pile = Tableau; pile < Piles; ++pile)
                        if (backend.piles()[pile].toMap()["up"].toInt() >= 12 && !backend.game().finishable()) longest = pile;
                }
            }
            QVERIFY(longest >= 0);
            window->resize(720, 540);
            QTest::qWait(200);
            auto *first = findItem(window->contentItem(), QString("card-%1").arg(backend.game().pile(longest).front().id));
            auto *last = findItem(window->contentItem(), QString("card-%1").arg(backend.game().pile(longest).back().id));
            QVERIFY(first && last);
            QVERIFY2(last->y() + last->height() <= table->height() + .5, qPrintable(QString::number(last->y() + last->height())));
            // Closed up: its cards lie nearer than they would with room to spare.
            const int count = int(backend.game().pile(longest).size());
            QVERIFY((last->y() - first->y()) / (count - 1) < table->property("upStep").toReal() - .5);
            window->resize(original);
            QTest::qWait(200);
        }

        // When a hint finds nothing, the footer says so where the counts were.
        auto *status = window->findChild<QQuickItem *>("status");
        auto *stats = window->findChild<QQuickItem *>("stats");
        QVERIFY(status && stats && !status->isVisible() && stats->isVisible());
        backend.newGame(stuckSeed());
        while (const auto next = backend.game().hint()) {
            if (next->from == Stock || next->to == Stock) backend.draw();
            else QVERIFY(backend.drop(next->from, int(backend.game().pile(next->from).size()) - next->count, next->to));
        }
        QTest::keyClick(window, Qt::Key_H);
        QVERIFY(backend.stuck());
        QVERIFY(status->isVisible() && !stats->isVisible());
        QVERIFY(!hintRing->isVisible() && !hintTargetRing->isVisible());
        QTest::keyClick(window, Qt::Key_Escape);
        QVERIFY(!status->isVisible() && stats->isVisible());
        // A healthy game shows no warning about saving.
        QVERIFY(!window->findChild<QQuickItem *>("unsavedMark")->isVisible());

        // N deals a new game at once, and so does the footer's button.
        backend.draw();
        QString dealt = layout(backend.game());
        QTest::keyClick(window, Qt::Key_N);
        QVERIFY(layout(backend.game()) != dealt);
        QCOMPARE(backend.moves(), 0);
        backend.draw();
        dealt = layout(backend.game());
        auto *deal = window->findChild<QQuickItem *>("newGameButton");
        QVERIFY(deal);
        QTest::mouseClick(window, Qt::LeftButton, {}, deal->mapToScene(QPointF(deal->width() / 2, deal->height() / 2)).toPoint());
        QVERIFY(layout(backend.game()) != dealt);
        QCOMPARE(backend.moves(), 0);
    }

    void theMouseClicksDragsAndDoubleClicks() {
        QTemporaryDir dir;
        Stage stage(dir.path());
        QVERIFY2(stage.window, qPrintable(stage.warnings.join('\n')));
        Backend &backend = stage.backend;
        QQuickWindow *window = stage.window;
        backend.newGame(transferSeed());
        QTest::qWait(50);
        auto centre = [&](int pile) {
            const auto &cards = backend.game().pile(pile);
            QQuickItem *item = cards.empty() ? findItem(window->contentItem(), QString("slot-%1").arg(pile))
                                             : findItem(window->contentItem(), QString("card-%1").arg(cards.back().id));
            // Near the top edge, the part of a card that shows in a column.
            return item ? item->mapToScene(QPointF(item->width() / 2, 10)).toPoint() : QPoint();
        };
        // A click on the stock draws; a click on its empty place brings the waste back.
        for (int turn = 0; turn < 8; ++turn) QTest::mouseClick(window, Qt::LeftButton, {}, centre(Stock));
        QCOMPARE(backend.stock(), 0);
        QTest::mouseClick(window, Qt::LeftButton, {}, centre(Stock));
        QCOMPARE(backend.stock(), 24);
        QCOMPARE(backend.moves(), 9);
        while (backend.canUndo()) backend.undo();
        QTest::mouseClick(window, Qt::LeftButton, {}, centre(Stock));
        QCOMPARE(backend.stock(), 21);
        QTest::mouseClick(window, Qt::LeftButton, {}, centre(Waste));
        QCOMPARE(backend.selectedPile(), int(Waste));
        // The bare table puts the card back.
        QTest::mouseClick(window, Qt::LeftButton, {}, QPoint(4, window->height() - 60));
        QCOMPARE(backend.selectedPile(), -1);
        backend.undo();

        // A click picks up, a click on the target puts down.
        const Move move = *backend.game().hint();
        QVERIFY(move.count == 1);
        QTest::mouseClick(window, Qt::LeftButton, {}, centre(move.from));
        QCOMPARE(backend.selectedPile(), move.from);
        auto *held = findItem(window->contentItem(), QString("card-%1").arg(backend.game().pile(move.from).back().id));
        auto *outline = findItem(window->contentItem(), "selectionRing");
        QVERIFY(outline && outline->isVisible());
        // The outline sits around the card that was picked up.
        QVERIFY(qAbs(outline->x() + outline->width() / 2 - held->x() - held->width() / 2) < 1);
        QVERIFY(qAbs(outline->y() + outline->height() / 2 - held->y() - held->height() / 2) < 1);
        auto *onto = findItem(window->contentItem(), QString("card-%1").arg(backend.game().pile(move.to).back().id));
        QVERIFY(onto->findChild<QQuickItem *>("targetRing")->isVisible());
        QTest::mouseClick(window, Qt::LeftButton, {}, centre(move.to));
        QCOMPARE(backend.moves(), 1);
        QCOMPARE(backend.game().moves().back(), move);
        backend.undo();

        // The same move as a drag, and a drag to nowhere that springs back.
        const QPoint from = centre(move.from), to = centre(move.to);
        QTest::mousePress(window, Qt::LeftButton, {}, from);
        QTest::mouseMove(window, from + QPoint(12, 12));
        QTest::mouseMove(window, to + QPoint(3, 30));
        QTest::mouseRelease(window, Qt::LeftButton, {}, to + QPoint(3, 30));
        QCOMPARE(backend.moves(), 1);
        QCOMPARE(backend.game().moves().back(), move);
        backend.undo();
        QTest::mousePress(window, Qt::LeftButton, {}, from);
        QTest::mouseMove(window, from + QPoint(12, 12));
        QTest::mouseMove(window, QPoint(6, window->height() - 60));
        QTest::mouseRelease(window, Qt::LeftButton, {}, QPoint(6, window->height() - 60));
        QCOMPARE(backend.moves(), 0);
        QCOMPARE(centre(move.from), from);

        auto *table = window->findChild<QQuickItem *>("table");
        auto *grip = findItem(window->contentItem(), QString("card-%1").arg(backend.game().pile(move.from).back().id))->findChild<QQuickItem *>("grip");
        QVERIFY(table && grip);
        // Picking cards up by dragging lets go of whatever a click had picked up.
        QTest::mouseClick(window, Qt::LeftButton, {}, centre(move.to));
        QCOMPARE(backend.selectedPile(), move.to);
        QTest::mousePress(window, Qt::LeftButton, {}, from);
        QTest::mouseMove(window, from + QPoint(12, 12));
        QVERIFY(table->property("dragging").toBool());
        QCOMPARE(backend.selectedPile(), -1);
        // Single keys wait while cards are in the hand: no new deal, no draw.
        const QString inHand = layout(backend.game());
        QTest::keyClick(window, Qt::Key_N);
        QTest::keyClick(window, Qt::Key_D);
        QCOMPARE(layout(backend.game()), inHand);
        // Escape lets go of them, back where they were, and the release that follows drops nothing.
        QTest::mouseMove(window, to + QPoint(3, 30));
        QTest::keyClick(window, Qt::Key_Escape);
        QVERIFY(!table->property("dragging").toBool());
        QTest::mouseMove(window, to + QPoint(4, 31));
        QTest::mouseRelease(window, Qt::LeftButton, {}, to + QPoint(4, 31));
        QCOMPARE(backend.moves(), 0);
        QCOMPARE(centre(move.from), from);
        QTest::mousePress(window, Qt::LeftButton, {}, from);
        QTest::mouseMove(window, from + QPoint(12, 12));
        QVERIFY(table->property("dragging").toBool());
        // A drag that is taken away, rather than let go, puts the cards back.
        QTest::mouseMove(window, to + QPoint(3, 30));
        grip->ungrabMouse();
        QVERIFY(!table->property("dragging").toBool());
        QCOMPARE(table->property("dragPile").toInt(), -1);
        QCOMPARE(backend.moves(), 0);
        QTest::mouseRelease(window, Qt::LeftButton, {}, to + QPoint(3, 30));
        QCOMPARE(backend.moves(), 0);
        QCOMPARE(centre(move.from), from);

        // A double click to put a card down puts it down once, and does not send it on,
        // in a deal where the card that arrives has somewhere else it could go.
        {
            quint32 seed = 0;
            Move twice;
            for (quint32 candidate = 1; !seed && candidate < 5000; ++candidate) {
                Game game(candidate);
                const auto hint = game.hint();
                if (!hint || hint->from < Tableau || hint->to < Tableau || hint->count != 1) continue;
                QVERIFY(game.play(hint->from, hint->to, hint->count));
                if (game.bestTarget(hint->to, int(game.pile(hint->to).size()) - 1) >= 0) { seed = candidate; twice = *hint; }
            }
            QVERIFY(seed);
            backend.newGame(seed);
            QTest::qWait(50);
            QTest::mouseClick(window, Qt::LeftButton, {}, centre(twice.from));
            QCOMPARE(backend.selectedPile(), twice.from);
            // Lower down the target, where the card arrives, so the second click lands on it.
            QTest::mouseDClick(window, Qt::LeftButton, {}, centre(twice.to) + QPoint(0, int(table->property("upStep").toReal()) + 12));
            QCOMPARE(backend.moves(), 1);
            QCOMPARE(backend.game().moves().back(), twice);
            backend.newGame(transferSeed());
            QTest::qWait(50);
        }

        // A double click sends the card to the best place it can go.
        QTest::mouseDClick(window, Qt::LeftButton, {}, from);
        QCOMPARE(backend.moves(), 1);
        QCOMPARE(backend.game().moves().back().from, move.from);

        // Winning shows the way to another deal.
        auto *panel = window->findChild<QQuickItem *>("wonPanel");
        QVERIFY(panel && !panel->isVisible());
        backend.newGame(winnable());
        QVERIFY(playOut(backend));
        QVERIFY(backend.won());
        QTRY_VERIFY(panel->isVisible());
        auto *again = window->findChild<QQuickItem *>("dealAgainButton");
        QVERIFY(again);
        QTest::mouseClick(window, Qt::LeftButton, {}, again->mapToScene(QPointF(again->width() / 2, again->height() / 2)).toPoint());
        QVERIFY(!backend.won());
        QCOMPARE(backend.moves(), 0);
        QTRY_VERIFY(!panel->isVisible());
        // Every icon answers the pointer, which is what brings its tooltip up.
        for (const char *name : {"undoButton", "hintButton", "newGameButton", "wordmark"}) {
            auto *icon = window->findChild<QQuickItem *>(name);
            QVERIFY2(icon, name);
            const QPoint over = icon->mapToScene(QPointF(icon->width() / 2, icon->height() / 2)).toPoint();
            QTest::mouseMove(window, over - QPoint(2, 2));
            QTest::mouseMove(window, over);
            QTRY_VERIFY2(icon->property("hovered").toBool(), name);
            QVERIFY2(!icon->property("name").toString().isEmpty() || QByteArray(name) == "wordmark", name);
        }
        // The series is picked from the footer's row of small cards.
        auto *swatch = findItem(window->contentItem(), "series-2");
        QVERIFY(swatch);
        QTest::mouseClick(window, Qt::LeftButton, {}, swatch->mapToScene(QPointF(swatch->width() / 2, swatch->height() / 2)).toPoint());
        QCOMPARE(backend.series(), 2);
    }

    void aGameThatIsNotBeingSavedSaysSo() {
        QTemporaryDir dir;
        const QString path = dir.filePath("game.json");
        QVERIFY(write(path, "not json"));
        Stage stage(dir.path(), path);
        QVERIFY2(stage.window, qPrintable(stage.warnings.join('\n')));
        auto *mark = stage.window->findChild<QQuickItem *>("unsavedMark");
        QVERIFY(mark && mark->isVisible());
        QVERIFY(!stage.backend.error().isEmpty());
        // Dismissing the message leaves the mark, since nothing is being written still.
        stage.backend.dismissError();
        QVERIFY(mark->isVisible());
        stage.backend.draw();
        QVERIFY(mark->isVisible());
        // A new game replaces the damaged save, and the mark goes.
        QTest::keyClick(stage.window, Qt::Key_N);
        QVERIFY(stage.backend.saveHealthy());
        QTRY_VERIFY(!mark->isVisible());
        QCOMPARE(readCatalog(path)["version"].toInt(), 1);
    }

    void windowMirrorsForArabic() {
        QTemporaryDir dir;
        QVERIFY(write(dir.path() + "/language", "ar\n"));
        Stage stage(dir.path());
        QVERIFY2(stage.window, qPrintable(stage.warnings.join('\n')));
        QQuickWindow *window = stage.window;
        QCOMPARE(QGuiApplication::layoutDirection(), Qt::RightToLeft);
        auto *title = window->findChild<QQuickItem *>("wordmark");
        auto *undo = window->findChild<QQuickItem *>("undoButton");
        auto *table = window->findChild<QQuickItem *>("table");
        QVERIFY(title && undo && table);
        // The footer reads from the right; the table still reads from the stock on the left.
        QTRY_VERIFY(title->mapToScene(QPointF(0, 0)).x() > undo->mapToScene(QPointF(0, 0)).x());
        auto *stock = findItem(window->contentItem(), "slot-0");
        auto *lastColumn = findItem(window->contentItem(), "slot-12");
        QVERIFY(stock && lastColumn && stock->x() < lastColumn->x());
        // Each card still reads rank first, then suit.
        auto *shown = findItem(window->contentItem(), QString("card-%1").arg(stage.backend.game().pile(Tableau + 6).back().id));
        QVERIFY(shown);
        auto *rank = shown->findChild<QQuickItem *>("rank");
        auto *pip = shown->findChild<QQuickItem *>("pip");
        QVERIFY(rank && pip && rank->isVisible());
        QVERIFY(rank->mapToScene(QPointF(0, 0)).x() < pip->mapToScene(QPointF(0, 0)).x());
        auto *dialog = window->findChild<QObject *>("help");
        QCOMPARE(dialog->property("title").toString(), QString::fromUtf8("في متناول يدك"));
        QVERIFY(QMetaObject::invokeMethod(dialog, "open"));
        QTRY_VERIFY(dialog->property("opened").toBool());
        QTest::qWait(50);
        QVERIFY(QMetaObject::invokeMethod(dialog, "close"));
        QTRY_VERIFY(!dialog->property("visible").toBool());
        QGuiApplication::setLayoutDirection(Qt::LeftToRight);
        QLocale::setDefault(QLocale::c());
    }
};

QTEST_MAIN(CardsTests)
#include "cards_tests.moc"

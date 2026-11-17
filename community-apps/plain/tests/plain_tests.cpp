#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QElapsedTimer>
#include <QJsonObject>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QSemaphore>
#include <QThread>
#include <QLocalServer>
#include <QLocalSocket>
#include <QMap>
#include <QQmlComponent>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickStyle>
#include <QQuickView>
#include <QQuickTextDocument>
#include <QRegularExpression>
#include <QSet>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTextCursor>
#include <QTextBlock>
#include <QTextLayout>
#include <QTextDocument>
#include <QtTest>

#include <sys/stat.h>
#include <sys/types.h>
#include <signal.h>
#include <unistd.h>

#include "arguments.h"
#include "document.h"
#include "editing.h"
#include "filetree.h"
#include "launcher.h"
#include "portalfilepicker.h"
#include "highlighter.h"
#include "theme.h"
#include "translator.h"

namespace {

// The folder of the app's sources, where its catalogs live.
// Delete as a keyboard sends it: with the DEL character as its text,
// which QTest::keyClick leaves out.
void pressDelete(QWindow *window) {
    for (QEvent::Type type : {QEvent::KeyPress, QEvent::KeyRelease}) {
        QKeyEvent event(type, Qt::Key_Delete, Qt::NoModifier, QString(QChar(0x7f)));
        QGuiApplication::sendEvent(window, &event);
    }
}

QString sourceFolder() {
    return QFileInfo(QFINDTESTDATA("../src/main.cpp")).absolutePath();
}

// A source file with its comments left out (their examples aren't calls)
// and its strings kept whole, so neither hides the other.
QString withoutComments(const QString &text, bool cpp) {
    QString out;
    for (qsizetype i = 0; i < text.size();) {
        const QChar c = text.at(i);
        if (text.mid(i, 2) == "//") {
            const qsizetype end = text.indexOf('\n', i);
            i = end < 0 ? text.size() : end;
        } else if (text.mid(i, 2) == "/*") {
            const qsizetype end = text.indexOf("*/", i + 2);
            i = end < 0 ? text.size() : end + 2;
        } else if (cpp && c == '"' && i > 0 && text.at(i - 1) == 'R') {
            // A raw string holds quotes of its own; it's no translation, so it's left out whole.
            const qsizetype open = text.indexOf('(', i);
            const QString close = ')' + text.mid(i + 1, open - i - 1) + '"';
            out += "\"\"";
            i = text.indexOf(close, open) + close.size();
        } else if (c == '"' || c == '\'' || c == '`') {
            qsizetype end = i + 1;
            while (end < text.size() && text.at(end) != c)
                end += text.at(end) == '\\' ? 2 : 1;
            out += text.mid(i, end + 1 - i);
            i = end + 1;
        } else {
            out += c;
            ++i;
        }
    }
    return out;
}

// A literal's text as the language reads it.
QString unescaped(const QString &literal) {
    QString out;
    for (qsizetype i = 0; i < literal.size(); ++i) {
        QChar c = literal.at(i);
        if (c == '\\' && i + 1 < literal.size()) {
            c = literal.at(++i);
            c = c == 'n' ? QChar('\n') : c == 't' ? QChar('\t') : c;
        }
        out += c;
    }
    return out;
}

// Every text the sources hand to qsTr(), tr() or QT_TR_NOOP(), and whether
// any call also passes it a count (its third argument). C++'s adjacent
// literals are one text. A call whose text isn't a literal can't be in a
// catalog, and is reported in `problems`.
QMap<QString, bool> translatables(const QString &folder, QStringList *problems) {
    static const QRegularExpression call(R"(\b(qsTr|tr|QT_TR_NOOP)\s*\()");
    static const QRegularExpression literal(R"(^\s*(["'])((?:\\.|(?!\1).)*)\1)",
                                            QRegularExpression::DotMatchesEverythingOption);
    QMap<QString, bool> found;
    for (const QFileInfo &info : QDir(folder).entryInfoList({"*.qml", "*.js", "*.cpp", "*.h"}, QDir::Files)) {
        QFile file(info.filePath());
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const bool cpp = info.suffix() == "cpp" || info.suffix() == "h";
        const QString code = withoutComments(QString::fromUtf8(file.readAll()), cpp);
        for (auto calls = call.globalMatch(code); calls.hasNext();) {
            const auto match = calls.next();
            qsizetype at = match.capturedEnd();
            QString text;
            bool isLiteral = false;
            for (auto part = literal.match(code.mid(at)); part.hasMatch(); part = literal.match(code.mid(at))) {
                text += unescaped(part.captured(2));
                at += part.capturedEnd();
                isLiteral = true;
                if (!cpp)
                    break;
            }
            // A text the call builds, like qsTr("Saved " + name), is no literal either.
            while (at < code.size() && code.at(at).isSpace())
                ++at;
            if (isLiteral && at < code.size() && code.at(at) != ',' && code.at(at) != ')')
                isLiteral = false;
            if (!isLiteral) {
                *problems << info.fileName() + ": not a literal: " + code.mid(match.capturedStart(), 60);
                continue;
            }
            // The arguments after the text, up to the call's closing parenthesis.
            int depth = 0, commas = 0;
            for (; at < code.size(); ++at) {
                const QChar c = code.at(at);
                if (c == '"' || c == '\'') {
                    for (++at; at < code.size() && code.at(at) != c; at += code.at(at) == '\\' ? 2 : 1) { }
                } else if (c == '(' || c == '[' || c == '{') {
                    ++depth;
                } else if (c == ')' || c == ']' || c == '}') {
                    if (depth-- == 0)
                        break;
                } else if (c == ',' && depth == 0) {
                    ++commas;
                }
            }
            found[text] = found.value(text) || commas >= 2;
        }
    }
    return found;
}

QJsonObject readCatalog(const QString &path, QStringList *problems) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        *problems << path + ": can't be read";
        return {};
    }
    QJsonParseError error;
    const QJsonDocument document = QJsonDocument::fromJson(file.readAll(), &error);
    if (!document.isObject())
        *problems << path + ": not a JSON object: " + error.errorString();
    return document.object();
}

// The placeholders in a text, in order: %1 to %9, and the count (%n, %Ln).
QStringList placeholders(const QString &text) {
    static const QRegularExpression placeholder("%L?[1-9n]");
    QStringList found;
    for (auto it = placeholder.globalMatch(text); it.hasNext();)
        found << it.next().captured();
    found.sort();
    return found;
}

// Omarchy's 49 translations (default/i18n/locales.json), as the sync's LANGUAGES has them.
const QStringList &languageCodes() {
    static const QStringList codes{"ar", "bg", "bn", "ca", "cs", "da", "de", "el", "es-MX", "et", "fa", "fi", "fil",
                                   "fr", "ga", "he", "hi", "hr", "hu", "id", "is", "it", "ja", "ko", "lt", "lv", "ms",
                                   "nl", "no", "pl", "pt", "pt-BR", "ro", "ru", "si", "sk", "sl", "sr", "sv", "sw",
                                   "ta", "th", "tr", "uk", "ur", "uz", "vi", "zh-CN", "zh-TW"};
    return codes;
}

// What's wrong with the translations in `folder`, measured against its
// en.json: an unknown language, empty or broken translations, and plural
// forms that don't fit the language's rule. A string a catalog lacks, or one
// en.json no longer has, is work for the translation sync
// (scripts/i18n-sync.py), not a problem: the window shows the English
// meanwhile, so a change to the English never waits on 49 languages.
QStringList catalogProblems(const QString &folder) {
    const QStringList &codes = languageCodes();
    QStringList problems;
    const QJsonObject english = readCatalog(folder + "/en.json", &problems);
    for (const QFileInfo &file : QDir(folder).entryInfoList({"*.json"}, QDir::Files)) {
        const QString code = file.completeBaseName();
        if (code == "en")
            continue;
        if (!codes.contains(code)) {
            problems << file.fileName() + ": not one of Omarchy's language codes";
            continue;
        }
        const QJsonObject catalog = readCatalog(file.filePath(), &problems);

        // The categories the language's rule reaches, and "other" always.
        QSet<QString> categories{"other", Translator::pluralCategory(code, 1000000)};
        for (long long n = 0; n <= 1000; ++n)
            categories << Translator::pluralCategory(code, n);

        for (auto it = english.begin(); it != english.end(); ++it) {
            const QJsonValue translated = catalog.value(it.key());
            const QString where = code + ": " + it.key() + ": ";
            if (translated.isUndefined())
                continue;
            if (it.value().isString()) {
                if (!translated.isString() || translated.toString().trimmed().isEmpty())
                    problems << where + "needs a translation";
                else if (placeholders(translated.toString()) != placeholders(it.key()))
                    problems << where + "has other placeholders than the English";
                continue;
            }
            const QJsonObject forms = translated.toObject();
            const QStringList given = forms.keys();
            if (!translated.isObject() || QSet<QString>(given.begin(), given.end()) != categories) {
                QStringList wanted(categories.begin(), categories.end());
                wanted.sort();
                problems << where + "needs exactly the plural forms " + wanted.join(", ");
                continue;
            }
            // Every form says every placeholder; one that isn't "other" may
            // say the number in words instead of the count.
            const QStringList all = placeholders(it.value().toObject().value("other").toString());
            const QSet<QString> needed(all.begin(), all.end());
            QSet<QString> fixed = needed;
            fixed.remove("%n");
            fixed.remove("%Ln");
            for (auto form = forms.begin(); form != forms.end(); ++form) {
                const QStringList has = placeholders(form.value().toString());
                const QSet<QString> present(has.begin(), has.end());
                if (form.value().toString().trimmed().isEmpty())
                    problems << where + form.key() + " needs a translation";
                else if (!(form.key() == "other" ? present == needed : present.contains(fixed) && needed.contains(present)))
                    problems << where + form.key() + " has other placeholders than the English";
            }
        }
    }
    return problems;
}

}

class PlainTests : public QObject {
    Q_OBJECT

private slots:
    // Before any QML loads, as Plain itself does.
    void initTestCase() { QQuickStyle::setStyle("Material"); }

    // Decoding.

    void decodesLfAndCrlf()
    {
        auto lf = Document::decode("a\nb\n");
        QVERIFY(lf.ok);
        QVERIFY(!lf.crlf);
        QCOMPARE(lf.text, QString("a\nb\n"));

        auto crlf = Document::decode("a\r\nb\r\n");
        QVERIFY(crlf.ok);
        QVERIFY(crlf.crlf);
        QVERIFY(!crlf.mixed);
        QCOMPARE(crlf.text, QString("a\nb\n"));

        auto mixed = Document::decode("a\r\nb\r\nc\n");
        QVERIFY(mixed.ok);
        QVERIFY(mixed.crlf);
        QVERIFY(mixed.mixed);
    }

    void refusesWhatCantRoundTrip()
    {
        QVERIFY(!Document::decode(QByteArray("a\0b", 3)).ok);
        QVERIFY(!Document::decode("caf\xE9\n").ok);           // Latin-1, not UTF-8
        QVERIFY(!Document::decode("a\rb\n").ok);              // lone CR
        QVERIFY(!Document::decode("a\xEF\xB7\xAF" "b").ok);   // U+FDEF, U+2029's stand-in
        // U+FDD0 and U+FDD1, which Qt's text document saves as line breaks.
        QVERIFY(!Document::decode("a\xEF\xB7\x90" "b\n").ok);
        QVERIFY(!Document::decode("a\xEF\xB7\x91" "b\n").ok);
        QVERIFY(Document::decode("").ok);
        // A sequence cut off at the end, which a stateful decoder holds back
        // without an error, so saving would drop it.
        QVERIFY(!Document::decode("a\xE2\x82").ok);
    }

    void keepsTheBom()
    {
        auto d = Document::decode("\xEF\xBB\xBFkey = 1\n");
        QVERIFY(d.ok);
        QVERIFY(d.bom);
        QCOMPARE(d.text, QString("key = 1\n"));
    }

    void roundTripsByteForByte_data()
    {
        QTest::addColumn<QByteArray>("bytes");
        QTest::newRow("lf") << QByteArray("a = 1\nb = 2\n");
        QTest::newRow("no final newline") << QByteArray("a = 1\nb = 2");
        QTest::newRow("blank final lines") << QByteArray("a\n\n\n");
        QTest::newRow("crlf") << QByteArray("[s]\r\nk=v\r\n");
        QTest::newRow("bom") << QByteArray("\xEF\xBB\xBF" "x\n");
        QTest::newRow("double bom") << QByteArray("\xEF\xBB\xBF\xEF\xBB\xBF" "x\n");
        QTest::newRow("nbsp and tabs") << QByteArray("a\xC2\xA0" "b\n\tc\n");
        QTest::newRow("line separator") << QByteArray("a\xE2\x80\xA8" "b\n");
        QTest::newRow("paragraph separator") << QByteArray("a\xE2\x80\xA9" "b\n");
        QTest::newRow("empty") << QByteArray();
        QTest::newRow("only newline") << QByteArray("\n");
        QTest::newRow("unicode") << QByteArray("名前 = \"ø\" # 🎉\n");
    }

    void roundTripsByteForByte()
    {
        QFETCH(QByteArray, bytes);
        const auto decoded = Document::decode(bytes);
        QVERIFY(decoded.ok);
        QTextDocument document;
        document.setPlainText(decoded.text);
        QCOMPARE(Document::encode(&document, decoded.bom, decoded.crlf), bytes);
    }

    void asksBeforeOpeningLargeFiles()
    {
        QVERIFY(!Document::tooLarge(1000, "a\nb\n"));
        QVERIFY(Document::tooLarge(Document::LargeFileBytes + 1, "a"));
        QVERIFY(Document::tooLarge(30000, QString(Document::LongLineChars + 1, 'x')));
        QVERIFY(Document::tooLarge(30000, "a\n" + QString(Document::LongLineChars + 1, 'x')));

        QTemporaryDir dir;
        const QString path = dir.filePath("long.json");
        write(path, QByteArray(Document::LongLineChars + 10, 'x'));
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(!doc.open(path));
        QCOMPARE(doc.problem(), QString("TooLarge"));
        QVERIFY(text.isEmpty());
        doc.openAnyway();
        QCOMPARE(doc.problem(), QString("None"));
        QCOMPARE(text.characterCount() - 1, Document::LongLineChars + 10);
        QVERIFY(doc.editable());
    }

    void detectsIndentation()
    {
        QCOMPARE(Document::detectIndent("a {\n    b {\n        c\n    }\n}\n"), QString("    "));
        QCOMPARE(Document::detectIndent("a:\n  b:\n    c: 1\n  d: 2\n"), QString("  "));
        QCOMPARE(Document::detectIndent("a {\n\tb\n\tc\n}\n"), QString("\t"));
        QCOMPARE(Document::detectIndent("flat\nfile\n"), QString());
    }

    // Opening.

    void opensAndRefuses()
    {
        QTemporaryDir dir;
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);

        QVERIFY(!doc.open(dir.filePath("missing/new.conf")));
        QCOMPARE(doc.problem(), QString("NotFound"));

        QVERIFY(!doc.open(dir.path()));
        QCOMPARE(doc.problem(), QString("NotRegular"));

        QVERIFY(::mkfifo(QFile::encodeName(dir.filePath("fifo")).constData(), 0600) == 0);
        QVERIFY(!doc.open(dir.filePath("fifo")));
        QCOMPARE(doc.problem(), QString("NotRegular"));

        write(dir.filePath("binary"), QByteArray("\x7F" "ELF\0\0", 6));
        QVERIFY(!doc.open(dir.filePath("binary")));
        QCOMPARE(doc.problem(), QString("NotText"));
        QVERIFY(!doc.editable());

        write(dir.filePath("secret"), "x\n");
        QFile::setPermissions(dir.filePath("secret"), QFile::WriteOwner);
        if (::geteuid() != 0) {
            QVERIFY(!doc.open(dir.filePath("secret")));
            QCOMPARE(doc.problem(), QString("NotReadable"));
        }

        write(dir.filePath("ok.toml"), "a = 1\r\nb = 2\n");
        QVERIFY(doc.open(dir.filePath("ok.toml")));
        QCOMPARE(doc.problem(), QString("MixedEndings"));
        QCOMPARE(doc.language(), QString("toml"));
        QVERIFY(!doc.modified());
    }

    // Saving.

    void savesAtomicallyKeepingTheMode()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("a.conf");
        write(path, "a = 1\n");
        QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup);
        const ino_t before = inode(path);

        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        append(&text, "b = 2\n");
        QVERIFY(doc.modified());
        QVERIFY(doc.save());
        QVERIFY(!doc.modified());
        QCOMPARE(read(path), QByteArray("a = 1\nb = 2\n"));
        QCOMPARE(mode(path), 0640);
        QVERIFY(inode(path) != before); // replaced, not rewritten
    }

    void savesThroughSymlinks()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("store");
        const QString target = dir.filePath("store/real.lua"), link = dir.filePath("link.lua");
        write(target, "x = 1\n");
        QVERIFY(QFile::link(target, link));

        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(link));
        QCOMPARE(doc.path(), link);
        append(&text, "y = 2\n");
        QVERIFY(doc.save());
        QVERIFY(QFileInfo(link).isSymLink());
        QCOMPARE(read(target), QByteArray("x = 1\ny = 2\n"));
    }

    void asksWhenALinkIsRetargeted()
    {
        QTemporaryDir dir;
        const QString one = dir.filePath("one"), two = dir.filePath("two"), link = dir.filePath("link");
        write(one, "1\n");
        write(two, "2\n");
        QVERIFY(QFile::link(one, link));

        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(link));
        QFile::remove(link);
        QVERIFY(QFile::link(two, link));
        append(&text, "more\n");
        QVERIFY(!doc.save());
        QCOMPARE(doc.problem(), QString("Retargeted"));
        QCOMPARE(read(two), QByteArray("2\n"));
        QCOMPARE(read(one), QByteArray("1\n"));
    }

    void neverSavesOverAnUnseenVersion()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("a.conf");
        write(path, "a = 1\n");

        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        // Same size, different content: mtime and size wouldn't catch it.
        write(path, "a = 2\n");
        append(&text, "mine\n");
        QVERIFY(!doc.save());
        QCOMPARE(doc.problem(), QString("Conflict"));
        QCOMPARE(read(path), QByteArray("a = 2\n"));

        QVERIFY(doc.overwrite());
        QCOMPARE(read(path), QByteArray("a = 1\nmine\n"));
    }

    void asksBeforeRecreatingADeletedFile()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("gone.conf");
        write(path, "a\n");
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        QFile::remove(path);
        append(&text, "b\n");
        QVERIFY(!doc.save());
        QCOMPARE(doc.problem(), QString("DeletedOnDisk"));
        QVERIFY(!QFile::exists(path));
        QVERIFY(doc.overwrite());
        QCOMPARE(read(path), QByteArray("a\nb\n"));
    }

    void asksBeforeWritingInPlace()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("linked.conf"), other = dir.filePath("other-name.conf");
        write(path, "a\n");
        QVERIFY(::link(QFile::encodeName(path).constData(), QFile::encodeName(other).constData()) == 0);

        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        append(&text, "b\n");
        QVERIFY(!doc.save());
        QCOMPARE(doc.problem(), QString("NeedsInPlace"));
        QCOMPARE(read(path), QByteArray("a\n"));

        QVERIFY(doc.overwriteInPlace());
        QCOMPARE(read(other), QByteArray("a\nb\n")); // the hard link survived
        QVERIFY(!doc.modified());
    }

    // Overwriting in place, after the question, still never saves over a
    // version of the file the user hasn't seen.
    void overwritingInPlaceChecksTheDiskFirst()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("linked.conf"), other = dir.filePath("other.conf");
        write(path, "a\n");
        QVERIFY(::link(QFile::encodeName(path).constData(), QFile::encodeName(other).constData()) == 0);
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        append(&text, "mine\n");
        QVERIFY(!doc.save());
        QCOMPARE(doc.problem(), QString("NeedsInPlace"));

        write(other, "theirs\n");
        QVERIFY(!doc.overwriteInPlace());
        QCOMPARE(doc.problem(), QString("Conflict"));
        QCOMPARE(read(path), QByteArray("theirs\n"));
    }

    void stopsWhenTheDiskCantBeChecked()
    {
        if (::geteuid() == 0)
            QSKIP("root can read anything");
        QTemporaryDir dir;
        const QString path = dir.filePath("a.conf");
        write(path, "a\n");
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        QFile::setPermissions(path, QFile::WriteOwner);
        append(&text, "b\n");
        QVERIFY(!doc.save());
        QCOMPARE(doc.problem(), QString("SaveFailed"));
        QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner);
        QCOMPARE(read(path), QByteArray("a\n"));
    }

    // A reload that can't use what's on disk keeps the editor as it was.
    void failedReloadKeepsTheEdits()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("a.conf");
        write(path, "a\n");
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        append(&text, "mine\n");
        write(path, QByteArray("\xFF\xFE", 2));
        doc.reload();
        QCOMPARE(doc.problem(), QString("NotText"));
        QCOMPARE(text.toPlainText(), QString("a\nmine\n"));
        QVERIFY(doc.modified());
        QVERIFY(doc.editable());

        QFile::remove(path);
        doc.reload();
        QCOMPARE(doc.problem(), QString("DeletedOnDisk"));
        QCOMPARE(text.toPlainText(), QString("a\nmine\n"));
    }

    void failedSaveAsKeepsTheFile()
    {
        if (::geteuid() == 0)
            QSKIP("root can write anything");
        QTemporaryDir dir;
        const QString path = dir.filePath("a.conf");
        write(path, "a\n");
        QDir(dir.path()).mkdir("sealed");
        QFile::setPermissions(dir.filePath("sealed"), QFile::ReadOwner | QFile::ExeOwner);
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        QVERIFY(!doc.saveAsUrl(QUrl::fromLocalFile(dir.filePath("sealed/b.conf"))));
        QCOMPARE(doc.path(), path);
        QFile::setPermissions(dir.filePath("sealed"), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    }

    // A refused file leaves the editor empty; Save As over it, which the
    // dialog suggests, would truncate it.
    void saveAsNeedsAFileToSave()
    {
        QTemporaryDir dir;
        const QString binary = dir.filePath("binary");
        write(binary, QByteArray("\x7F" "ELF\0\0", 6));
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(!doc.open(binary));
        QVERIFY(!doc.saveAsUrl(QUrl::fromLocalFile(binary)));
        QCOMPARE(read(binary), QByteArray("\x7F" "ELF\0\0", 6));

        if (::geteuid() == 0)
            return;
        // A file the user can't write is loaded, and Save As is its way out.
        const QString locked = dir.filePath("locked.conf"), copy = dir.filePath("copy.conf");
        write(locked, "a = 1\n");
        QFile::setPermissions(locked, QFile::ReadOwner);
        QVERIFY(doc.open(locked));
        QVERIFY(doc.locked());
        QVERIFY(doc.saveAsUrl(QUrl::fromLocalFile(copy)));
        QCOMPARE(read(copy), QByteArray("a = 1\n"));
    }

    // A rename would hand the file to the user's own group.
    void asksBeforeChangingTheGroup()
    {
        gid_t groups[64];
        const int count = ::getgroups(64, groups);
        gid_t other = ::getegid();
        for (int i = 0; i < count; ++i)
            if (groups[i] != ::getegid())
                other = groups[i];
        if (other == ::getegid())
            QSKIP("needs a second group to give the file");

        QTemporaryDir dir;
        const QString path = dir.filePath("shared.conf");
        write(path, "a\n");
        QVERIFY(::chown(QFile::encodeName(path).constData(), -1, other) == 0);
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        append(&text, "b\n");
        QVERIFY(!doc.save());
        QCOMPARE(doc.problem(), QString("NeedsInPlace"));
        QVERIFY(doc.overwriteInPlace());
        struct stat st;
        QVERIFY(::stat(QFile::encodeName(path).constData(), &st) == 0);
        QCOMPARE(st.st_gid, other);
    }

    void asksBeforeDroppingSpecialBits()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("tool.sh");
        write(path, "echo hi\n");
        QVERIFY(::chmod(QFile::encodeName(path).constData(), 02755) == 0);
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        append(&text, "echo bye\n");
        QVERIFY(!doc.save());
        QCOMPARE(doc.problem(), QString("NeedsInPlace"));
        QVERIFY(doc.overwriteInPlace());
        QCOMPARE(mode(path), 02755);
    }

    void unlocksWhenTheFileBecomesWritable()
    {
        if (::geteuid() == 0)
            QSKIP("root can write anything");
        QTemporaryDir dir;
        const QString path = dir.filePath("a.conf");
        write(path, "a = 1\n");
        QFile::setPermissions(path, QFile::ReadOwner);
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        QVERIFY(doc.locked());

        QFile::setPermissions(path, QFile::ReadOwner | QFile::WriteOwner);
        QTRY_VERIFY(!doc.locked());
        QVERIFY(doc.editable());
        QCOMPARE(doc.problem(), QString("None"));
    }

    void reportsFilesItCantWrite()
    {
        if (::geteuid() == 0)
            QSKIP("root can write anything");
        QTemporaryDir dir;
        const QString path = dir.filePath("ro.conf");
        write(path, "a\n");
        QFile::setPermissions(path, QFile::ReadOwner);
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        QCOMPARE(doc.problem(), QString("NotWritable"));
        QVERIFY(!doc.editable());
        QVERIFY(doc.locked());
        QVERIFY(!doc.save());
        QCOMPARE(read(path), QByteArray("a\n"));

        // Writable at open, read-only by save time: the save says so.
        const QString later = dir.filePath("later.conf");
        write(later, "a\n");
        QVERIFY(doc.open(later));
        QVERIFY(doc.editable());
        QVERIFY(!doc.locked());
        QFile::setPermissions(later, QFile::ReadOwner);
        append(&text, "b\n");
        QVERIFY(!doc.save());
        QCOMPARE(doc.problem(), QString("NotWritable"));

        // A new file in a folder the user can't write opens locked, too.
        QDir(dir.path()).mkdir("sealed");
        QFile::setPermissions(dir.filePath("sealed"), QFile::ReadOwner | QFile::ExeOwner);
        QVERIFY(doc.open(dir.filePath("sealed/new.conf")));
        QVERIFY(doc.locked());
        QVERIFY(!doc.editable());
        QCOMPARE(doc.problem(), QString("NotWritable"));
        QFile::setPermissions(dir.filePath("sealed"), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
    }

    // Qt Quick draws only the visible lines of a long text, but turns that on
    // only when the text arrives through the TextEdit itself. Loaded behind
    // its back, every keystroke in a 10,000-line file redrew it all.
    void longFilesDrawOnlyWhatsVisible()
    {
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData("import QtQuick\nTextEdit { textFormat: TextEdit.PlainText }", {});
        std::unique_ptr<QQuickItem> edit(qobject_cast<QQuickItem *>(component.create()));
        QVERIFY(edit);

        QTemporaryDir dir;
        QByteArray lines;
        for (int i = 0; i < 2000; ++i)
            lines += "key_" + QByteArray::number(i) + " = value\n";
        write(dir.filePath("long.conf"), lines);
        Document doc;
        doc.attach(edit.get());
        QVERIFY(doc.open(dir.filePath("long.conf")));
        QVERIFY(edit->flags() & QQuickItem::ItemObservesViewport);

        // A reload replaces the text undoably, past the text property.
        write(dir.filePath("grows.conf"), "a = 1\n");
        QVERIFY(doc.open(dir.filePath("grows.conf")));
        QVERIFY(!(edit->flags() & QQuickItem::ItemObservesViewport));
        write(dir.filePath("grows.conf"), lines);
        doc.reload();
        QCOMPARE(edit->property("text").toString().size(), lines.size());
        QVERIFY(edit->flags() & QQuickItem::ItemObservesViewport);

        // Shrinking it keeps the flag, since undo brings the long text back.
        write(dir.filePath("grows.conf"), "a = 1\n");
        doc.reload();
        undo(edit.get());
        QCOMPARE(edit->property("text").toString().size(), lines.size());
        QVERIFY(edit->flags() & QQuickItem::ItemObservesViewport);
    }

    void createsNewFiles()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("new.yaml");
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));
        QCOMPARE(doc.problem(), QString("None"));
        QCOMPARE(doc.indentUnit(), QString("  "));
        append(&text, "a: 1");
        QVERIFY(doc.save());
        QCOMPARE(read(path), QByteArray("a: 1"));
    }

    void followsTheDisk()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("live.conf");
        write(path, "a = 1\n");
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));

        // No unsaved changes: reloads quietly, and the reload can be undone.
        replace(path, "a = 2\n");
        QTRY_COMPARE(text.toPlainText(), QString("a = 2\n"));
        QVERIFY(!doc.modified());
        QCOMPARE(doc.problem(), QString("None"));

        // Unsaved changes: asks.
        append(&text, "mine\n");
        replace(path, "a = 3\n");
        QTRY_COMPARE(doc.problem(), QString("ChangedOnDisk"));
        QVERIFY(text.toPlainText().contains("mine"));
        doc.keepMine();
        QVERIFY(doc.save());
        QCOMPARE(read(path), QByteArray("a = 2\nmine\n"));

        // Plain's own save doesn't count as news.
        QTest::qWait(250);
        QCOMPARE(doc.problem(), QString("None"));
    }

    // A file that grows past the limit while open is put aside, and opening
    // it anyway replaces the text as one undoable step, like any reload.
    void openAnywayAfterAReloadCanBeUndone()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("grows.conf");
        write(path, "a = 1\n");
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));

        replace(path, QByteArray(Document::LargeFileBytes + 1, 'x'));
        QTRY_COMPARE(doc.problem(), QString("TooLarge"));
        QCOMPARE(text.toPlainText(), QString("a = 1\n"));
        append(&text, "mine\n");
        doc.openAnyway();
        QCOMPARE(text.characterCount() - 1, Document::LargeFileBytes + 1);
        text.undo();
        QCOMPARE(text.toPlainText(), QString("a = 1\nmine\n"));
    }

    // Reading a FIFO waits for a writer, which would freeze the window.
    void neverReadsAFifoThatReplacedTheFile()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath("a.conf");
        write(path, "a = 1\n");
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(path));

        const QString fifo = dir.filePath("fifo");
        QVERIFY(::mkfifo(QFile::encodeName(fifo).constData(), 0600) == 0);
        QVERIFY(::rename(QFile::encodeName(fifo).constData(), QFile::encodeName(path).constData()) == 0);
        QTRY_COMPARE(doc.problem(), QString("NotRegular"));
        QCOMPARE(text.toPlainText(), QString("a = 1\n"));
        QVERIFY(!doc.save());
    }

    // Arguments.

    void parsesArguments()
    {
        auto a = Arguments::parse({"plain", "+12", "--", "-weird name"});
        QCOMPARE(a.line, 12);
        QCOMPARE(a.path, QString("-weird name"));
        QVERIFY(a.error.isEmpty());

        QCOMPARE(Arguments::parse({"plain", "--", "+5"}).path, QString("+5"));
        QCOMPARE(Arguments::parse({"plain", "file:///etc/hosts"}).path, QString("/etc/hosts"));
        QCOMPARE(Arguments::parse({"plain", "a:12"}).path, QString("a:12"));
        QVERIFY(!Arguments::parse({"plain", "https://example.com/x"}).error.isEmpty());
        QVERIFY(!Arguments::parse({"plain", "a", "b"}).error.isEmpty());
        QVERIFY(!Arguments::parse({"plain", "--wait", "a"}).error.isEmpty());
        QVERIFY(Arguments::parse({"plain"}).path.isEmpty());
        // After --, even a name that looks like a URL is a filename.
        QCOMPARE(Arguments::parse({"plain", "--", "a://b"}).path, QString("a://b"));
        QVERIFY(Arguments::parse({"plain", "--", "a://b"}).error.isEmpty());
    }

    // The sidebar's files.

    void listsFoldersFirstWithoutDotfiles()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("b-folder/inner");
        QDir(dir.path()).mkpath("A-folder");
        QDir(dir.path()).mkpath(".git");
        write(dir.filePath("z.conf"), "");
        write(dir.filePath("a.lua"), "");
        write(dir.filePath("file10.toml"), "");
        write(dir.filePath("file9.toml"), "");
        write(dir.filePath(".hidden"), "");
        write(dir.filePath("b-folder/inside.conf"), "");

        FileTree tree;
        tree.setRoot(dir.path());
        QCOMPARE(names(tree), QStringList({"A-folder", "b-folder", "a.lua", "file9.toml", "file10.toml", "z.conf"}));
        QVERIFY(tree.isFolder(1));
        QVERIFY(!tree.isFolder(2));
        QCOMPARE(tree.data(tree.index(0), FileTree::DepthRole).toInt(), 0);
    }

    void showsHiddenFilesOnAskingOrInsideAHiddenFolder()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("home/.config/hypr");
        write(dir.filePath("home/.bashrc"), "");
        write(dir.filePath("home/notes.md"), "");
        write(dir.filePath("home/.config/hypr/.backup"), "");
        write(dir.filePath("home/.config/hypr/hyprland.lua"), "");

        FileTree tree;
        tree.setRoot(dir.filePath("home"));
        QVERIFY(!tree.showHidden());
        QCOMPARE(names(tree), QStringList({"notes.md"}));
        tree.setShowHidden(true);
        QCOMPARE(names(tree), QStringList({".config", ".bashrc", "notes.md"}));
        QVERIFY(tree.data(tree.index(0), FileTree::HiddenRole).toBool());
        QVERIFY(!tree.data(tree.index(2), FileTree::HiddenRole).toBool());

        // Started inside a hidden folder, everything shows.
        tree.setRoot(dir.filePath("home/.config/hypr"));
        QVERIFY(tree.showHidden());
        QCOMPARE(names(tree), QStringList({".backup", "hyprland.lua"}));
        tree.setRoot(dir.filePath("home"));
        QVERIFY(!tree.showHidden());
    }

    void foldsFoldersOpenAndClosed()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("hypr/scripts");
        write(dir.filePath("hypr/bindings.lua"), "");
        write(dir.filePath("hypr/scripts/run.sh"), "");
        write(dir.filePath("top.conf"), "");

        FileTree tree;
        tree.setRoot(dir.path());
        QCOMPARE(names(tree), QStringList({"hypr", "top.conf"}));

        tree.expand(0);
        QCOMPARE(names(tree), QStringList({"hypr", "scripts", "bindings.lua", "top.conf"}));
        QCOMPARE(tree.data(tree.index(2), FileTree::DepthRole).toInt(), 1);
        QCOMPARE(tree.parentOf(2), 0);
        QCOMPARE(tree.parentOf(0), -1);

        tree.expand(1);
        QCOMPARE(names(tree), QStringList({"hypr", "scripts", "run.sh", "bindings.lua", "top.conf"}));

        // Closing a folder closes those inside it, too.
        tree.toggle(0);
        QCOMPARE(names(tree), QStringList({"hypr", "top.conf"}));
        tree.toggle(0);
        QCOMPARE(names(tree), QStringList({"hypr", "scripts", "bindings.lua", "top.conf"}));
    }

    void revealsAFileUnderTheRoot()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("a/b");
        write(dir.filePath("a/b/deep.conf"), "");

        FileTree tree;
        tree.setRoot(dir.path());
        const int row = tree.reveal(dir.filePath("a/b/deep.conf"));
        QCOMPARE(row, 2);
        QCOMPARE(tree.pathAt(row), QDir::cleanPath(dir.filePath("a/b/deep.conf")));
        QCOMPARE(tree.reveal("/etc/hosts"), -1);
        QCOMPARE(tree.reveal(dir.filePath("a/missing.conf")), -1);
    }

    void findsNamesByTheirStart()
    {
        QTemporaryDir dir;
        for (const char *name : {"autostart.lua", "bindings.lua", "Bluetooth.conf", "input.lua"})
            write(dir.filePath(name), "");
        FileTree tree;
        tree.setRoot(dir.path());
        QCOMPARE(tree.find("b", 0), 1);
        QCOMPARE(tree.find("b", 2), 2);
        // Around past the end, and in any case.
        QCOMPARE(tree.find("B", 3), 1);
        QCOMPARE(tree.find("blu", 0), 2);
        QCOMPARE(tree.find("z", 0), -1);
    }

    void followsTheFolderOnDisk()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("sub");
        write(dir.filePath("one.conf"), "");

        FileTree tree;
        tree.setRoot(dir.path());
        tree.expand(0);
        QCOMPARE(names(tree), QStringList({"sub", "one.conf"}));

        write(dir.filePath("sub/new.conf"), "");
        QTRY_COMPARE(names(tree), QStringList({"sub", "new.conf", "one.conf"}));
        QFile::remove(dir.filePath("one.conf"));
        QTRY_COMPARE(names(tree), QStringList({"sub", "new.conf"}));
    }

    void deletesToTheTrash()
    {
        // The trash lives under XDG_DATA_HOME; a temporary one keeps the
        // test out of the user's.
        QTemporaryDir dir;
        const QByteArray dataHome = qgetenv("XDG_DATA_HOME");
        qputenv("XDG_DATA_HOME", QFile::encodeName(dir.filePath("data")));
        QDir(dir.path()).mkpath("data");
        QDir(dir.path()).mkpath("root/folder");
        write(dir.filePath("root/a.conf"), "a\n");
        write(dir.filePath("root/folder/b.conf"), "b\n");

        FileTree tree;
        tree.setRoot(dir.filePath("root"));
        QCOMPARE(names(tree), QStringList({"folder", "a.conf"}));
        QCOMPARE(tree.trash(dir.filePath("root/a.conf")), QString());
        QVERIFY(!QFileInfo::exists(dir.filePath("root/a.conf")));
        QCOMPARE(read(dir.filePath("data/Trash/files/a.conf")), QByteArray("a\n"));
        QCOMPARE(names(tree), QStringList({"folder"}));

        // A folder goes whole.
        QCOMPARE(tree.trash(dir.filePath("root/folder")), QString());
        QVERIFY(QFileInfo::exists(dir.filePath("data/Trash/files/folder/b.conf")));
        QCOMPARE(tree.rowCount(), 0);
        QVERIFY(!tree.trash(dir.filePath("root/folder")).isEmpty());
        // Nothing outside the tree, and never the top folder itself.
        write(dir.filePath("outside.conf"), "");
        QVERIFY(!tree.trash(dir.filePath("outside.conf")).isEmpty());
        QVERIFY(!tree.trash(dir.filePath("root")).isEmpty());
        QVERIFY(QFileInfo::exists(dir.filePath("outside.conf")));

        if (dataHome.isNull())
            qunsetenv("XDG_DATA_HOME");
        else
            qputenv("XDG_DATA_HOME", dataHome);
    }

    void movesIntoFolders()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("a/inner");
        QDir(dir.path()).mkpath("b");
        write(dir.filePath("x.conf"), "x\n");
        write(dir.filePath("b/x.conf"), "other\n");
        write(dir.filePath("y.conf"), "y\n");

        FileTree tree;
        tree.setRoot(dir.path());
        QCOMPARE(names(tree), QStringList({"a", "b", "x.conf", "y.conf"}));

        // Into a folder, which opens to show it.
        QCOMPARE(tree.move(dir.filePath("y.conf"), dir.filePath("a")).value("path").toString(), QDir::cleanPath(dir.filePath("a/y.conf")));
        QCOMPARE(read(dir.filePath("a/y.conf")), QByteArray("y\n"));
        QCOMPARE(names(tree), QStringList({"a", "inner", "y.conf", "b", "x.conf"}));

        // Never over something with the same name, or a folder into itself.
        QVERIFY(tree.move(dir.filePath("x.conf"), dir.filePath("b")).contains("error"));
        QCOMPARE(read(dir.filePath("x.conf")), QByteArray("x\n"));
        QVERIFY(tree.move(dir.filePath("a"), dir.filePath("a/inner")).contains("error"));
        QVERIFY(tree.move(dir.filePath("a"), dir.filePath("a")).contains("error"));

        // A whole folder moves, staying open.
        QCOMPARE(tree.move(dir.filePath("a"), dir.filePath("b")).value("path").toString(), QDir::cleanPath(dir.filePath("b/a")));
        QVERIFY(QFileInfo::exists(dir.filePath("b/a/y.conf")));
        QCOMPARE(names(tree), QStringList({"b", "a", "inner", "y.conf", "x.conf", "x.conf"}));
    }

    void createsFilesAndFolders()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("conf");
        write(dir.filePath("conf/a.conf"), "a\n");
        write(dir.filePath("top.lua"), "");

        FileTree tree;
        tree.setRoot(dir.path());
        tree.expand(0);
        QCOMPARE(names(tree), QStringList({"conf", "a.conf", "top.lua"}));
        // Into a folder, beside a file, or at the top with no row.
        const QString conf = QDir::cleanPath(dir.filePath("conf"));
        QCOMPARE(tree.folderAt(0), conf);
        QCOMPARE(tree.folderAt(1), conf);
        QCOMPARE(tree.folderAt(2), QDir::cleanPath(dir.path()));
        QCOMPARE(tree.folderAt(-1), QDir::cleanPath(dir.path()));

        // Never over what's there, and only a plain name.
        QVERIFY(tree.create(conf, "a.conf", false).contains("error"));
        QCOMPARE(read(dir.filePath("conf/a.conf")), QByteArray("a\n"));
        QVERIFY(tree.create(conf, "", false).contains("error"));
        QVERIFY(tree.create(conf, "x/y", false).contains("error"));
        QVERIFY(tree.create(conf, "..", true).contains("error"));

        QCOMPARE(tree.create(conf, "new.conf", false).value("path").toString(), conf + "/new.conf");
        QVERIFY(QFileInfo(dir.filePath("conf/new.conf")).isFile());
        QCOMPARE(tree.create(conf, "sub", true).value("path").toString(), conf + "/sub");
        QVERIFY(QFileInfo(dir.filePath("conf/sub")).isDir());
        QCOMPARE(names(tree), QStringList({"conf", "sub", "a.conf", "new.conf", "top.lua"}));
    }

    void renamesAndDuplicates()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("conf/inner");
        write(dir.filePath("conf/a.conf"), "a\n");
        write(dir.filePath("conf/inner/x.lua"), "x\n");
        write(dir.filePath("b.lua"), "b\n");
        write(dir.filePath(".zshrc"), "z\n");

        FileTree tree;
        tree.setRoot(dir.path());
        tree.expand(0);
        tree.expand(1);
        QCOMPARE(names(tree), QStringList({"conf", "inner", "x.lua", "a.conf", "b.lua"}));

        // A folder keeps its open folders under the new name.
        const QString conf = QDir::cleanPath(dir.filePath("conf"));
        QCOMPARE(tree.rename(conf, "configs").value("path").toString(), QDir::cleanPath(dir.filePath("configs")));
        QCOMPARE(names(tree), QStringList({"configs", "inner", "x.lua", "a.conf", "b.lua"}));
        // Never over another, and only a plain name.
        QVERIFY(tree.rename(dir.filePath("b.lua"), "configs").contains("error"));
        QVERIFY(tree.rename(dir.filePath("b.lua"), "x/y").contains("error"));
        QCOMPARE(tree.rename(dir.filePath("b.lua"), "b.lua").value("path").toString(), QDir::cleanPath(dir.filePath("b.lua")));

        // Copies beside it, numbered past the first.
        QCOMPARE(tree.duplicate(dir.filePath("b.lua")).value("path").toString(), QDir::cleanPath(dir.filePath("b copy.lua")));
        QCOMPARE(tree.duplicate(dir.filePath("b.lua")).value("path").toString(), QDir::cleanPath(dir.filePath("b copy 2.lua")));
        QCOMPARE(read(dir.filePath("b copy 2.lua")), QByteArray("b\n"));
        QCOMPARE(tree.duplicate(dir.filePath(".zshrc")).value("path").toString(), QDir::cleanPath(dir.filePath(".zshrc copy")));
        // A folder whole.
        QCOMPARE(tree.duplicate(dir.filePath("configs")).value("path").toString(), QDir::cleanPath(dir.filePath("configs copy")));
        QCOMPARE(read(dir.filePath("configs copy/inner/x.lua")), QByteArray("x\n"));
        QCOMPARE(read(dir.filePath("configs/inner/x.lua")), QByteArray("x\n"));
        QVERIFY(tree.duplicate(dir.filePath("missing")).contains("error"));
    }

    // A link duplicates as a copy of its file, so editing the copy can't
    // change the original.
    void duplicatesALinksFileNotTheLink()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("root");
        write(dir.filePath("real.lua"), "real\n");
        QVERIFY(QFile::link(dir.filePath("real.lua"), dir.filePath("root/linked.lua")));
        QVERIFY(QFile::link(dir.filePath("gone.lua"), dir.filePath("root/dangling.lua")));
        FileTree tree;
        tree.setRoot(dir.filePath("root"));
        const QString copy = tree.duplicate(dir.filePath("root/linked.lua")).value("path").toString();
        QCOMPARE(copy, QDir::cleanPath(dir.filePath("root/linked copy.lua")));
        QVERIFY(!QFileInfo(copy).isSymLink());
        QCOMPARE(read(copy), QByteArray("real\n"));
        QVERIFY(tree.duplicate(dir.filePath("root/dangling.lua")).contains("error"));
        // A link to a folder the copy would land in can't copy itself.
        QVERIFY(QFile::link(dir.filePath("root"), dir.filePath("root/up")));
        QVERIFY(tree.duplicate(dir.filePath("root/up")).contains("error"));
        QVERIFY(!QFileInfo::exists(dir.filePath("root/up copy")));
    }

    // Another file never brings the last one's edits back with Ctrl+Z, even
    // when its text is the same.
    void openingAnotherFileForgetsTheUndoHistory()
    {
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData("import QtQuick\nTextEdit { textFormat: TextEdit.PlainText }", {});
        std::unique_ptr<QQuickItem> edit(qobject_cast<QQuickItem *>(component.create()));
        QVERIFY(edit);
        QTemporaryDir dir;
        write(dir.filePath("a.conf"), "a");
        write(dir.filePath("b.lua"), "xa");
        Document doc;
        doc.attach(edit.get());
        QVERIFY(doc.open(dir.filePath("a.conf")));
        QTextDocument *text = edit->property("textDocument").value<QQuickTextDocument *>()->textDocument();
        QTextCursor cursor(text);
        cursor.insertText("x");
        QCOMPARE(text->toPlainText(), QString("xa"));
        QVERIFY(doc.open(dir.filePath("b.lua")));
        QVERIFY(!text->isUndoAvailable());
        undo(edit.get());
        QCOMPARE(text->toPlainText(), QString("xa"));
        QCOMPARE(doc.commentPrefix(), QString("--"));
    }

    // Escape on "deleted on disk" lets the file go as the banner's close
    // does: the next save recreates it.
    void dismissingADeletedFileLetsItGo()
    {
        QTemporaryDir dir;
        write(dir.filePath("x.conf"), "x\n");
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(dir.filePath("x.conf")));
        QFile::remove(dir.filePath("x.conf"));
        QTRY_COMPARE(doc.problem(), QString("DeletedOnDisk"));
        doc.dismissProblem();
        QCOMPARE(doc.problem(), QString("None"));
        append(&text, "y\n");
        QVERIFY(doc.save());
        QCOMPARE(read(dir.filePath("x.conf")), QByteArray("x\ny\n"));
    }

    void followsAMovedFile()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("into");
        write(dir.filePath("x.lua"), "-- x\n");
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(dir.filePath("x.lua")));
        append(&text, "edit\n");

        QVERIFY(QDir().rename(dir.filePath("x.lua"), dir.filePath("into/x.lua")));
        doc.relocate(dir.filePath("x.lua"), dir.filePath("into/x.lua"));
        QCOMPARE(doc.path(), dir.filePath("into/x.lua"));
        QVERIFY(doc.modified());
        QCOMPARE(doc.commentPrefix(), QString("--"));

        // A new extension, a new language.
        QVERIFY(QDir().rename(dir.filePath("into/x.lua"), dir.filePath("into/x.conf")));
        doc.relocate(dir.filePath("into/x.lua"), dir.filePath("into/x.conf"));
        QCOMPARE(doc.commentPrefix(), QString("#"));
        QVERIFY(QDir().rename(dir.filePath("into/x.conf"), dir.filePath("into/x.lua")));
        doc.relocate(dir.filePath("into/x.conf"), dir.filePath("into/x.lua"));
        QVERIFY(doc.save());
        QCOMPARE(read(dir.filePath("into/x.lua")), QByteArray("-- x\nedit\n"));
        QVERIFY(!QFileInfo::exists(dir.filePath("x.lua")));
    }

    // The sidebar itself, offscreen: a row dragged onto a folder moves into
    // it, and the open file follows with its edits.
    void dragsFilesIntoFolders()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("root/folder");
        write(dir.filePath("root/a.conf"), "a\n");
        write(dir.filePath("root/b.conf"), "b\n");
        write(dir.filePath("Harness.qml"),
              "import QtQuick\nimport \"file://" + QFile::encodeName(sourceFolder()) + "\"\n"
              "Item { id: win; width: 300; height: 400\n"
              "  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }\n"
              "  Sidebar { objectName: \"sidebar\"; anchors.fill: parent } }\n");

        Theme theme(dir.path());
        FileTree tree;
        tree.setRoot(dir.filePath("root"));
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(dir.filePath("root/a.conf")));
        append(&text, "edit\n");

        QQuickView view;
        view.engine()->rootContext()->setContextProperty("theme", &theme);
        view.engine()->rootContext()->setContextProperty("doc", &doc);
        view.engine()->rootContext()->setContextProperty("files", &tree);
        view.setSource(QUrl::fromLocalFile(dir.filePath("Harness.qml")));
        QVERIFY2(view.status() == QQuickView::Ready, qPrintable(view.errors().isEmpty() ? QString() : view.errors().first().toString()));
        view.show();
        QVERIFY(QTest::qWaitForWindowExposed(&view));
        QCOMPARE(names(tree), QStringList({"folder", "a.conf", "b.conf"}));

        // Rows start 13px down, each twice the text size high.
        const int rowHeight = qRound(theme.textSize() * 2.0);
        auto centerOf = [&](int row) { return QPoint(60, 13 + row * rowHeight + rowHeight / 2); };
        QTest::mousePress(&view, Qt::LeftButton, {}, centerOf(1));
        for (int step = 1; step <= 10; ++step) {
            const QPoint at = centerOf(1) + (centerOf(0) - centerOf(1)) * step / 10;
            QMouseEvent move(QEvent::MouseMove, at, view.mapToGlobal(at), Qt::NoButton, Qt::LeftButton, {});
            QGuiApplication::sendEvent(&view, &move);
            QTest::qWait(10);
            // Another program adds a file mid-drag: the list refreshes
            // under it, and the drag carries on.
            if (step == 5) {
                write(dir.filePath("root/z.conf"), "");
                QTRY_COMPARE(names(tree), QStringList({"folder", "a.conf", "b.conf", "z.conf"}));
            }
        }
        QTest::mouseRelease(&view, Qt::LeftButton, {}, centerOf(0));

        QTRY_VERIFY(QFileInfo::exists(dir.filePath("root/folder/a.conf")));
        QVERIFY(!QFileInfo::exists(dir.filePath("root/a.conf")));
        QCOMPARE(doc.path(), dir.filePath("root/folder/a.conf"));
        QVERIFY(doc.modified());
        QCOMPARE(names(tree), QStringList({"folder", "a.conf", "b.conf", "z.conf"}));
        QCOMPARE(tree.pathAt(1), QDir::cleanPath(dir.filePath("root/folder/a.conf")));
    }

    // The sidebar's keys, offscreen: typing jumps, and Delete asks.
    void sidebarKeys()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("root");
        for (const char *name : {"autostart.lua", "bindings.lua", "bluetooth.conf", "input.lua"})
            write(dir.filePath(QString("root/") + name), "");
        write(dir.filePath("Harness.qml"),
              "import QtQuick\nimport \"file://" + QFile::encodeName(sourceFolder()) + "\"\n"
              "Item { id: win; width: 300; height: 400; property string asked\n"
              "  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }\n"
              "  Sidebar { id: bar; objectName: \"sidebar\"; anchors.fill: parent\n"
              "    onDeleteRequested: function(path) { win.asked = path } }\n"
              "  Component.onCompleted: bar.focusTree() }\n");

        Theme theme(dir.path());
        FileTree tree;
        tree.setRoot(dir.filePath("root"));
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);

        QQuickView view;
        view.engine()->rootContext()->setContextProperty("theme", &theme);
        view.engine()->rootContext()->setContextProperty("doc", &doc);
        view.engine()->rootContext()->setContextProperty("files", &tree);
        view.setSource(QUrl::fromLocalFile(dir.filePath("Harness.qml")));
        QVERIFY(view.status() == QQuickView::Ready);
        view.show();
        QVERIFY(QTest::qWaitForWindowExposed(&view));
        QObject *sidebar = view.rootObject()->findChild<QObject *>("sidebar");
        QVERIFY(sidebar);
        QTRY_VERIFY(sidebar->property("treeFocused").toBool());

        // The same letter again steps to the next name it starts.
        QTest::keyClick(&view, Qt::Key_B);
        QCOMPARE(sidebar->property("currentPath").toString(), QDir::cleanPath(dir.filePath("root/bindings.lua")));
        QTest::keyClick(&view, Qt::Key_B);
        QCOMPARE(sidebar->property("currentPath").toString(), QDir::cleanPath(dir.filePath("root/bluetooth.conf")));
        QTest::qWait(900);
        QTest::keyClick(&view, Qt::Key_I);
        QTRY_COMPARE(sidebar->property("currentPath").toString(), QDir::cleanPath(dir.filePath("root/input.lua")));
        pressDelete(&view);
        QCOMPARE(view.rootObject()->property("asked").toString(), QDir::cleanPath(dir.filePath("root/input.lua")));
        QVERIFY(QFileInfo::exists(dir.filePath("root/input.lua")));
    }

    // A moved relative link points somewhere else: Save asks rather than
    // writing to that other file.
    void aMovedLinkStillAsksBeforeSaving()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("into");
        write(dir.filePath("real.conf"), "same\n");
        write(dir.filePath("into/real.conf"), "same\n");
        QVERIFY(QFile::link("real.conf", dir.filePath("link.conf")));
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(dir.filePath("link.conf")));
        append(&text, "edit\n");

        QVERIFY(QDir().rename(dir.filePath("link.conf"), dir.filePath("into/link.conf")));
        doc.relocate(dir.filePath("link.conf"), dir.filePath("into/link.conf"));
        QVERIFY(!doc.save());
        QCOMPARE(doc.problem(), QString("Retargeted"));
        QCOMPARE(read(dir.filePath("into/real.conf")), QByteArray("same\n"));
        QCOMPARE(read(dir.filePath("real.conf")), QByteArray("same\n"));
    }

    // A folder moved with both a link and its file in it: still the same
    // file, so Save writes it without asking.
    void aLinkMovedWithItsFileStillSaves()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("configs");
        QDir(dir.path()).mkpath("into");
        write(dir.filePath("configs/real.conf"), "a\n");
        QVERIFY(QFile::link("real.conf", dir.filePath("configs/link.conf")));
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(dir.filePath("configs/link.conf")));
        append(&text, "b\n");

        QVERIFY(QDir().rename(dir.filePath("configs"), dir.filePath("into/configs")));
        doc.relocate(dir.filePath("configs"), dir.filePath("into/configs"));
        QCOMPARE(doc.path(), dir.filePath("into/configs/link.conf"));
        QVERIFY2(doc.save(), qPrintable(doc.problem()));
        QCOMPARE(read(dir.filePath("into/configs/real.conf")), QByteArray("a\nb\n"));
        QVERIFY(QFileInfo(dir.filePath("into/configs/link.conf")).isSymLink());
    }

    void revealsUnderTheRootFolder()
    {
        FileTree tree;
        tree.setRoot("/");
        QVERIFY(tree.reveal("/etc/hostname") >= 0 || !QFileInfo::exists("/etc/hostname"));
        QVERIFY(tree.indexOf("/etc") >= 0);
        QCOMPARE(tree.folderAt(tree.indexOf("/etc")), QString("/etc"));
    }

    // The whole window, offscreen, as main.cpp sets it up: the flows across
    // the editor, the sidebar and the dialogs.

    void openingAFolderShowsItsFilesWithTheKeysInThem()
    {
        PlainWindow plain;
        QVERIFY(plain.load("", "root"));
        QVERIFY(plain.window->property("sidebarVisible").toBool());
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        QVERIFY(plain.item("pickAFile")->property("visible").toBool());
    }

    void ctrlBAndCtrlTabMoveTheKeys()
    {
        PlainWindow plain;
        QVERIFY(plain.load("root/b.conf", ""));
        QVERIFY(!plain.window->property("sidebarVisible").toBool());

        plain.key(Qt::Key_B, Qt::ControlModifier);
        QVERIFY(plain.window->property("sidebarVisible").toBool());
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        // On the open file.
        QCOMPARE(plain.sidebar()->property("currentPath").toString(), plain.path("root/b.conf"));
        QVERIFY(!plain.item("pickAFile")->property("visible").toBool());

        plain.key(Qt::Key_Tab, Qt::ControlModifier);
        QTRY_VERIFY(!plain.sidebar()->property("treeFocused").toBool());
        QVERIFY(plain.editorFocused());
        plain.key(Qt::Key_Tab, Qt::ControlModifier);
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());

        plain.key(Qt::Key_B, Qt::ControlModifier);
        QVERIFY(!plain.window->property("sidebarVisible").toBool());
        QTRY_VERIFY(plain.editorFocused());
        // Without the files, Ctrl+Tab leaves the keys where they are.
        plain.key(Qt::Key_Tab, Qt::ControlModifier);
        QVERIFY(!plain.window->property("sidebarVisible").toBool());
        QVERIFY(plain.editorFocused());
    }

    // Opening another file from the files asks about unsaved changes
    // first, and the question has the keys.
    void openingFromTheFilesAsksAboutUnsavedChanges()
    {
        PlainWindow plain;
        QVERIFY(plain.load("root/b.conf", ""));
        plain.type("x");
        QVERIFY(plain.doc.modified());
        plain.key(Qt::Key_B, Qt::ControlModifier);
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        plain.key(Qt::Key_A);
        plain.key(Qt::Key_Return);
        QTRY_VERIFY(plain.item("unsaved")->property("opened").toBool());
        // Enter saves.
        plain.key(Qt::Key_Return);
        QTRY_COMPARE(plain.doc.path(), plain.path("root/a.conf"));
        QCOMPARE(read(plain.path("root/b.conf")), QByteArray("xb\n"));
        QTRY_VERIFY(plain.editorFocused());
    }

    // Ctrl+H: hidden files in the files, find and replace in the text.
    void ctrlHDependsOnWhereTheKeysAre()
    {
        PlainWindow plain;
        write(plain.path("root/.hidden"), "");
        QVERIFY(plain.load("root/b.conf", ""));
        plain.key(Qt::Key_B, Qt::ControlModifier);
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        QVERIFY(!plain.files.showHidden());
        plain.key(Qt::Key_H, Qt::ControlModifier);
        QVERIFY(plain.files.showHidden());
        QVERIFY(plain.files.indexOf(plain.path("root/.hidden")) >= 0);
        QVERIFY(!plain.item("findBar")->property("visible").toBool());

        plain.key(Qt::Key_Tab, Qt::ControlModifier);
        QTRY_VERIFY(plain.editorFocused());
        plain.key(Qt::Key_H, Qt::ControlModifier);
        QVERIFY(plain.files.showHidden());
        QTRY_VERIFY(plain.item("findBar")->property("visible").toBool());
    }

    // F2 renames, and the open file follows with its edits.
    void f2RenamesAndTheOpenFileFollows()
    {
        PlainWindow plain;
        QVERIFY(plain.load("root/b.conf", ""));
        plain.type("x");
        plain.key(Qt::Key_B, Qt::ControlModifier);
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        plain.key(Qt::Key_F2);
        QTRY_VERIFY(plain.item("namePrompt")->property("opened").toBool());
        // Typing replaces the name before the extension.
        plain.type("c");
        plain.key(Qt::Key_Return);
        QTRY_COMPARE(plain.doc.path(), plain.path("root/c.conf"));
        QVERIFY(!QFileInfo::exists(plain.path("root/b.conf")));
        QVERIFY(plain.doc.modified());
        plain.key(Qt::Key_S, Qt::ControlModifier);
        QTRY_COMPARE(read(plain.path("root/c.conf")), QByteArray("xb\n"));
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
    }

    // Alt+Enter opens the row's menu: Rename, Duplicate, Delete.
    void altEnterOpensTheRowMenu()
    {
        PlainWindow plain;
        QVERIFY(plain.load("", "root"));
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        plain.key(Qt::Key_A);
        plain.key(Qt::Key_Return, Qt::AltModifier);
        QTRY_VERIFY(plain.item("rowMenu")->property("opened").toBool());
        // Rename is already picked; Down to Duplicate.
        QCOMPARE(plain.item("rowMenu")->property("currentIndex").toInt(), 0);
        plain.key(Qt::Key_Down);
        plain.key(Qt::Key_Return);
        QTRY_VERIFY(QFileInfo::exists(plain.path("root/a copy.conf")));
        QTRY_VERIFY(!plain.item("rowMenu")->property("opened").toBool());
        QTRY_COMPARE(plain.sidebar()->property("currentPath").toString(), plain.path("root/a copy.conf"));
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
    }

    // Ctrl+F and Ctrl+H open the find bar in their mode, switch it, or
    // close it when it's already what's open.
    void ctrlFAndCtrlHToggleTheFindBar()
    {
        PlainWindow plain;
        QVERIFY(plain.load("root/b.conf", ""));
        QObject *bar = plain.item("findBar");
        plain.key(Qt::Key_F, Qt::ControlModifier);
        QVERIFY(bar->property("visible").toBool());
        QVERIFY(!bar->property("replacing").toBool());
        plain.key(Qt::Key_F, Qt::ControlModifier);
        QVERIFY(!bar->property("visible").toBool());
        QTRY_VERIFY(plain.editorFocused());

        plain.key(Qt::Key_H, Qt::ControlModifier);
        QVERIFY(bar->property("visible").toBool());
        QVERIFY(bar->property("replacing").toBool());
        // Ctrl+F from replace narrows to find; Ctrl+H again widens.
        plain.key(Qt::Key_F, Qt::ControlModifier);
        QVERIFY(bar->property("visible").toBool());
        QVERIFY(!bar->property("replacing").toBool());
        plain.key(Qt::Key_H, Qt::ControlModifier);
        QVERIFY(bar->property("replacing").toBool());
        plain.key(Qt::Key_H, Qt::ControlModifier);
        QVERIFY(!bar->property("visible").toBool());
        QTRY_VERIFY(plain.editorFocused());
    }

    // Page Up and Page Down, in the text and in the files.
    void pageUpAndDownMoveAScreenful()
    {
        PlainWindow plain;
        QByteArray lines;
        for (int i = 1; i <= 400; ++i)
            lines += "line " + QByteArray::number(i) + "\n";
        write(plain.path("root/long.conf"), lines);
        for (int i = 0; i < 60; ++i)
            write(plain.path(QString("root/file%1.conf").arg(i, 2, 10, QChar('0'))), "");
        QVERIFY(plain.load("root/long.conf", ""));
        QObject *editor = plain.item("editorView");
        QCOMPARE(editor->property("currentLine").toInt(), 1);

        plain.key(Qt::Key_PageDown);
        const int afterOne = editor->property("currentLine").toInt();
        QVERIFY2(afterOne > 10, qPrintable(QString::number(afterOne)));
        plain.key(Qt::Key_PageDown);
        QVERIFY(editor->property("currentLine").toInt() > afterOne);
        QVERIFY(editor->property("firstLine").toInt() > 1);
        plain.key(Qt::Key_PageUp);
        QCOMPARE(editor->property("currentLine").toInt(), afterOne);
        plain.key(Qt::Key_PageUp);
        QCOMPARE(editor->property("currentLine").toInt(), 1);
        QVERIFY(!plain.doc.modified());

        plain.key(Qt::Key_B, Qt::ControlModifier);
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        // Laid out a frame after it shows.
        QTRY_VERIFY(plain.item("fileList")->property("height").toReal() > 200);
        plain.key(Qt::Key_Home);
        const QString top = plain.sidebar()->property("currentPath").toString();
        plain.key(Qt::Key_PageDown);
        const QString paged = plain.sidebar()->property("currentPath").toString();
        QVERIFY(paged != top);
        QVERIFY(plain.files.indexOf(paged) > 5);
        plain.key(Qt::Key_PageUp);
        QCOMPARE(plain.sidebar()->property("currentPath").toString(), top);
    }

    // The line numbers are a fixed set, re-used as the text scrolls, rather
    // than rebuilt whenever the count of lines on screen changes.
    void lineNumbersAreReusedWhileScrolling()
    {
        PlainWindow plain;
        QByteArray lines;
        for (int i = 0; i < 400; ++i)
            lines += i % 3 ? "short\n" : QByteArray(400, 'w') + "\n";
        write(plain.path("root/long.conf"), lines);
        QVERIFY(plain.load("root/long.conf", ""));
        QObject *numbers = plain.item("lineNumbers");
        QObject *editor = plain.item("editorView");
        const int count = numbers->property("count").toInt();
        QVERIFY(count > 5);
        QSignalSpy rebuilt(numbers, SIGNAL(countChanged()));
        for (int i = 0; i < 6; ++i) {
            plain.key(Qt::Key_PageDown);
            // The first number is the first line on screen.
            QQuickItem *first = nullptr;
            QVERIFY(QMetaObject::invokeMethod(numbers, "itemAt", Q_RETURN_ARG(QQuickItem *, first), Q_ARG(int, 0)));
            QCOMPARE(first->property("text").toString(), QString::number(editor->property("firstLine").toInt()));
        }
        QCOMPARE(rebuilt.count(), 0);
        QCOMPARE(numbers->property("count").toInt(), count);
        QVERIFY(editor->property("firstLine").toInt() > 1);
    }

    // Paging keeps its column across a short line, and its place on screen.
    void pagingKeepsItsColumnAndPlace()
    {
        PlainWindow plain;
        // Every line but the first empty, so a page always lands on one.
        QByteArray lines = "0123456789\n" + QByteArray(300, '\n');
        write(plain.path("root/long.conf"), lines);
        QVERIFY(plain.load("root/long.conf", ""));
        QObject *editor = plain.item("editorView");
        auto *area = qobject_cast<QQuickItem *>(editor->property("area").value<QObject *>());
        for (int i = 0; i < 8; ++i)
            plain.key(Qt::Key_Right);
        QCOMPARE(area->property("cursorPosition").toInt(), 8);

        // Down twice, then up twice: back to the same column, wherever the
        // pages landed on the way.
        QObject *flick = plain.item("editorFlick");
        auto onScreen = [&] { return area->property("cursorRectangle").toRectF().y() - flick->property("contentY").toReal(); };
        plain.key(Qt::Key_PageDown);
        const int line = editor->property("currentLine").toInt();
        const qreal place = onScreen();
        // The cursor keeps its place on screen, page after page.
        for (int i = 0; i < 3; ++i) {
            plain.key(Qt::Key_PageDown);
            QCOMPARE(onScreen(), place);
        }
        QVERIFY(editor->property("currentLine").toInt() > line);
        plain.key(Qt::Key_PageUp);
        plain.key(Qt::Key_PageUp);
        plain.key(Qt::Key_PageUp);
        plain.key(Qt::Key_PageUp);
        QCOMPARE(area->property("cursorPosition").toInt(), 8);
    }

    // F3 and Shift+F3 step through matches.
    void f3FindsTheNextMatch()
    {
        PlainWindow plain;
        write(plain.path("root/m.conf"), "x one x two x\n");
        QVERIFY(plain.load("root/m.conf", ""));
        auto *area = qobject_cast<QQuickItem *>(plain.item("editorView")->property("area").value<QObject *>());
        plain.key(Qt::Key_F, Qt::ControlModifier);
        plain.type("x");
        plain.key(Qt::Key_Escape);
        QTRY_VERIFY(plain.editorFocused());
        area->setProperty("cursorPosition", 0);
        plain.key(Qt::Key_F3);
        QCOMPARE(area->property("selectionStart").toInt(), 0);
        plain.key(Qt::Key_F3);
        QCOMPARE(area->property("selectionStart").toInt(), 6);
        plain.key(Qt::Key_F3, Qt::ShiftModifier);
        QCOMPARE(area->property("selectionStart").toInt(), 0);
    }

    // A change in a shown folder, like saving the open file, keeps the
    // files where they were scrolled to.
    void savingKeepsTheFilesScrolled()
    {
        PlainWindow plain;
        for (int i = 0; i < 80; ++i)
            write(plain.path(QString("root/f%1.conf").arg(i, 2, 10, QChar('0'))), "");
        QVERIFY(plain.load("root/f79.conf", ""));
        plain.key(Qt::Key_B, Qt::ControlModifier);
        QTRY_VERIFY(plain.item("fileList")->property("height").toReal() > 200);
        QObject *list = plain.item("fileList");
        // Scrolled down to the open file, the last of 82 rows.
        auto top = [&] { return list->property("originY").toReal() - list->property("topMargin").toReal(); };
        QTRY_VERIFY(list->property("contentY").toReal() > top() + 500);
        const qreal scrolled = list->property("contentY").toReal();
        plain.key(Qt::Key_Tab, Qt::ControlModifier);
        plain.type("x");
        plain.key(Qt::Key_S, Qt::ControlModifier);
        QTRY_COMPARE(read(plain.path("root/f79.conf")), QByteArray("x"));
        // Past the watcher's pause, the rows refresh in place.
        QTest::qWait(400);
        QCOMPARE(list->property("contentY").toReal(), scrolled);
        QCOMPARE(plain.sidebar()->property("currentPath").toString(), plain.path("root/f79.conf"));
    }

    // A reload from disk doesn't reopen folders or move the keys.
    void aReloadLeavesTheFilesAlone()
    {
        PlainWindow plain;
        QDir(plain.path("root")).mkpath("sub");
        write(plain.path("root/sub/c.conf"), "c\n");
        // Opened from the files, a folder up: sub, a.conf, b.conf.
        QVERIFY(plain.load("", "root"));
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        plain.key(Qt::Key_Right);
        plain.key(Qt::Key_Down);
        plain.key(Qt::Key_Return);
        QTRY_COMPARE(plain.doc.path(), plain.path("root/sub/c.conf"));
        const int sub = plain.files.indexOf(plain.path("root/sub"));
        QVERIFY(plain.files.isExpanded(sub));
        plain.key(Qt::Key_Tab, Qt::ControlModifier);
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        plain.key(Qt::Key_Left);
        plain.key(Qt::Key_Left);
        QVERIFY(!plain.files.isExpanded(sub));
        replace(plain.path("root/sub/c.conf"), "changed\n");
        QTRY_COMPARE(plain.doc.textDocument()->toPlainText(), QString("changed\n"));
        QTest::qWait(300);
        QVERIFY(!plain.files.isExpanded(plain.files.indexOf(plain.path("root/sub"))));
        QCOMPARE(plain.sidebar()->property("currentPath").toString(), plain.path("root/sub"));
    }

    // The shortcuts take the keys while they show: typing changes nothing.
    void theShortcutsTakeTheKeys()
    {
        PlainWindow plain;
        QVERIFY(plain.load("root/b.conf", ""));
        plain.key(Qt::Key_F1);
        QVERIFY(plain.item("help")->property("visible").toBool());
        plain.type("q");
        plain.key(Qt::Key_PageDown);
        QVERIFY(!plain.doc.modified());
        plain.key(Qt::Key_F1);
        QVERIFY(!plain.item("help")->property("visible").toBool());
        QTRY_VERIFY(plain.editorFocused());

        // A shortcut that takes the keys elsewhere closes it, rather than
        // leaving it up with typing reaching the text behind.
        plain.key(Qt::Key_B, Qt::ControlModifier);
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        plain.key(Qt::Key_F1);
        QVERIFY(plain.item("help")->property("visible").toBool());
        plain.key(Qt::Key_B, Qt::ControlModifier);
        QTRY_VERIFY(plain.editorFocused());
        QVERIFY(!plain.item("help")->property("visible").toBool());
        plain.type("q");
        QVERIFY(plain.doc.modified());
    }

    // Go to line reads numbers as the language writes them.
    void goToLineReadsGroupedNumbers()
    {
        PlainWindow plain;
        write(plain.path("root/long.conf"), QByteArray(1200, '\n'));
        QVERIFY(plain.load("root/long.conf", ""));
        plain.key(Qt::Key_G, Qt::ControlModifier);
        plain.type("1,000");
        plain.key(Qt::Key_Return);
        QTRY_COMPARE(plain.item("editorView")->property("currentLine").toInt(), 1000);
    }

    // Cancelling the unsaved question gives the keys back to the files when
    // a file was picked there.
    void cancellingTheUnsavedQuestionGoesBack()
    {
        PlainWindow plain;
        QVERIFY(plain.load("root/b.conf", ""));
        plain.type("x");
        plain.key(Qt::Key_B, Qt::ControlModifier);
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        plain.key(Qt::Key_A);
        plain.key(Qt::Key_Return);
        QTRY_VERIFY(plain.item("unsaved")->property("opened").toBool());
        plain.key(Qt::Key_Escape);
        QTRY_VERIFY(!plain.item("unsaved")->property("opened").toBool());
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        QCOMPARE(plain.doc.path(), plain.path("root/b.conf"));
    }

    void anUntitledDocumentNeverAsksForAFile()
    {
        PlainWindow plain;
        QVERIFY(plain.load("", ""));
        plain.key(Qt::Key_B, Qt::ControlModifier);
        QVERIFY(plain.window->property("sidebarVisible").toBool());
        QVERIFY(!plain.item("pickAFile")->property("visible").toBool());
    }

    void deleteAsksThenMovesToTheTrash()
    {
        PlainWindow plain;
        QVERIFY(plain.load("", "root"));
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        plain.key(Qt::Key_A);
        QCOMPARE(plain.sidebar()->property("currentPath").toString(), plain.path("root/a.conf"));
        pressDelete(plain.window);
        QTRY_VERIFY(plain.item("deleteConfirm")->property("opened").toBool());
        QVERIFY(QFileInfo::exists(plain.path("root/a.conf")));
        plain.key(Qt::Key_Return);
        QTRY_VERIFY(!QFileInfo::exists(plain.path("root/a.conf")));
        QVERIFY(QFileInfo::exists(plain.path("data/Trash/files/a.conf")));

        // Escape keeps it.
        plain.key(Qt::Key_B);
        pressDelete(plain.window);
        QTRY_VERIFY(plain.item("deleteConfirm")->property("opened").toBool());
        plain.key(Qt::Key_Escape);
        QTRY_VERIFY(!plain.item("deleteConfirm")->property("opened").toBool());
        QVERIFY(QFileInfo::exists(plain.path("root/b.conf")));
    }

    void ctrlNNamesANewFileAndOpensIt()
    {
        PlainWindow plain;
        QVERIFY(plain.load("", "root"));
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
        plain.key(Qt::Key_N, Qt::ControlModifier);
        QTRY_VERIFY(plain.item("namePrompt")->property("opened").toBool());
        plain.type("new.conf");
        plain.key(Qt::Key_Return);
        QTRY_COMPARE(plain.doc.path(), plain.path("root/new.conf"));
        QVERIFY(QFileInfo(plain.path("root/new.conf")).isFile());
        QTRY_VERIFY(plain.editorFocused());

        // And a folder, which the keys go to.
        plain.key(Qt::Key_N, Qt::ControlModifier | Qt::ShiftModifier);
        QTRY_VERIFY(plain.item("namePrompt")->property("opened").toBool());
        plain.type("themes");
        plain.key(Qt::Key_Return);
        QTRY_VERIFY(QFileInfo(plain.path("root/themes")).isDir());
        QTRY_COMPARE(plain.sidebar()->property("currentPath").toString(), plain.path("root/themes"));
        QTRY_VERIFY(plain.sidebar()->property("treeFocused").toBool());
    }

    void closesToAnEmptyDocument()
    {
        QTemporaryDir dir;
        write(dir.filePath("x.lua"), "-- x\n");
        QTextDocument text;
        Document doc;
        doc.attachDocument(&text);
        QVERIFY(doc.open(dir.filePath("x.lua")));
        append(&text, "more\n");
        QVERIFY(doc.modified());

        QSignalSpy changed(&doc, &Document::fileChanged);
        doc.close();
        QCOMPARE(changed.count(), 1);
        QVERIFY(doc.path().isEmpty());
        QVERIFY(text.toPlainText().isEmpty());
        QVERIFY(!doc.modified());
        QVERIFY(doc.editable());
        QCOMPARE(doc.problem(), QString("None"));
    }

    // Languages and highlighting.

    void picksLanguages()
    {
        QCOMPARE(Highlighter::languageFor("/h/.config/hypr/bindings.lua", ""), QString("lua"));
        QCOMPARE(Highlighter::languageFor("/h/.config/hypr/hypridle.conf", ""), QString("conf"));
        QCOMPARE(Highlighter::languageFor("/h/.config/waybar/config.jsonc", ""), QString("jsonc"));
        QCOMPARE(Highlighter::languageFor("/h/.config/waybar/style.css", ""), QString("css"));
        QCOMPARE(Highlighter::languageFor("/h/.bashrc", ""), QString("shell"));
        QCOMPARE(Highlighter::languageFor("/h/PKGBUILD", ""), QString("shell"));
        QCOMPARE(Highlighter::languageFor("/h/bin/thing", "#!/bin/bash"), QString("shell"));
        QCOMPARE(Highlighter::languageFor("/h/notes", "hello"), QString("text"));
        QCOMPARE(Highlighter::commentPrefix("jsonc"), QString("//"));
        QCOMPARE(Highlighter::commentPrefix("text"), QString());
    }

    void highlightsLua()
    {
        QCOMPARE(Highlighter::tokens("lua", {"local x = \"a -- b\" -- c"}),
                 QString("wwwww.k...ssssssss.cccc"));
        // A long comment holding ]] ends only at its own level.
        QCOMPARE(Highlighter::tokens("lua", {"--[==[ a ]] b", "]==] x = 1"}),
                 QString("ccccccccccccc\ncccc.k...n"));
        QCOMPARE(Highlighter::tokens("lua", {"s = 'it\\'s' == nil"}),
                 QString("k...sssssss....xxx"));
        QCOMPARE(Highlighter::tokens("conf", {"; ini comment", "key = a;b"}),
                 QString("ccccccccccccc\nkkk......"));
    }

    void highlightsShell()
    {
        QCOMPARE(Highlighter::tokens("shell", {"echo ${#arr} # note"}),
                 QString(".....xxxxxxx.cccccc"));
        QCOMPARE(Highlighter::tokens("shell", {"export EDITOR='a#b'"}),
                 QString("wwwwww.kkkkkk.sssss"));
    }

    void leavesVeryLongLinesUncolored()
    {
        // A document reports its changes only once it has a layout, which the
        // TextEdit's always does.
        QTextDocument document;
        document.documentLayout();
        Highlighter highlighter(&document, nullptr);
        highlighter.setLanguage("jsonc");
        const QString longLine = "\"k\": " + QString(Highlighter::LongLine, '1');
        document.setPlainText(longLine + "\n\"k\": 1");
        QVERIFY(document.firstBlock().layout()->formats().isEmpty());
        QVERIFY(!document.lastBlock().layout()->formats().isEmpty());

        // A long line that closes a block comment still closes it.
        highlighter.setLanguage("css");
        document.setPlainText("/* open\n" + QString(Highlighter::LongLine, 'x') + " */\na: 1;");
        const auto formats = document.lastBlock().layout()->formats();
        QVERIFY(!formats.isEmpty());
        QVERIFY(!formats.first().format.fontItalic()); // a key, not a comment
    }

    void highlightsDataFormats()
    {
        QCOMPARE(Highlighter::tokens("jsonc", {"{\"a\": \"b\", // c"}),
                 QString(".kkk..sss..cccc"));
        QCOMPARE(Highlighter::tokens("toml", {"[server]", "msg = \"\"\"", "# not a comment", "\"\"\""}),
                 QString("wwwwwwww\nkkk...sss\nsssssssssssssss\nsss"));
        QCOMPARE(Highlighter::tokens("yaml", {"- name: x#y # z", "  on: true"}),
                 QString("..kkkk......ccc\n..xx..xxxx"));
        QCOMPARE(Highlighter::tokens("conf", {"general {", "    gaps_in = 5 # px", "}"}),
                 QString("wwwwwww..\n....kkkkkkk...n.cccc\n."));
        QCOMPARE(Highlighter::tokens("css", {"@define-color fg #ffcead; /* c */"}),
                 QString("wwwwwwwwwwwww....nnnnnnn..ccccccc"));
    }

    // Edits, through a real TextEdit and its own undo stack.

    void editsAreSingleUndoSteps()
    {
        QQmlEngine engine;
        QQmlComponent component(&engine);
        component.setData("import QtQuick\nTextEdit { textFormat: TextEdit.PlainText }", {});
        std::unique_ptr<QQuickItem> edit(qobject_cast<QQuickItem *>(component.create()));
        QVERIFY(edit);

        QTemporaryDir dir;
        const QString path = dir.filePath("t.lua");
        write(path, "a = 1\n    b = 2\n");
        Document doc;
        doc.attach(edit.get());
        Editing editing(&doc);
        QVERIFY(doc.open(path));
        auto text = [&] { return edit->property("text").toString(); };
        auto undo = [&] { QMetaObject::invokeMethod(edit.get(), "undo"); };
        auto redo = [&] { QMetaObject::invokeMethod(edit.get(), "redo"); };
        QVERIFY(!edit->property("canUndo").toBool());

        editing.toggleComment(0, 12);
        // Lined up at the shallowest indentation of the lines, as VSCode does.
        QCOMPARE(text(), QString("-- a = 1\n--     b = 2\n"));
        undo();
        QCOMPARE(text(), QString("a = 1\n    b = 2\n"));
        QVERIFY(!doc.modified());
        redo();
        QCOMPARE(text(), QString("-- a = 1\n--     b = 2\n"));
        editing.toggleComment(0, 20);
        QCOMPARE(text(), QString("a = 1\n    b = 2\n"));

        editing.indent(0, 10);
        QCOMPARE(text(), QString("    a = 1\n        b = 2\n"));
        editing.outdent(0, 20);
        editing.outdent(0, 20);
        QCOMPARE(text(), QString("a = 1\nb = 2\n"));
        undo();
        QCOMPARE(text(), QString("a = 1\n    b = 2\n"));

        // In CSS, a line that only opens with an inline comment isn't
        // commented: it's wrapped whole, and unwrapped back.
        {
            const QString css = dir.filePath("t.css");
            write(css, "/* bar */ .bar { color: red; }\n");
            QVERIFY(doc.open(css));
            editing.toggleComment(0, 0);
            // The */ inside is escaped, so the whole line is one comment.
            QCOMPARE(text(), QString("/* /* bar *\\/ .bar { color: red; } */\n"));
            const QString commented = text().trimmed();
            QCOMPARE(Highlighter::tokens("css", {commented}), QString(commented.size(), 'c'));
            editing.toggleComment(0, 0);
            QCOMPARE(text(), QString("/* bar */ .bar { color: red; }\n"));
            // A *\/ that was already there comes back as it was.
            write(css, ".x::after { content: \"*\\/ and */\"; }\n");
            QVERIFY(doc.open(css));
            editing.toggleComment(0, 0);
            QCOMPARE(Highlighter::tokens("css", {text().trimmed()}), QString(text().trimmed().size(), 'c'));
            editing.toggleComment(0, 0);
            QCOMPARE(text(), QString(".x::after { content: \"*\\/ and */\"; }\n"));
            QVERIFY(doc.open(path));
        }

        // Enter keeps the indentation.
        const int end = text().indexOf("2") + 1;
        QCOMPARE(editing.newline(end, end), end + 5);
        QCOMPARE(text(), QString("a = 1\n    b = 2\n    \n"));
        undo();

        QCOMPARE(editing.matchCount("= ", false), 2);
        QCOMPARE(editing.replaceAll("= ", ":= ", true), 2);
        QCOMPARE(text(), QString("a := 1\n    b := 2\n"));
        undo();
        QCOMPARE(text(), QString("a = 1\n    b = 2\n"));
        QCOMPARE(editing.find("=", 3, false, false), QVariantList({12, 13}));
        QCOMPARE(editing.find("=", 13, false, false), QVariantList({2, 3})); // wraps around
        QCOMPARE(editing.lineOf(7), 2);
        QCOMPARE(editing.positionOfLine(2), 6);
    }

    // QML calls these from Ctrl+O and Ctrl+S; plain C++ methods it can't.
    // A portal that owns its name but never answers can't freeze Plain:
    // asking it, and asking again, return at once.
    void aHungPortalDoesntFreeze()
    {
        if (QStandardPaths::findExecutable("dbus-daemon").isEmpty())
            QSKIP("needs dbus-daemon for a private bus");
        QProcess daemon;
        daemon.start("dbus-daemon", {"--session", "--print-address", "--nofork"});
        QVERIFY(daemon.waitForReadyRead(5000));
        const QString address = QString::fromUtf8(daemon.readLine()).trimmed();
        QDBusConnection bus = QDBusConnection::connectToBus(address, "plain-test");
        QVERIFY(bus.isConnected());

        // A copy of this test program takes the portal's name, then is
        // stopped outright, so nothing on its side answers anything.
        QProcess portal;
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert("PLAIN_HUNG_PORTAL_BUS", address);
        portal.setProcessEnvironment(environment);
        portal.start(QCoreApplication::applicationFilePath(), {"hungPortal"});
        QTRY_VERIFY_WITH_TIMEOUT(bus.interface()->isServiceRegistered("org.freedesktop.portal.Desktop"), 10000);
        ::kill(portal.processId(), SIGSTOP);

        PortalFilePicker picker(nullptr, bus);
        QElapsedTimer clock;
        clock.start();
        picker.openFile(QDir::tempPath());
        QVERIFY2(clock.elapsed() < 1000, qPrintable(QString::number(clock.elapsed())));
        // Asking again replaces the stuck request, promptly too.
        clock.restart();
        picker.saveFile(QDir::tempPath() + "/x.conf");
        QVERIFY2(clock.elapsed() < 1000, qPrintable(QString::number(clock.elapsed())));

        portal.kill();
        portal.waitForFinished();
        QDBusConnection::disconnectFromBus("plain-test");
        daemon.kill();
        daemon.waitForFinished();
    }

    // The portal aHungPortalDoesntFreeze stops: run only as its helper.
    void hungPortal()
    {
        const QString address = qEnvironmentVariable("PLAIN_HUNG_PORTAL_BUS");
        if (address.isEmpty())
            QSKIP("the hung portal's helper, run by aHungPortalDoesntFreeze");
        QDBusConnection portal = QDBusConnection::connectToBus(address, "hung-portal");
        QVERIFY(portal.registerService("org.freedesktop.portal.Desktop"));
        QThread::sleep(60);
    }

    void filePickerIsCallableFromQml()
    {
        QVERIFY(PortalFilePicker::staticMetaObject.indexOfMethod("openFile(QString)") >= 0);
        QVERIFY(PortalFilePicker::staticMetaObject.indexOfMethod("saveFile(QString)") >= 0);
    }

    // Theme and translator, from the template.

    void themeFallsBack()
    {
        QTemporaryDir dir;
        Theme theme(dir.path());
        QCOMPARE(theme.accent(), QColor("#FFD60A"));
        QCOMPARE(theme.textSize(), 12);
    }

    // Rounding follows Hyprland: asked at start and on each config reload
    // Hyprland announces, never on a timer.
    void themeFollowsHyprlandRounding()
    {
        QTemporaryDir dir;
        write(dir.filePath("rounding"), "4");
        write(dir.filePath("hyprctl"), "#!/bin/sh\necho \"{\\\"int\\\": $(cat '" + QFile::encodeName(dir.filePath("rounding")) + "')}\"\n");
        QFile::setPermissions(dir.filePath("hyprctl"), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        QLocalServer hyprland;
        QVERIFY(hyprland.listen(dir.filePath("events.sock")));

        // The theme's folder apart from the fakes: a theme change asks too.
        QDir(dir.path()).mkpath("state");
        Theme theme(dir.filePath("state"), nullptr, dir.filePath("hyprctl"), dir.filePath("events.sock"));
        QTRY_COMPARE(theme.radius(), 4);
        QTRY_VERIFY(hyprland.hasPendingConnections());
        QLocalSocket *events = hyprland.nextPendingConnection();

        // Changed without telling anyone: nothing asks again.
        write(dir.filePath("rounding"), "8");
        QTest::qWait(1500);
        QCOMPARE(theme.radius(), 4);

        // Other events don't ask either; a config reload does.
        events->write("workspace>>2\n");
        events->flush();
        QTest::qWait(300);
        QCOMPARE(theme.radius(), 4);
        events->write("configreloaded>>\n");
        events->flush();
        QTRY_COMPARE(theme.radius(), 8);
    }

    // A reload announced while hyprctl is still answering isn't lost: it
    // may have read the rounding from before.
    void aReloadDuringARoundingReadIsKept()
    {
        QTemporaryDir dir;
        write(dir.filePath("rounding"), "4");
        // Reads the rounding, then takes its time answering.
        write(dir.filePath("hyprctl"), "#!/bin/sh\nv=$(cat '" + QFile::encodeName(dir.filePath("rounding"))
                                           + "')\nsleep 0.25\necho \"{\\\"int\\\": $v}\"\n");
        QFile::setPermissions(dir.filePath("hyprctl"), QFile::ReadOwner | QFile::WriteOwner | QFile::ExeOwner);
        QLocalServer hyprland;
        QVERIFY(hyprland.listen(dir.filePath("events.sock")));
        QDir(dir.path()).mkpath("state");
        Theme theme(dir.filePath("state"), nullptr, dir.filePath("hyprctl"), dir.filePath("events.sock"));
        QTRY_VERIFY(hyprland.hasPendingConnections());
        QLocalSocket *events = hyprland.nextPendingConnection();
        // While the first read sleeps on the old value.
        QTest::qWait(100);
        write(dir.filePath("rounding"), "8");
        events->write("configreloaded>>\n");
        events->flush();
        QTRY_COMPARE_WITH_TIMEOUT(theme.radius(), 8, 3000);
    }

    // The display panel's Text size: the user's override, else the theme's.
    void themeFollowsTheDesktopTextSize()
    {
        QTemporaryDir dir;
        QDir(dir.path()).mkpath("theme");
        write(dir.path() + "/theme/shell.toml",
              "[bar]\nbase-size = 99\n\n[font]\n# base-size = 20\nbase-size = 13\n");
        Theme theme(dir.path());
        QCOMPARE(theme.textSize(), 13);

        write(dir.path() + "/shell.toml", "[font]\nbase-size = 16\n");
        QTRY_COMPARE(theme.textSize(), 16);
        QFile::remove(dir.path() + "/shell.toml");
        QTRY_COMPARE(theme.textSize(), 13);
    }

    void translatorFallsBackToEnglish()
    {
        QTemporaryDir dir;
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.language(), QString("en"));
        QVERIFY(translator.translate("Main", "Save").isNull());
    }

    // 21 is "one" in Russian but plural in English, so the find bar's English
    // fallback must count by English rules, not show "21 match".
    void translatorCountsAFallbackByItsOwnLanguage()
    {
        LocaleGuard guard;
        QTemporaryDir dir;
        write(dir.path() + "/language", "ru\n");
        write(dir.path() + "/en.json", R"({"%n matches": {"one": "%n match", "other": "%n matches"}})");
        write(dir.path() + "/ru.json",
              R"({"%n files": {"one": "%n файл", "few": "%n файла", "many": "%n файлов", "other": "%n файла"}})");
        Translator translator(dir.path() + "/language", dir.path());
        QCOMPARE(translator.translate("Main", "%n files", nullptr, 21), QString("%n файл"));
        QCOMPARE(translator.translate("Main", "%n files", nullptr, 25), QString("%n файлов"));
        QCOMPARE(translator.translate("FindBar", "%n matches", nullptr, 21), QString("%n matches"));
        QCOMPARE(translator.translate("FindBar", "%n matches", nullptr, 1), QString("%n match"));
    }

    // A first language pick can create ~/.config/omarchy itself.
    void translatorFollowsAFirstPickThatCreatesItsDirectory()
    {
        LocaleGuard guard;
        QTemporaryDir dir;
        write(dir.path() + "/da.json", R"({"Save": "Gem"})");
        const QString language = dir.path() + "/config/omarchy/language";
        Translator translator(language, dir.path());
        QCOMPARE(translator.language(), QString("en"));

        QVERIFY(QDir().mkpath(QFileInfo(language).absolutePath()));
        write(language, "da\n");
        QTRY_COMPARE(translator.language(), QString("da"));
        QCOMPARE(translator.translate("Main", "Save"), QString("Gem"));
    }

    // The catalogs.

    void englishCatalogMatchesTheSources() {
        // en.json is the source translators work from: every text the
        // sources translate is in it, as itself or (when a count is passed)
        // as its English plural forms, and nothing else is.
        QStringList problems;
        const QMap<QString, bool> used = translatables(sourceFolder(), &problems);
        QVERIFY(used.size() > 70);
        QVERIFY(used.value("%n matches"));
        QVERIFY(used.value("Replaced %n"));
        const QJsonObject english = readCatalog(sourceFolder() + "/i18n/en.json", &problems);
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

    void sourceScanRefusesABuiltText() {
        QTemporaryDir dir;
        write(dir.filePath("Saved.qml"), "Label { text: qsTr(\"Saved \" + name); tip: qsTr(\"Saved\", \"\", count) }\n");
        QStringList problems;
        const QMap<QString, bool> used = translatables(dir.path(), &problems);
        QCOMPARE(used.keys(), QStringList{"Saved"});
        QVERIFY(used.value("Saved"));
        QCOMPARE(problems.size(), 1);
        QVERIFY2(problems.first().startsWith("Saved.qml: not a literal: qsTr(\"Saved \" + name)"), qPrintable(problems.first()));
    }

    void catalogsMatchTheEnglishOne() {
        QStringList problems = catalogProblems(sourceFolder() + "/i18n");
        // Every language has its catalog, empty until the sync fills it: the
        // sync only changes catalogs that exist, and only these are compiled in.
        for (const QString &code : languageCodes())
            if (!QFileInfo::exists(sourceFolder() + "/i18n/" + code + ".json"))
                problems << code + ".json: missing";
        QVERIFY2(problems.isEmpty(), qPrintable(problems.join('\n')));
    }

    void catalogChecksCatchBrokenTranslations() {
        QTemporaryDir dir;
        write(dir.filePath("en.json"), R"({"Open": "Open", "Open %1": "Open %1",
                                              "%Ln items": {"one": "%Ln item", "other": "%Ln items"},
                                              "%Ln items in %1": {"one": "%Ln item in %1", "other": "%Ln items in %1"}})");
        // Polish needs one, few, many and other; a form may say "one" in
        // words, but not drop the document.
        write(dir.filePath("pl.json"), R"({"Open": "Otwórz", "Open %1": "Otwórz",
                                              "%Ln items": {"one": "jeden element", "few": "%Ln elementy", "other": "%Ln elementu"},
                                              "%Ln items in %1": {"one": "jeden element", "few": "%Ln elementy w %1",
                                                                  "many": "%Ln elementów w %1", "other": "%Ln elementu w %1"}})");
        write(dir.filePath("da.json"), R"({"Open": " ", "Open %1": "Åbn %1",
                                              "%Ln items": {"one": "ét element", "other": "  "},
                                              "%Ln items in %1": {"one": "%Ln element i %1", "other": "%Ln elementer i %1"}})");
        // German hasn't caught up yet: one string still to translate and one
        // the English has since dropped.
        write(dir.filePath("de.json"), R"({"Open": "Öffnen", "Opened": "Geöffnet"})");
        write(dir.filePath("xx.json"), "{}");
        QStringList problems = catalogProblems(dir.path());
        problems.sort();
        QCOMPARE(problems, QStringList({"da: %Ln items: other needs a translation",
                                        "da: Open: needs a translation",
                                        "pl: %Ln items in %1: one has other placeholders than the English",
                                        "pl: %Ln items: needs exactly the plural forms few, many, one, other",
                                        "pl: Open %1: has other placeholders than the English",
                                        "xx.json: not one of Omarchy's language codes"}));
    }

    void everyCatalogIsCompiledIn() {
        QFile resources(sourceFolder() + "/resources.qrc");
        QVERIFY(resources.open(QIODevice::ReadOnly));
        const QString listed = QString::fromUtf8(resources.readAll());
        QStringList left;
        for (const QString &name : QDir(sourceFolder() + "/i18n").entryList({"*.json"}, QDir::Files))
            if (!listed.contains("<file>i18n/" + name + "</file>"))
                left << name;
        QVERIFY2(left.isEmpty(), qPrintable("not in resources.qrc: " + left.join(", ")));
    }

private:
    // A Translator sets the app's default locale and layout direction.
    struct LocaleGuard {
        QLocale locale;
        Qt::LayoutDirection direction = QGuiApplication::layoutDirection();
        ~LocaleGuard()
        {
            QLocale::setDefault(locale);
            QGuiApplication::setLayoutDirection(direction);
        }
    };

    static void write(const QString &path, const QByteArray &contents)
    {
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write(contents);
    }

    // Replaces the file the way other editors do, so the watch has to re-arm.
    static void replace(const QString &path, const QByteArray &contents)
    {
        write(path + ".tmp", contents);
        QVERIFY(::rename(QFile::encodeName(path + ".tmp").constData(), QFile::encodeName(path).constData()) == 0);
    }

    // Main.qml as main.cpp loads it, over a folder with a.conf and b.conf
    // in root/, with settings and the trash kept in the temporary folder.
    struct PlainWindow {
        QTemporaryDir dir;
        QByteArray config = qgetenv("XDG_CONFIG_HOME"), data = qgetenv("XDG_DATA_HOME");
        Theme theme{dir.path()};
        Document doc;
        Editing editing{&doc};
        PortalFilePicker picker;
        FileTree files;
        Launcher launcher;
        QQmlApplicationEngine engine;
        QQuickWindow *window = nullptr;

        PlainWindow()
        {
            QDir(dir.path()).mkpath("root");
            QDir(dir.path()).mkpath("data");
            write(path("root/a.conf"), "a\n");
            write(path("root/b.conf"), "b\n");
            qputenv("XDG_CONFIG_HOME", QFile::encodeName(path("config")));
            qputenv("XDG_DATA_HOME", QFile::encodeName(path("data")));
            doc.setTheme(&theme);
        }
        ~PlainWindow()
        {
            delete window;
            restore("XDG_CONFIG_HOME", config);
            restore("XDG_DATA_HOME", data);
        }
        static void restore(const char *name, const QByteArray &value)
        {
            if (value.isNull())
                qunsetenv(name);
            else
                qputenv(name, value);
        }

        QString path(const QString &relative) const { return QDir::cleanPath(dir.filePath(relative)); }

        bool load(const QString &file, const QString &folder)
        {
            QQmlContext *context = engine.rootContext();
            context->setContextProperty("theme", &theme);
            context->setContextProperty("doc", &doc);
            context->setContextProperty("editing", &editing);
            context->setContextProperty("picker", &picker);
            context->setContextProperty("files", &files);
            context->setContextProperty("launcher", &launcher);
            context->setContextProperty("startPath", file.isEmpty() ? QString() : path(file));
            context->setContextProperty("startLine", 0);
            context->setContextProperty("startFolder", folder.isEmpty() ? QString() : path(folder));
            context->setContextProperty("homePath", QDir::homePath());
            engine.load(QUrl::fromLocalFile(sourceFolder() + "/Main.qml"));
            if (engine.rootObjects().isEmpty())
                return false;
            window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
            window->requestActivate();
            return window && QTest::qWaitForWindowActive(window);
        }

        // By objectName, through both the object and the item trees: an
        // ApplicationWindow's items aren't all its QObject children.
        QObject *item(const char *name) const
        {
            QList<QObject *> queue{window};
            QSet<QObject *> seen;
            while (!queue.isEmpty()) {
                QObject *object = queue.takeFirst();
                if (!object || seen.contains(object))
                    continue;
                seen.insert(object);
                if (object->objectName() == QLatin1String(name))
                    return object;
                queue << object->children();
                if (auto *quick = qobject_cast<QQuickItem *>(object))
                    for (QQuickItem *child : quick->childItems())
                        queue << child;
                if (object == window)
                    queue << window->contentItem();
            }
            qWarning("no %s in the window", name);
            return nullptr;
        }
        QObject *sidebar() const { return item("sidebar"); }
        bool editorFocused() const
        {
            QQuickItem *focus = window->activeFocusItem();
            auto *editor = qobject_cast<QQuickItem *>(item("editorView"));
            return focus && editor && editor->isAncestorOf(focus);
        }
        void key(Qt::Key key, Qt::KeyboardModifiers modifiers = {}) { QTest::keyClick(window, key, modifiers); }
        void type(const char *text)
        {
            for (const char *c = text; *c; ++c)
                QTest::keyClick(window, *c);
        }
    };

    static QStringList names(const FileTree &tree)
    {
        QStringList names;
        for (int i = 0; i < tree.rowCount(); ++i)
            names << tree.data(tree.index(i), FileTree::NameRole).toString();
        return names;
    }

    static QByteArray read(const QString &path)
    {
        QFile file(path);
        return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray("<unreadable>");
    }

    static void undo(QQuickItem *edit)
    {
        edit->property("textDocument").value<QQuickTextDocument *>()->textDocument()->undo();
    }

    static void append(QTextDocument *document, const QString &text)
    {
        QTextCursor cursor(document);
        cursor.movePosition(QTextCursor::End);
        cursor.insertText(text);
    }

    static int mode(const QString &path)
    {
        struct stat st;
        return ::stat(QFile::encodeName(path).constData(), &st) == 0 ? int(st.st_mode & 07777) : -1;
    }

    static ino_t inode(const QString &path)
    {
        struct stat st;
        return ::stat(QFile::encodeName(path).constData(), &st) == 0 ? st.st_ino : 0;
    }
};

QTEST_MAIN(PlainTests)
#include "plain_tests.moc"

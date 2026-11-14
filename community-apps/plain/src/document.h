#pragma once

#include <QByteArray>
#include <QFileSystemWatcher>
#include <QObject>
#include <QPointer>
#include <QQuickItem>
#include <QTextDocument>
#include <QTimer>

#include "theme.h"

class Highlighter;

// The file behind the editor: loading it, saving it without damage, and
// noticing when it changes underneath. The QTextDocument belongs to the QML
// TextEdit and is the one source of truth for the text.
class Document : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString path READ path NOTIFY fileChanged)
    Q_PROPERTY(QString displayPath READ displayPath NOTIFY fileChanged)
    Q_PROPERTY(QString fileName READ fileName NOTIFY fileChanged)
    Q_PROPERTY(QString lineEnding READ lineEnding NOTIFY fileChanged)
    Q_PROPERTY(QString indentUnit READ indentUnit NOTIFY fileChanged)
    Q_PROPERTY(bool modified READ modified NOTIFY modifiedChanged)
    Q_PROPERTY(bool editable READ editable NOTIFY fileChanged)
    // The user can't write the file: saving it needs sudo.
    Q_PROPERTY(bool locked READ locked NOTIFY fileChanged)
    Q_PROPERTY(QString problem READ problem NOTIFY problemChanged)
    Q_PROPERTY(QString problemDetail READ problemDetail NOTIFY problemChanged)

public:
    // What the banner shows. Each one names the situation, and QML picks the
    // words and buttons.
    enum class Problem {
        None,
        NotFound,        // the path doesn't exist and its folder doesn't either
        NotRegular,      // a folder, device or pipe
        NotReadable,     // permission denied: belongs to root or someone else
        NotText,         // not UTF-8, NUL bytes, lone CRs, or U+FDEF
        TooLarge,        // big enough that TextEdit would be slow; asks first
        MixedEndings,    // opened fine; will be saved with the majority ending
        ChangedOnDisk,   // changed elsewhere while there are unsaved edits
        DeletedOnDisk,   // removed elsewhere
        Conflict,        // a save found a version of the file the user hasn't seen
        Retargeted,      // the symlink now points at a different file
        NotWritable,     // the user can't write the file: sudoedit is the way
        NeedsInPlace,    // an atomic replace would lose something; ask first
        SaveFailed,      // the write itself failed
        ModeLost,        // saved in place, but its special permission bits couldn't be restored
    };
    Q_ENUM(Problem)

    // The result of reading bytes as text, separate from the file so tests
    // can feed it bytes directly.
    struct Decoded {
        QString text;          // LF line endings, no BOM
        bool bom = false;
        bool crlf = false;
        bool mixed = false;
        bool ok = false;
    };
    static Decoded decode(const QByteArray &bytes);
    static QByteArray encode(const QTextDocument *document, bool bom, bool crlf);
    static QString detectIndent(const QString &text);
    static QByteArray hash(const QByteArray &bytes);
    static QByteArray stamp(const QString &path);

    explicit Document(QObject *parent = nullptr);

    void setTheme(Theme *theme) { m_theme = theme; }

    QString path() const { return m_path; }
    QString displayPath() const;
    QString fileName() const;
    QString language() const { return m_language; }
    QString commentPrefix() const;
    QString lineEnding() const { return m_crlf ? "CRLF" : "LF"; }
    QString indentUnit() const { return m_indentUnit; }
    bool modified() const;
    bool editable() const { return m_editable; }
    bool locked() const { return m_locked; }
    QString problem() const;
    QString problemDetail() const { return m_problemDetail; }

    // Hands over the TextEdit; everything else needs it first. Files load
    // through its text property, which is where Qt Quick turns on drawing only
    // the visible lines of a long text: loaded behind its back, every
    // keystroke in a 10,000-line file redrew all of it (57 ms instead of 1).
    Q_INVOKABLE void attach(QQuickItem *textEdit);
    // Tests without a TextEdit hand over a bare document.
    void attachDocument(QTextDocument *document);
    QTextDocument *textDocument() const { return m_document; }

    Q_INVOKABLE bool open(const QString &path);
    Q_INVOKABLE bool openUrl(const QUrl &url);
    // Saves to the current file; false with a problem set when it didn't.
    Q_INVOKABLE bool save();
    Q_INVOKABLE bool saveAsUrl(const QUrl &url);
    // The banner's answers.
    Q_INVOKABLE bool overwrite();        // Conflict, DeletedOnDisk: save over what's there now
    Q_INVOKABLE bool overwriteInPlace(); // NeedsInPlace
    Q_INVOKABLE void reload();           // ChangedOnDisk, Conflict
    Q_INVOKABLE void keepMine();         // ChangedOnDisk
    Q_INVOKABLE void dismissProblem();
    Q_INVOKABLE void openAnyway();       // TooLarge

    // Measured on Qt 6.12: Qt Quick's TextEdit opens a 1 MB config in about
    // a second and a 20,000-character line in under one, but a 100 KB line
    // takes half a minute. Past these, Plain asks before opening.
    static constexpr qint64 LargeFileBytes = 1024 * 1024;
    static constexpr int LongLineChars = 20000;
    static bool tooLarge(qint64 size, const QString &text);

signals:
    void fileChanged();
    void modifiedChanged();
    void problemChanged();
    // Around a reload from disk, so the view can keep the cursor's line.
    void aboutToReload();
    void reloaded();

private:
    bool load(bool reload);
    void setText(const QString &text, bool undoably);
    bool checkAndWrite(bool inPlace);
    bool write(const QString &target, bool inPlace);
    void rememberDisk(const QByteArray &bytes);
    void forgetDisk();
    void acknowledgeDisk();
    QString currentTarget() const;
    QString unsafeForRename(const QString &target) const;
    void setProblem(Problem problem, const QString &detail = {});
    void watch();
    void diskChanged();
    void setLanguageFor(const QString &path, const QString &firstLine, bool recolor = true);

    QPointer<QQuickItem> m_textEdit;
    QPointer<QTextDocument> m_document;
    QPointer<Theme> m_theme;
    Highlighter *m_highlighter = nullptr;

    QString m_path;              // what the user opened, as they wrote it (absolute)
    QString m_target;            // the regular file it resolves to, at open
    QByteArray m_diskHash;       // the bytes last read or written; empty: no file yet
    QByteArray m_diskStamp;      // stamp() of that version, to skip rereading unchanged files
    bool m_bom = false;
    bool m_crlf = false;
    QString m_indentUnit = "    ";
    QString m_language = "text";
    bool m_editable = true;
    bool m_allowLarge = false;
    bool m_locked = false;

    Problem m_problem = Problem::None;
    QString m_problemDetail;

    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
};

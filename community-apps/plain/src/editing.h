#pragma once

#include <QObject>
#include <QVariantList>

class Document;
class QTextDocument;

// Edits the TextEdit can't do by itself, made on its QTextDocument through
// QTextCursor edit blocks, so each one is a single step in the TextEdit's own
// undo stack. Positions are the TextEdit's cursor positions.
class Editing : public QObject {
    Q_OBJECT

public:
    explicit Editing(Document *document, QObject *parent = nullptr);

    // Comments the lines the selection touches, or uncomments them when all
    // of them already are. Uses the language's own comment marker.
    Q_INVOKABLE void toggleComment(int start, int end);
    // Indents and outdents every non-empty line the selection touches.
    Q_INVOKABLE void indent(int start, int end);
    Q_INVOKABLE void outdent(int start, int end);
    // Replaces the selection with a line break and the current line's
    // indentation; returns where the cursor goes.
    Q_INVOKABLE int newline(int start, int end);

    // [start, end] of the next match after `from` (or before it, backward),
    // wrapping around; empty when there's none.
    Q_INVOKABLE QVariantList find(const QString &text, int from, bool backward, bool caseSensitive) const;
    Q_INVOKABLE int matchCount(const QString &text, bool caseSensitive) const;
    Q_INVOKABLE int replace(int start, int end, const QString &replacement);
    Q_INVOKABLE int replaceAll(const QString &text, const QString &replacement, bool caseSensitive);

    Q_INVOKABLE int lineCount() const;
    Q_INVOKABLE int lineOf(int position) const;   // 1-based
    Q_INVOKABLE int positionOfLine(int line) const;

private:
    QTextDocument *document() const;
    Document *m_document;
};

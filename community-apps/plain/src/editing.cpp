#include "editing.h"

#include "document.h"

#include <QTextBlock>
#include <QTextCursor>
#include <QTextDocument>

namespace {
// The blocks a selection touches. A selection ending at the very start of a
// line doesn't include that line, the way every editor treats it.
QList<QTextBlock> touchedBlocks(QTextDocument *document, int start, int end) {
    if (end < start)
        std::swap(start, end);
    QTextBlock first = document->findBlock(start);
    QTextBlock last = document->findBlock(end);
    if (end > start && last.position() == end && last != first)
        last = last.previous();
    QList<QTextBlock> blocks;
    for (QTextBlock block = first; block.isValid(); block = block.next()) {
        blocks << block;
        if (block == last)
            break;
    }
    return blocks;
}

int leadingWhitespace(const QString &text) {
    int i = 0;
    while (i < text.size() && (text.at(i) == ' ' || text.at(i) == '\t'))
        ++i;
    return i;
}
}

Editing::Editing(Document *document, QObject *parent) : QObject(parent), m_document(document) {}

QTextDocument *Editing::document() const {
    return m_document ? m_document->textDocument() : nullptr;
}

void Editing::toggleComment(int start, int end) {
    QTextDocument *doc = document();
    const QString prefix = m_document ? m_document->commentPrefix() : QString();
    if (!doc || prefix.isEmpty())
        return;
    // CSS has only block comments, so each line is wrapped: /* line */.
    const QString suffix = prefix == "/*" ? " */" : QString();

    QList<QTextBlock> lines;
    for (const QTextBlock &block : touchedBlocks(doc, start, end))
        if (!block.text().trimmed().isEmpty())
            lines << block;
    if (lines.isEmpty())
        return;

    bool allCommented = true;
    int column = INT_MAX;
    for (const QTextBlock &block : lines) {
        const QString text = block.text();
        const int indent = leadingWhitespace(text);
        column = qMin(column, indent);
        if (!text.mid(indent).startsWith(prefix))
            allCommented = false;
    }

    QTextCursor cursor(doc);
    cursor.beginEditBlock();
    for (const QTextBlock &block : lines) {
        const QString text = block.text();
        if (allCommented) {
            const int at = leadingWhitespace(text);
            int length = prefix.size();
            if (at + length < text.size() && text.at(at + length) == ' ')
                ++length;
            if (!suffix.isEmpty() && text.endsWith("*/")) {
                const int cut = text.endsWith(suffix) ? suffix.size() : 2;
                cursor.setPosition(block.position() + text.size() - cut);
                cursor.setPosition(block.position() + text.size(), QTextCursor::KeepAnchor);
                cursor.removeSelectedText();
            }
            cursor.setPosition(block.position() + at);
            cursor.setPosition(block.position() + at + length, QTextCursor::KeepAnchor);
            cursor.removeSelectedText();
        } else {
            if (!suffix.isEmpty()) {
                cursor.setPosition(block.position() + text.size());
                cursor.insertText(suffix);
            }
            cursor.setPosition(block.position() + column);
            cursor.insertText(prefix + " ");
        }
    }
    cursor.endEditBlock();
}

void Editing::indent(int start, int end) {
    QTextDocument *doc = document();
    if (!doc)
        return;
    const QString unit = m_document->indentUnit();
    QTextCursor cursor(doc);
    cursor.beginEditBlock();
    for (const QTextBlock &block : touchedBlocks(doc, start, end)) {
        if (block.text().trimmed().isEmpty())
            continue;
        cursor.setPosition(block.position());
        cursor.insertText(unit);
    }
    cursor.endEditBlock();
}

void Editing::outdent(int start, int end) {
    QTextDocument *doc = document();
    if (!doc)
        return;
    const int width = m_document->indentUnit() == "\t" ? 4 : qMax(1, int(m_document->indentUnit().size()));
    QTextCursor cursor(doc);
    cursor.beginEditBlock();
    for (const QTextBlock &block : touchedBlocks(doc, start, end)) {
        const QString text = block.text();
        int remove = 0;
        if (text.startsWith('\t'))
            remove = 1;
        else
            while (remove < width && remove < text.size() && text.at(remove) == ' ')
                ++remove;
        if (remove == 0)
            continue;
        cursor.setPosition(block.position());
        cursor.setPosition(block.position() + remove, QTextCursor::KeepAnchor);
        cursor.removeSelectedText();
    }
    cursor.endEditBlock();
}

int Editing::newline(int start, int end) {
    QTextDocument *doc = document();
    if (!doc)
        return start;
    if (end < start)
        std::swap(start, end);
    const QTextBlock block = doc->findBlock(start);
    const QString before = block.text().left(start - block.position());
    const QString indent = before.left(leadingWhitespace(before));

    QTextCursor cursor(doc);
    cursor.beginEditBlock();
    cursor.setPosition(start);
    cursor.setPosition(end, QTextCursor::KeepAnchor);
    cursor.insertText("\n" + indent);
    cursor.endEditBlock();
    return cursor.position();
}

QVariantList Editing::find(const QString &text, int from, bool backward, bool caseSensitive) const {
    QTextDocument *doc = document();
    if (!doc || text.isEmpty())
        return {};
    QTextDocument::FindFlags flags;
    if (backward)
        flags |= QTextDocument::FindBackward;
    if (caseSensitive)
        flags |= QTextDocument::FindCaseSensitively;
    QTextCursor found = doc->find(text, from, flags);
    if (found.isNull()) {
        QTextCursor wrap(doc);
        if (backward)
            wrap.movePosition(QTextCursor::End);
        found = doc->find(text, wrap, flags);
    }
    if (found.isNull())
        return {};
    return {found.selectionStart(), found.selectionEnd()};
}

int Editing::matchCount(const QString &text, bool caseSensitive) const {
    QTextDocument *doc = document();
    if (!doc || text.isEmpty())
        return 0;
    int count = 0;
    QTextCursor cursor(doc);
    const auto flags = caseSensitive ? QTextDocument::FindCaseSensitively : QTextDocument::FindFlags();
    while (!(cursor = doc->find(text, cursor, flags)).isNull())
        ++count;
    return count;
}

int Editing::replace(int start, int end, const QString &replacement) {
    QTextDocument *doc = document();
    if (!doc)
        return start;
    QTextCursor cursor(doc);
    cursor.setPosition(start);
    cursor.setPosition(end, QTextCursor::KeepAnchor);
    cursor.insertText(replacement);
    return cursor.position();
}

int Editing::replaceAll(const QString &text, const QString &replacement, bool caseSensitive) {
    QTextDocument *doc = document();
    if (!doc || text.isEmpty())
        return 0;
    const auto flags = caseSensitive ? QTextDocument::FindCaseSensitively : QTextDocument::FindFlags();
    int count = 0;
    QTextCursor edit(doc);
    edit.beginEditBlock();
    QTextCursor found(doc);
    while (!(found = doc->find(text, found, flags)).isNull()) {
        found.insertText(replacement);
        ++count;
    }
    edit.endEditBlock();
    return count;
}

int Editing::lineCount() const {
    QTextDocument *doc = document();
    return doc ? doc->blockCount() : 0;
}

int Editing::lineOf(int position) const {
    QTextDocument *doc = document();
    return doc ? doc->findBlock(position).blockNumber() + 1 : 1;
}

int Editing::positionOfLine(int line) const {
    QTextDocument *doc = document();
    if (!doc)
        return 0;
    const QTextBlock block = doc->findBlockByNumber(qBound(1, line, doc->blockCount()) - 1);
    return block.position();
}

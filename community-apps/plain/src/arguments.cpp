#include "arguments.h"

#include <QRegularExpression>
#include <QUrl>

Arguments Arguments::parse(const QStringList &arguments) {
    Arguments result;
    QStringList files;
    bool literal = false;
    static const QRegularExpression lineOption("^\\+([0-9]+)$");
    static const QRegularExpression scheme("^[a-zA-Z][a-zA-Z0-9+.-]*://");

    for (const QString &argument : arguments.mid(1)) {
        if (!literal) {
            if (argument == "--") {
                literal = true;
                continue;
            }
            if (argument == "-h" || argument == "--help") {
                result.help = true;
                continue;
            }
            if (argument == "--version") {
                result.version = true;
                continue;
            }
            if (const auto match = lineOption.match(argument); match.hasMatch()) {
                result.line = match.captured(1).toInt();
                continue;
            }
            if (argument.startsWith('-') && argument != "-") {
                result.error = QStringLiteral("unknown option %1").arg(argument);
                return result;
            }
        }
        if (scheme.match(argument).hasMatch()) {
            const QUrl url(argument);
            if (!url.isLocalFile()) {
                result.error = QStringLiteral("can only open local files, not %1").arg(argument);
                return result;
            }
            files << url.toLocalFile();
        } else {
            files << argument;
        }
    }

    if (files.size() > 1) {
        result.error = QStringLiteral("opens one file at a time, got %1").arg(files.size());
        return result;
    }
    if (!files.isEmpty())
        result.path = files.first();
    return result;
}

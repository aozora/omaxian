#pragma once

#include <QString>
#include <QStringList>

// `plain [+LINE] [--] [FILE]`. Everything after `--` is a literal filename,
// which is how omarchy-launch-editor passes paths. file:// URIs (xdg-open)
// become paths; other schemes are refused. More than one file is an error
// rather than a silent drop, since sudoedit can hand an editor several.
struct Arguments {
    QString path;
    int line = 0;
    bool help = false;
    bool version = false;
    QString error;

    static Arguments parse(const QStringList &arguments);
};

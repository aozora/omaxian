#pragma once

#include <QStringList>

// Headless commands for scripts and agents: signed signatures, pages, text,
// render, sign, and so on. None of them needs a display.
bool isCliCommand(const QString &word);
QString cliSummary();
int runCli(const QStringList &arguments);

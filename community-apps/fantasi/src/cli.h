#pragma once

#include <QStringList>

// The commands that need no window: `fantasi generate`, help and version.
bool isCliCommand(int argc, char *argv[]);

// Runs one, with the application's arguments; the exit code.
int runCli(const QStringList &arguments);

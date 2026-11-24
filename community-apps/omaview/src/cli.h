#pragma once

#include <QStringList>

// Commands that need no display, for scripts and agents, after Hype's.
bool isCliCommand(const QString &word);
int runCli(const QStringList &arguments);
QString cliSummary();

// "90", "1:30", "1:02:03.5" as seconds; negative when it isn't a time.
double parseTime(const QString &text);
// Seconds formatted as "h:mm:ss.mmm", clamped at 0.
QString formatTime(double seconds);

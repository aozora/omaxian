#pragma once

#include <QCoreApplication>
#include <QObject>
#include <QProcess>

// Another Plain, in a window of its own: Ctrl+N while the files are hidden.
// Each window is its own process, so closing one never touches another.
class Launcher : public QObject {
    Q_OBJECT

public:
    using QObject::QObject;

    Q_INVOKABLE bool newWindow() const { return QProcess::startDetached(QCoreApplication::applicationFilePath(), {}); }
};

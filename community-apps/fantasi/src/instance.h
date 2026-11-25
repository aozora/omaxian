#pragma once

#include <QJsonObject>
#include <QLocalServer>
#include <QObject>

// One Fantasi window at a time: the first one listens on a socket in the
// user's runtime folder, and a later `fantasi open` hands it what it was asked
// for (a model to use, a prompt to start) instead of opening a second window.
class Instance : public QObject {
    Q_OBJECT

public:
    explicit Instance(const QString &path = defaultPath(), QObject *parent = nullptr);

    static QString defaultPath();

    // Hands `request` to a window already open and returns true, or becomes
    // the one window and returns false. Two launches at once take turns.
    bool handOver(const QJsonObject &request);
    // Hands `request` to a window already open; false when none answers.
    bool forward(const QJsonObject &request) const;
    // Becomes the one window, taking over a socket left by one that crashed.
    bool listen();

signals:
    void requested(const QJsonObject &request);

private:
    QString m_path;
    QLocalServer m_server;
};

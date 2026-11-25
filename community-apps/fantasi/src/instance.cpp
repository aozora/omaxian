#include "instance.h"

#include <QJsonDocument>
#include <QLockFile>
#include <QLocalSocket>
#include <QStandardPaths>

Instance::Instance(const QString &path, QObject *parent) : QObject(parent), m_path(path) {
    connect(&m_server, &QLocalServer::newConnection, this, [this] {
        while (QLocalSocket *socket = m_server.nextPendingConnection()) {
            connect(socket, &QLocalSocket::disconnected, socket, &QObject::deleteLater);
            connect(socket, &QLocalSocket::readyRead, this, [this, socket] {
                if (!socket->canReadLine())
                    return;
                const QJsonObject request = QJsonDocument::fromJson(socket->readLine()).object();
                socket->disconnectFromServer();
                emit requested(request);
            });
        }
    });
}

QString Instance::defaultPath() {
    return QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + "/fantasi.sock";
}

bool Instance::handOver(const QJsonObject &request) {
    // Held until this launch is listening, so another launch at the same
    // moment waits, then finds this one and hands over to it.
    QLockFile lock(m_path + ".lock");
    lock.setStaleLockTime(5000);
    lock.lock();
    if (forward(request))
        return true;
    listen();
    return false;
}

bool Instance::forward(const QJsonObject &request) const {
    QLocalSocket socket;
    socket.connectToServer(m_path);
    if (!socket.waitForConnected(500))
        return false;
    socket.write(QJsonDocument(request).toJson(QJsonDocument::Compact) + "\n");
    return socket.waitForBytesWritten(1000);
}

bool Instance::listen() {
    // Nothing answered forward(), so a socket still there is a crashed one's.
    QLocalServer::removeServer(m_path);
    m_server.setSocketOptions(QLocalServer::UserAccessOption);
    return m_server.listen(m_path);
}

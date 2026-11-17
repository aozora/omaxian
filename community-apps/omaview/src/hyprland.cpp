#include "hyprland.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QLocalSocket>
#include <QString>

namespace hyprland {

bool reshape(QSize size) {
    const QByteArray instance = qgetenv("HYPRLAND_INSTANCE_SIGNATURE");
    const QByteArray runtime = qgetenv("XDG_RUNTIME_DIR");
    if (QGuiApplication::platformName() != QLatin1String("wayland") || instance.isEmpty() || runtime.isEmpty()
        || size.isEmpty())
        return false;
    QLocalSocket socket;
    socket.connectToServer(QString::fromLocal8Bit(runtime + "/hypr/" + instance + "/.socket.sock"));
    if (!socket.waitForConnected(200))
        return false;
    const QString window = QStringLiteral("pid:%1").arg(QCoreApplication::applicationPid());
    const QString batch =
        QStringLiteral("[[BATCH]]dispatch hl.dsp.window.resize({ window = \"%1\", x = %2, y = %3 });"
                       "dispatch hl.dsp.window.center({ window = \"%1\" })")
            .arg(window)
            .arg(size.width())
            .arg(size.height());
    socket.write(batch.toUtf8());
    if (!socket.waitForBytesWritten(200) || !socket.waitForReadyRead(200))
        return false;
    return socket.readAll().startsWith("ok");
}

}  // namespace hyprland

#include "inhibit.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QProcess>
#include <QStandardPaths>

IdleInhibitor::IdleInhibitor(QObject *parent) : QObject(parent) {}

IdleInhibitor::~IdleInhibitor() {
    release();
}

void IdleInhibitor::setActive(bool active) {
    if (m_active == active)
        return;
    m_active = active;
    update();
    emit activeChanged();
}

void IdleInhibitor::setWindow(QWindow *window) {
    if (m_window == window)
        return;
    if (m_window)
        disconnect(m_window, nullptr, this, nullptr);
    release();
    m_window = window;
    // The surface/XID can go away when the window is hidden; re-apply then.
    if (m_window)
        connect(m_window, &QWindow::visibleChanged, this, [this] {
            release();
            update();
        });
    update();
    emit windowChanged();
}

void IdleInhibitor::release() {
    if (m_cookie != 0) {
        QDBusInterface iface(QStringLiteral("org.freedesktop.ScreenSaver"),
                             QStringLiteral("/org/freedesktop/ScreenSaver"),
                             QStringLiteral("org.freedesktop.ScreenSaver"),
                             QDBusConnection::sessionBus());
        if (iface.isValid())
            iface.call(QStringLiteral("UnInhibit"), m_cookie);
        m_cookie = 0;
    }
    if (m_xdgSuspended && m_xdgWindowId != 0) {
        const QString tool = QStandardPaths::findExecutable(QStringLiteral("xdg-screensaver"));
        if (!tool.isEmpty())
            QProcess::execute(tool, {QStringLiteral("resume"), QString::number(m_xdgWindowId)});
        m_xdgSuspended = false;
        m_xdgWindowId = 0;
    }
}

void IdleInhibitor::update() {
    if (!m_active || !m_window || !m_window->isVisible()) {
        release();
        return;
    }
    if (m_cookie != 0 || m_xdgSuspended)
        return;

    QDBusInterface iface(QStringLiteral("org.freedesktop.ScreenSaver"),
                         QStringLiteral("/org/freedesktop/ScreenSaver"),
                         QStringLiteral("org.freedesktop.ScreenSaver"),
                         QDBusConnection::sessionBus());
    if (iface.isValid()) {
        const QDBusReply<uint> reply =
            iface.call(QStringLiteral("Inhibit"), QStringLiteral("omaview"),
                       QStringLiteral("Playing video"));
        if (reply.isValid() && reply.value() != 0) {
            m_cookie = reply.value();
            return;
        }
    }

    const QString tool = QStandardPaths::findExecutable(QStringLiteral("xdg-screensaver"));
    if (tool.isEmpty())
        return;
    const WId id = m_window->winId();
    if (id == 0)
        return;
    if (QProcess::execute(tool, {QStringLiteral("suspend"), QString::number(id)}) == 0) {
        m_xdgSuspended = true;
        m_xdgWindowId = id;
    }
}

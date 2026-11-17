#pragma once

#include <QObject>
#include <QPointer>
#include <QWindow>
#include <QtGlobal>

// Keeps the screen on while a video plays.
// Omaxian: org.freedesktop.ScreenSaver over D-Bus, then xdg-screensaver
// suspend on the window XID (works with xss-lock). Upstream Omarchy uses a
// Wayland idle-inhibit on the surface instead.
class IdleInhibitor : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged)
    Q_PROPERTY(QWindow *window READ window WRITE setWindow NOTIFY windowChanged)

public:
    explicit IdleInhibitor(QObject *parent = nullptr);
    ~IdleInhibitor() override;

    bool active() const { return m_active; }
    void setActive(bool active);
    QWindow *window() const { return m_window; }
    void setWindow(QWindow *window);

signals:
    void activeChanged();
    void windowChanged();

private:
    void update();
    void release();

    bool m_active = false;
    QPointer<QWindow> m_window;
    uint m_cookie = 0;
    bool m_xdgSuspended = false;
    WId m_xdgWindowId = 0;
};

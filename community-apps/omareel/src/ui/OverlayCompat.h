#pragma once

// Omaxian: the recording bar, countdown and camera self-view are Wayland layer-shell surfaces
// upstream. Three things differ here:
//
// - LayerShellQt is optional (OMAREEL_LAYER_SHELL, off by default). Without it the stand-in below
//   takes its calls and does nothing, as LayerShellQt itself does on X11.
// - LayerShellQt before 6.4 (Debian trixie / Devuan Excalibur ship 6.3) has no per-window screen
//   or activate-on-show setting. The window's own screen is used instead, which is what
//   LayerShellQt 6.4 falls back to as well.
// - On X11 (the xcb platform) the layer-shell settings do nothing. The overlays become
//   override-redirect windows: the window manager does not tile, decorate or focus them, and
//   placeX11Overlay() puts them where the layer-shell anchors and margins would.

#if OMAREEL_LAYER_SHELL
#include <LayerShellQt/shell.h>
#include <LayerShellQt/window.h>
#endif

#include <QFlags>
#include <QGuiApplication>
#include <QMargins>
#include <QRect>
#include <QScreen>
#include <QWindow>

#if !OMAREEL_LAYER_SHELL
// The part of LayerShellQt's API omareel calls, doing nothing.
namespace LayerShellQt {

class Shell
{
public:
    static void useLayerShell() {}
};

class Window
{
public:
    enum Layer { LayerBackground, LayerBottom, LayerTop, LayerOverlay };
    enum Anchor { AnchorNone = 0, AnchorTop = 1, AnchorBottom = 2, AnchorLeft = 4, AnchorRight = 8 };
    Q_DECLARE_FLAGS(Anchors, Anchor)
    enum KeyboardInteractivity { KeyboardInteractivityNone, KeyboardInteractivityExclusive, KeyboardInteractivityOnDemand };

    static Window *get(QWindow *)
    {
        static Window window;
        return &window;
    }
    void setLayer(Layer) {}
    void setAnchors(Anchors) {}
    void setExclusiveZone(int) {}
    void setKeyboardInteractivity(KeyboardInteractivity) {}
    void setMargins(const QMargins &) {}
    void setScope(const QString &) {}
};
Q_DECLARE_OPERATORS_FOR_FLAGS(Window::Anchors)

} // namespace LayerShellQt
#endif

namespace omaxian {

inline void layerSetScreen([[maybe_unused]] LayerShellQt::Window *layer, [[maybe_unused]] QScreen *screen)
{
#if OMAREEL_LAYER_SHELL && OMAREEL_LAYERSHELL_SCREEN
    layer->setScreen(screen);
#endif
}

inline QScreen *layerScreen([[maybe_unused]] LayerShellQt::Window *layer, QWindow *window)
{
#if OMAREEL_LAYER_SHELL && OMAREEL_LAYERSHELL_SCREEN
    return layer->screen();
#else
    return window->screen();
#endif
}

inline void layerNoActivateOnShow([[maybe_unused]] LayerShellQt::Window *layer)
{
#if OMAREEL_LAYER_SHELL && OMAREEL_LAYERSHELL_SCREEN
    layer->setActivateOnShow(false);
#endif
}

inline bool x11Overlays()
{
    return QGuiApplication::platformName() == QLatin1String("xcb");
}

enum class OverlayAnchor { TopCenter, Center, TopLeft };

// Makes `window` an override-redirect overlay that never takes focus, and moves it onto `screen`
// (its own screen when null) as a layer surface with `anchor` and `margins` would sit. Call it
// before the window is first shown: X11 sets override-redirect when the window is created.
inline void placeX11Overlay(QWindow *window, QScreen *screen, OverlayAnchor anchor, const QMargins &margins = {})
{
    if (!window || !x11Overlays()) return;
    // Set once: this runs on every drag step of the camera bubble, and re-applying flags to a
    // mapped window re-sends its window-manager hints.
    const Qt::WindowFlags overlay = Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint
        | Qt::X11BypassWindowManagerHint | Qt::WindowDoesNotAcceptFocus;
    if ((window->flags() & overlay) != overlay) window->setFlags(window->flags() | overlay);
    if (!screen) screen = window->screen();
    if (!screen) return;
    const QRect area = screen->geometry();
    QPoint at;
    switch (anchor) {
    case OverlayAnchor::TopCenter:
        at = QPoint(area.x() + (area.width() - window->width()) / 2, area.y() + margins.top());
        break;
    case OverlayAnchor::Center:
        at = QPoint(area.x() + (area.width() - window->width()) / 2, area.y() + (area.height() - window->height()) / 2);
        break;
    case OverlayAnchor::TopLeft:
        at = QPoint(area.x() + margins.left(), area.y() + margins.top());
        break;
    }
    window->setPosition(at);
}

} // namespace omaxian

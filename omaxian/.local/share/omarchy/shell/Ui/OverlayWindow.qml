import QtQuick
import Quickshell
import qs.Commons as Commons

// X11 stand-in for upstream's fullscreen WlrLayershell OverlayWindow
// (Quickshell.Hyprland + Quickshell.Wayland). Same `shown` / contentReady /
// contentRevealed contract so remirrored consumers (menu, wifiqr, osd,
// emojis, reminders, …) keep compiling.
//
// Full-screen *transparent* PanelWindows black out under picom glx (see
// Ui/CenteredModal). Use a near-opaque black fill so the compositor keeps
// painting; consumers that draw their own scrim still look right. Prefer
// CenteredModal for new content-sized cards that do not need a scrim.
//
// Drop any `WlrLayershell.*` attached properties when remirroring callers —
// they require Quickshell.Wayland and are ignored here.
PanelWindow {
  id: window

  property bool shown: false
  // Upstream enums; accepted and ignored on X11.
  property int shownLayer: 0
  property int shownKeyboardFocus: 0

  property var targetScreen: null
  readonly property var targetMonitor: targetScreen

  readonly property bool contentReady: shown && !!targetScreen
  property bool contentRevealed: false

  onContentReadyChanged: {
    contentRevealed = false
    if (contentReady) Qt.callLater(function() {
      if (window.contentReady) window.contentRevealed = true
    })
  }

  function focusedScreen() {
    if (Quickshell.screens.length > 0) return Quickshell.screens[0]
    return null
  }

  onShownChanged: targetScreen = shown ? focusedScreen() : null

  Connections {
    target: Quickshell
    function onScreensChanged() {
      if (window.shown && Quickshell.screens.indexOf(window.targetScreen) < 0) {
        window.targetScreen = null
        Qt.callLater(function() {
          if (window.shown && !window.targetScreen) window.targetScreen = window.focusedScreen()
        })
      }
    }
  }

  visible: shown && !!targetScreen
  screen: targetScreen
  anchors { top: true; left: true; bottom: true; right: true }
  // Near-opaque: transparent fullscreen + picom glx → black tiled windows.
  color: shown ? "#E6000000" : "transparent"
  exclusionMode: ExclusionMode.Ignore
  aboveWindows: true
  focusable: shown

  Binding {
    target: window.contentItem
    property: "opacity"
    value: window.contentRevealed ? 1 : 0
  }

  Binding {
    target: window.contentItem
    property: "LayoutMirroring.enabled"
    value: Commons.I18n.rightToLeft
  }
  Binding {
    target: window.contentItem
    property: "LayoutMirroring.childrenInherit"
    value: true
  }
}

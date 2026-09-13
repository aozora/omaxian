import QtQuick
import Quickshell
import qs.Commons

// A content-sized modal card centred on screen — the X11-safe replacement for
// upstream's full-screen `WlrLayershell` overlays (wifiqr / speedtest /
// disk-speedtest / the reminder flow). Those black out under picom's glx
// backend: a full-screen transparent surface trips fullscreen unredirection,
// so its transparent regions stop compositing and paint black. This never
// maps a full-screen surface.
//
//   * Prefer `anchorWindow` (the already-mapped bar PanelWindow). Mapping a
//     fresh 1px PanelWindow host makes X11 emit another
//     `_NET_WM_WINDOW_TYPE_DOCK`; i3 restacks/reflows the real bar + dock and
//     it reads as a one-frame duplicate.
//   * Fallback `host` is a 1px-tall PanelWindow strip along the screen top
//     when no bar window is available yet. Same shape as Ui/PopupCard's
//     anchor space.
//   * `card` is a standalone `PopupWindow` (content-sized, `anchor.window`
//     → bar or host) — the same shape as Ui/PopupCard / KeyboardPanel, which
//     is what makes `grabFocus` (`Qt::Popup`) actually deliver keyboard input
//     on X11. Declared as a sibling of `host`, NOT nested inside it.
//
// Trade-off vs the Wayland original: no full-screen dimming scrim, and no
// click-in-empty-space dismissal. Escape, re-summoning, and the IPC toggle all
// still close it — the consumer wires `dismissed()` to its `close()` /
// `shell.hide(...)`. A press outside the card also dismisses (the `grabFocus`
// pointer grab), when the compositor delivers it.
Item {
  id: root

  property bool open: false
  property int contentWidth: Style.space(360)
  property int contentHeight: Style.space(280)
  property int padding: Style.spacing.popupPadding
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  property color background: Color.popups.background
  // Item inside `content` that should take keyboard focus on open.
  property Item focusTarget: null
  // Prefer the live bar PanelWindow so we never map a second DOCK surface.
  property var anchorWindow: null

  default property alias content: holder.children

  signal dismissed()

  readonly property var _screen: {
    if (root.anchorWindow && root.anchorWindow.screen)
      return root.anchorWindow.screen
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }
  readonly property real _screenW: _screen ? _screen.width : 0
  readonly property real _screenH: _screen ? _screen.height : 0
  readonly property var _anchorWindow: root.anchorWindow || host
  readonly property bool _useFallbackHost: !root.anchorWindow

  onOpenChanged: {
    if (root.open) {
      // grabFocus dismissal clobbers the declarative `visible` binding; re-arm.
      card.visible = Qt.binding(function() { return root.open || card.opacity > 0 })
      focusNudge.restart()
      return
    }
    // Never unmap the grabFocus PopupWindow synchronously from a Keys
    // handler living inside it — that use-after-frees in Quickshell 0.3.0
    // (seen as SIGSEGV in the IPC ready-read path right after ReminderFlow
    // submits). Let the current event finish, then hide.
    Qt.callLater(function() {
      if (!root.open)
        card.visible = false
    })
  }

  // The `card` PopupWindow is Qt::Popup / override-redirect; under i3 that
  // never actually receives X11 keyboard focus on map, so
  // `forceActiveFocus()` alone only picks the focused *item*, not the
  // window. `scripts/focus-window.py` does the XSetInputFocus that makes it
  // stick (see that file + Bar/widgets/MenuButton.qml). The delay lets the
  // window finish mapping first.
  Timer {
    id: focusNudge
    interval: 60
    onTriggered: {
      if (!root.open) return
      Quickshell.execDetached(["python3", Quickshell.shellDir + "/scripts/focus-window.py"])
      if (root.focusTarget) root.focusTarget.forceActiveFocus()
    }
  }

  // Fallback only: full-width 1px strip so `card` has a screen-wide window to
  // centre against when the bar is not up yet.
  PanelWindow {
    id: host
    visible: root._useFallbackHost && (root.open || card.visible)
    screen: root._screen
    anchors { top: true; left: true; right: true }
    implicitHeight: 1
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
  }

  PopupWindow {
    id: card
    // Visibility is driven from onOpenChanged so close can be deferred
    // (see comment there). Start closed; open path installs the binding.
    visible: false
    color: "transparent"
    implicitWidth: Math.max(1, root.contentWidth)
    // Floor of 64: scripts/focus-window.py ignores QS windows <= 40px tall
    // (that's the bar strip), so the card must clear that to be found.
    implicitHeight: Math.max(64, root.contentHeight)
    grabFocus: true

    anchor {
      window: root._anchorWindow
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      adjustment: PopupAdjustment.Slide
      rect.width: 1
      rect.height: 1
      // Bar PanelWindow origin is the screen origin for a top bar, so these
      // are screen coordinates. Fallback host sits just below the bar strut;
      // the same formula is slightly low there but only used before the bar
      // exists.
      rect.x: Math.round(Math.max(0, (root._screenW - card.implicitWidth) / 2))
      rect.y: Math.round(Math.max(0, (root._screenH - card.implicitHeight) / 2))
    }

    onVisibleChanged: {
      if (!visible && root.open) root.dismissed()
    }

    BorderSurface {
      id: cardSurface
      anchors.fill: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.padding
      radius: Style.radiusPopup

      MouseArea { anchors.fill: parent }

      FocusScope {
        id: holder
        anchors.fill: parent
        anchors.topMargin: cardSurface.contentTopInset
        anchors.rightMargin: cardSurface.contentRightInset
        anchors.bottomMargin: cardSurface.contentBottomInset
        anchors.leftMargin: cardSurface.contentLeftInset
        focus: true
        Keys.priority: Keys.AfterItem
        Keys.onEscapePressed: function(event) {
          // Same deferral as onOpenChanged: do not tear down from inside Keys.
          Qt.callLater(function() { root.dismissed() })
          event.accepted = true
        }
      }
    }
  }
}

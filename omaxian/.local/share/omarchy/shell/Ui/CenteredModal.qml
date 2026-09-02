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
//   * `host` is a 1px-tall PanelWindow strip along the screen top. A
//     top-anchored QS PanelWindow spans the full screen width, giving the
//     PopupWindow a full-width coordinate space to centre X against; 1px tall,
//     so picom never treats it as a full-screen surface.
//   * `card` is a standalone `PopupWindow` (content-sized, `anchor.window:
//     host`) — the same shape as Ui/PopupCard / the converted KeyboardPanel,
//     which is what makes `grabFocus` (`Qt::Popup`) actually deliver keyboard
//     input on X11. Declared as a sibling of `host`, NOT nested inside it.
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

  default property alias content: holder.children

  signal dismissed()

  readonly property var _screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  readonly property real _screenW: _screen ? _screen.width : 0
  readonly property real _screenH: _screen ? _screen.height : 0

  onOpenChanged: {
    if (!root.open) return
    // grabFocus dismissal clobbers the declarative `visible` binding; re-arm.
    card.visible = Qt.binding(function() { return root.open || card.opacity > 0 })
    focusNudge.restart()
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

  // Full-width 1px strip: only there to give `card` a screen-wide window to
  // anchor + centre against.
  PanelWindow {
    id: host
    visible: root.open || card.visible
    screen: root._screen
    anchors { top: true; left: true; right: true }
    implicitHeight: 1
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
  }

  PopupWindow {
    id: card
    visible: root.open
    color: "transparent"
    implicitWidth: Math.max(1, root.contentWidth)
    // Floor of 64: scripts/focus-window.py ignores QS windows <= 40px tall
    // (that's the bar strip), so the card must clear that to be found.
    implicitHeight: Math.max(64, root.contentHeight)
    grabFocus: true

    anchor {
      window: host
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      adjustment: PopupAdjustment.Slide
      rect.width: 1
      rect.height: 1
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
          root.dismissed()
          event.accepted = true
        }
      }
    }
  }
}

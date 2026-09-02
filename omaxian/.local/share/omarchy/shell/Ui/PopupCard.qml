import QtQuick
import Quickshell
import qs.Commons

// X11 delta (T2): dismissal is `PopupWindow.grabFocus` (pointer grab) PLUS a
// full-screen transparent `dismissCatcher` window. `grabFocus` alone stopped
// dismissing on a click into another application window once popups anchored
// to the real plugins/bar dock (`_NET_WM_STATE_ABOVE`) instead of the 1px
// widgets-only host — the catcher is the reliable, compositor-agnostic path
// (the same pattern Ui/KeyboardPanel uses). `grabFocus` is kept because it
// makes the card `Qt::Popup` (which can take keyboard focus for the
// launcher/runner fields; `Qt::ToolTip` cannot).
PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property color borderColor: Color.popups.border
  property var borderSpec: Border.localOrSurfaceSpec("popups", "border", borderColor, Color.popups.border, Math.max(1, Style.space(2)))
  property bool open: false
  // Center under the host window when polybar is the visible bar
  // (`QS_WIDGETS_ONLY`): popup-host widgets are undrawn so there is no
  // meaningful button to anchor to. Full-bar mode still anchors to the
  // triggering widget.
  property bool centerOnBar: !!(bar && bar.widgetsOnly)
  // "click" — uses PopupWindow.grabFocus so clicking outside dismisses the popup.
  // "hover" — passive overlay; the owning widget controls open via hover.
  property string triggerMode: "click"

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property bool containsMouse: cardHover.hovered
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  readonly property real barW: anchorWindow ? anchorWindow.width : 0
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((bar && (bar.position === "left" || bar.position === "right")) ? barW : 0) - root.margin * 2)
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((bar && (bar.position === "top" || bar.position === "bottom")) ? barH : 0) - root.margin * 2)
    : 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  default property alias contentItem: contentHolder.children

  visible: open || card.opacity > 0
  color: "transparent"
  implicitWidth: contentWidth
  implicitHeight: contentHeight

  onOpenChanged: {
    if (!bar) return
    if (open) {
      bar.requestPopout(coordinatorKey)
      // grabFocus (below) dismisses by writing `visible = false` directly,
      // which permanently breaks the declarative `visible` binding above.
      // Re-arm it on every open so a prior dismissal doesn't leave the
      // popup stuck invisible next time it's reopened.
      visible = Qt.binding(function() { return root.open || card.opacity > 0 })
      escapeFocus.restart()
    } else if (bar.activePopout === coordinatorKey) {
      bar.releasePopout(coordinatorKey)
    }
  }

  // Outside-click dismissal, X11 port: PopupWindow's own `grabFocus` is a
  // cross-platform equivalent of Hyprland's focus grab (X11 uses a pointer
  // grab under the hood) — no compositor-specific API needed here. Skipped
  // for hover-mode popups so the cursor can move freely between the trigger
  // and the popup.
  //
  // Deliberately NOT `root.open && root.triggerMode === "click"`: PopupWindow
  // reads grabFocus once, at the moment it creates the underlying window
  // (`Qt::Popup` if true, `Qt::ToolTip` — which never receives keyboard
  // input, by X11/EWMH convention — if false), and gating it on `open`
  // ties both to the exact same transition, racing the C++ side's read
  // against the binding's own re-evaluation. Confirmed live with an X11
  // keyboard-focus trace (`XSetInputFocus`/`get_input_focus` via
  // python-xlib): the popup was consistently created as
  // `_NET_WM_WINDOW_TYPE_TOOLTIP`, and no text field inside it could ever
  // take keyboard input as a result — not a focus-timing issue on our side,
  // the window itself was architecturally never going to accept focus.
  // `triggerMode` is static per-instance (never toggles after creation),
  // so there's no need to also key this off `open` — it only has any
  // effect while the window is mapped regardless.
  grabFocus: root.triggerMode === "click"

  onVisibleChanged: {
    if (!visible && root.open) root.close()
  }

  anchor {
    id: popupAnchor
    window: anchorItem ? anchorItem.QsWindow.window : null
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar) return

      var target = root.anchorItem
      var popupWidth = root.implicitWidth
      var popupHeight = root.implicitHeight
      var localX = target.width / 2 - popupWidth / 2
      var localY = target.height + root.margin

      if (root.bar.position === "bottom") {
        localY = -popupHeight - root.margin
      } else if (root.bar.position === "left") {
        localX = target.width + root.margin
        localY = target.height / 2 - popupHeight / 2
      } else if (root.bar.position === "right") {
        localX = -popupWidth - root.margin
        localY = target.height / 2 - popupHeight / 2
      }

      var window = target.QsWindow.window
      if (!window) return

      if (root.centerOnBar) {
        // When polybar is the visible bar (widgets-only) the host window is
        // 1px tall, so `window.height` can't clear it — offset by the real
        // strip height the bar exposes instead.
        var topStrip = (root.bar && root.bar.visibleBarSize !== undefined)
          ? root.bar.visibleBarSize : window.height
        var cx = 0;
        var cy = 0;
        if (root.bar.position === "top" || root.bar.position === "bottom") {
          cx = window.width / 2 - popupWidth / 2
          cy = root.bar.position === "bottom" ? -popupHeight - root.margin : topStrip + root.margin
          cx = Math.max(root.margin, Math.min(cx, window.width - popupWidth - root.margin))
        } else {
          cx = root.bar.position === "left" ? window.width + root.margin : -popupWidth - root.margin
          cy = window.height / 2 - popupHeight / 2
          cy = Math.max(root.margin, Math.min(cy, window.height - popupHeight - root.margin))
        }

        popupAnchor.rect.x = Math.round(cx)
        popupAnchor.rect.y = Math.round(cy)
        return
      }

      var point = window.contentItem.mapFromItem(target, localX, localY)

      if (root.bar.position === "top" || root.bar.position === "bottom") {
        point.x = Math.max(root.margin, Math.min(point.x, window.width - popupWidth - root.margin))
      } else {
        point.y = Math.max(root.margin, Math.min(point.y, window.height - popupHeight - root.margin))
      }

      popupAnchor.rect.x = Math.round(point.x)
      popupAnchor.rect.y = Math.round(point.y)
    }
  }

  // (Attempted a full-screen transparent dismiss catcher here — under
  // glx-picom's fullscreen unredirection it painted the whole screen black
  // and still didn't receive clicks landing on application windows. Removed.
  // Widget-popup dismissal is: click the bar / re-click the trigger (handled
  // in plugins/bar/Bar.qml's modulePointer), the IPC toggle, or Escape.
  // Click-into-a-window dismissal needs the KeyboardPanel conversion +
  // picom `unredir-if-possible-exclude` for quickshell — see phase-8.md.)

  Timer {
    id: escapeFocus
    interval: 60
    onTriggered: {
      if (!root.open) return
      Quickshell.execDetached(["python3", Quickshell.shellDir + "/scripts/focus-window.py"])
      contentHolder.forceActiveFocus()
    }
  }

  BorderSurface {
    id: card
    anchors.fill: parent
    color: Color.popups.background
    borderSpec: root.borderSpec
    padding: root.padding
    radius: Style.radiusPopup
    opacity: root.open ? 1.0 : 0

    Behavior on opacity {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    FocusScope {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      focus: true
      Keys.priority: Keys.AfterItem
      Keys.onEscapePressed: function(event) {
        root.close()
        event.accepted = true
      }
    }

    HoverHandler {
      id: cardHover
    }
  }
}

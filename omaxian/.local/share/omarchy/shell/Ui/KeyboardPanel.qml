import QtQuick
import Quickshell
import qs.Commons

// Popup card attached to a bar widget icon, for click-driven AND
// keyboard-driven panels (e.g. a keybinding-triggered summon).
//
// X11 port history:
//  - Upstream is a full-screen `WlrLayershell` overlay with a full-screen
//    dismiss surface. The T1 pass first mapped that to a full-screen X11
//    `PanelWindow` + `focusable` — which, under picom v12.5's glx backend,
//    blacked the entire screen whenever any app window was mapped (the
//    full-screen transparent surface never composited and culled everything
//    behind it).
//  - Now built on `PopupWindow` (same primitive as Ui/PopupCard), sized to
//    the card via implicitWidth/Height and positioned by its `anchor` block.
//    No full-screen surface exists, so there is nothing for picom to cull.
//
// `PopupWindow` reads `grabFocus` once at window creation: `true` makes the
// window `Qt::Popup`, which on X11 takes an active pointer+keyboard grab when
// shown — that is what lets `focusTarget` (a PanelKeyCatcher, typically) take
// keyboard focus immediately on open, before any click, which is the whole
// reason this stays separate from a plain tooltip-style popup. The grab also
// restores click-outside dismissal (a press outside the popup closes it),
// except a click straight into another application window while anchored to
// the `_NET_WM_STATE_ABOVE` bar dock is unreliable — same accepted limitation
// as the LocalHost widget popups; re-click the trigger / click another bar
// widget / Escape / the IPC toggle all still close it.
//
// API is a subset of Common.PopupCard: anchorItem, owner, bar, open, padding,
// margin, contentWidth/Height, centerOnBar, default contentItem, plus
// fittedContentWidth/Height / cappedContentHeight for the plugin panels.
PopupWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  property bool centerOnBar: false
  property bool open: false
  property int gap: Style.gapsOut  // distance between bar edge and panel
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false

  // Item that should take keyboard focus once the panel maps. Typically a
  // PanelKeyCatcher inside the panel content. The `Qt::Popup` grab (from
  // grabFocus below) gives the window keyboard focus at map time, but Qt
  // still needs an active-focus target inside the surface for Keys.onPressed
  // handlers to fire — scheduled through Qt.callLater so it runs after the
  // surface is mapped and children have laid out.
  property Item focusTarget: null

  default property alias contentItem: contentHolder.children

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: bar ? bar.position : "top"

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  // --- geometry --------------------------------------------------------

  visible: open || card.opacity > 0 || popoutSwitching
  color: "transparent"
  implicitWidth: Math.max(1, contentWidth)
  implicitHeight: Math.max(1, contentHeight)

  readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
  readonly property real screenW: popupScreen ? popupScreen.width : 0
  readonly property real screenH: popupScreen ? popupScreen.height : 0
  readonly property real barW: anchorWindow ? anchorWindow.width : screenW
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  readonly property real anchorH: anchorItem ? anchorItem.height : 0

  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((barPos === "left" || barPos === "right") ? barW + gap + margin : margin * 2))
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((barPos === "top" || barPos === "bottom") ? barH + gap + margin : margin * 2))
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

  // --- outside-click dismissal + focus (X11: Qt::Popup grab) ------------
  //
  // Read once at window creation. Always true here — KeyboardPanel is never a
  // passive hover popup, and only `Qt::Popup` (not `Qt::ToolTip`) can hold
  // keyboard focus for the PanelKeyCatcher / text fields inside.
  grabFocus: true

  onVisibleChanged: {
    // grabFocus dismissal writes `visible = false` directly; propagate that
    // to the logical close so the owner's state follows.
    if (!visible && root.open) root.close()
  }

  // --- popout coordination (same-bar single-popout model) ---------------

  // Coordinate on `open`, not `visible`. `visible` lags into the fade-out
  // animation, which made ownership transfer to a sibling popup race.
  onOpenChanged: {
    if (open) {
      // grabFocus dismissal breaks the declarative `visible` binding by
      // assigning it directly; re-arm on every open.
      visible = Qt.binding(function() { return root.open || card.opacity > 0 || root.popoutSwitching })
      Qt.callLater(function() {
        if (!root.open) return
        if (root.focusTarget) root.focusTarget.forceActiveFocus()
        else contentHolder.forceActiveFocus()
      })
    }
    if (!bar) return
    if (open) {
      popoutSwitchClosing = false
      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey
      bar.requestPopout(coordinatorKey)
      if (popoutSwitching) popoutSwitchTimer.restart()
    } else {
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false
      if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
      if (popoutSwitchClosing) closeSwitchTimer.restart()
    }
  }

  Timer {
    id: popoutSwitchTimer
    interval: 150
    onTriggered: root.popoutSwitching = false
  }

  Timer {
    id: closeSwitchTimer
    interval: 1
    onTriggered: root.popoutSwitchClosing = false
  }

  // --- positioning -----------------------------------------------------
  //
  // Places the card centred under the trigger button (or centred on the bar
  // when `centerOnBar`), clamped to the screen, `gap` px off the bar edge.
  // Ported from the old full-screen build's `cardOrigin`, expressed here as
  // an anchor rect in the bar window's content coordinates (same approach as
  // Ui/PopupCard).
  anchor {
    id: popupAnchor
    window: root.anchorWindow
    adjustment: PopupAdjustment.Slide
    edges: Edges.Top | Edges.Left
    gravity: Edges.Bottom | Edges.Right
    rect.width: 1
    rect.height: 1

    onAnchoring: {
      if (!root.anchorItem || !root.bar) return
      var window = root.anchorWindow
      if (!window) return

      var pw = root.implicitWidth
      var ph = root.implicitHeight
      var target = root.anchorItem
      var horizontal = (root.barPos === "top" || root.barPos === "bottom")

      // Bar strip thickness. The anchor window IS the bar, so its own
      // dimension across the strip is the strip size; fall back to a sane
      // default if it hasn't sized yet (a re-anchor corrects it once it has).
      var strip = horizontal
        ? (window.height > 1 ? window.height : (root.bar.barSize || 34))
        : (window.width > 1 ? window.width : (root.bar.barSize || 34))

      // Cross-strip axis (away from the bar): a fixed gap past the strip.
      // Along-strip axis: centred under the trigger button, or on the bar
      // when `centerOnBar`.
      var buttonPos = window.contentItem.mapFromItem(target, 0, 0)
      var x, y
      if (horizontal) {
        y = root.barPos === "bottom" ? window.height - strip - ph - root.gap : strip + root.gap
        x = root.centerOnBar
          ? window.width / 2 - pw / 2
          : buttonPos.x + target.width / 2 - pw / 2
      } else {
        x = root.barPos === "right" ? window.width - strip - pw - root.gap : strip + root.gap
        y = root.centerOnBar
          ? window.height / 2 - ph / 2
          : buttonPos.y + target.height / 2 - ph / 2
      }

      // Clamp against the SCREEN, not the bar window (which is only the strip
      // thick — clamping y to it would slam every panel back up under the
      // bar). `rect` is in bar-window content coords ≈ screen coords for a
      // screen-aligned bar; PopupAdjustment.Slide handles any residual.
      var maxX = (root.screenW > 0 ? root.screenW : window.width) - pw - root.margin
      var maxY = (root.screenH > 0 ? root.screenH : 2000) - ph - root.margin
      x = Math.max(root.margin, Math.min(x, Math.max(root.margin, maxX)))
      y = Math.max(root.margin, Math.min(y, Math.max(root.margin, maxY)))
      popupAnchor.rect.x = Math.round(x)
      popupAnchor.rect.y = Math.round(y)
    }
  }

  // --- card ------------------------------------------------------------

  BorderSurface {
    id: card
    anchors.fill: parent
    color: Color.popups.background
    borderSpec: root.borderSpec
    padding: root.padding
    radius: Style.radiusPopup
    opacity: root.open || root.popoutSwitching ? 1.0 : 0

    Behavior on opacity {
      enabled: !root.popoutSwitching && !root.popoutSwitchClosing
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    // Swallow clicks on the card body so they don't fall through the
    // transparent window to whatever is behind it.
    MouseArea { anchors.fill: parent }

    FocusScope {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      opacity: root.popoutSwitching ? (root.open ? 1.0 : 0) : 1.0
      focus: true
      Keys.priority: Keys.AfterItem
      Keys.onEscapePressed: function(event) {
        root.close()
        event.accepted = true
      }

      Behavior on opacity {
        enabled: root.popoutSwitching
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "OsdModel.js" as OsdModel

// X11 / picom note: upstream draws the OSD in a full-screen transparent
// layer-shell overlay, which blacks out tiled windows under picom glx (the same
// failure KeyboardPanel / CenteredModal already left behind). This OSD is a
// content-sized PopupWindow anchored to a 1px top host strip, bottom-centred
// on the screen. Visual-only: grabFocus stays false (Qt::ToolTip) so volume
// keys never steal keyboard focus from the focused client.

Item {
  id: root

  property bool opened: false
  property string icon: "󰕾"
  property string message: ""
  property string iconKey: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: true
  property int duration: 1200

  readonly property bool mediaOsd: iconKey.indexOf("media") === 0 || iconKey.indexOf("player") === 0

  // The card is built out of measured columns instead of fixed widths, so it
  // keeps exactly `pad` between border and content on every side whatever
  // glyph or message it carries. Messages grow with their text up to
  // `maxMessageWidth` and elide beyond it.
  // Volume/brightness glyphs are Nerd Font / MDI codepoints (OsdModel.js).
  // Style.font.family stays "monospace" on this port (no fc-match resolver),
  // which resolves to DejaVu, so pin a Nerd Font face that has the set.
  readonly property string iconFontFamily: "JetBrainsMono Nerd Font"

  readonly property int pad: Style.space(16)
  readonly property int gap: Style.space(16)
  // A glyph next to a message reads airier than it measures: the icon outline
  // and the letterforms both fall away from their ink extremes, so the space
  // between them opens up well past the nominal gap. Text takes two thirds of
  // it; the progress bar's hard edge keeps the full gap.
  readonly property int messageGap: Math.round(root.gap * 2 / 3)
  readonly property int barWidth: Style.space(142)
  readonly property int maxMessageWidth: root.mediaOsd ? Style.space(325) : Style.space(190)

  // Nerd Font glyphs draw well outside their monospace cell, so the icon
  // column is measured by ink rather than by advance width. Progress OSDs pin
  // it to the widest glyph the model can return, so the bar doesn't shift when
  // volume crosses an icon threshold.
  readonly property int iconInkWidth: Math.ceil(iconMetrics.tightBoundingRect.width)
  readonly property int iconWidth: root.hasProgress
    ? Math.max(root.iconInkWidth, Math.ceil(widestIconMetrics.tightBoundingRect.width))
    : root.iconInkWidth
  // Same idea for the readout: it is as wide as the longest percentage so the
  // digits don't jitter between 9% and 100%.
  readonly property int valueWidth: Math.ceil(Math.max(valueMetrics.advanceWidth, messageMetrics.advanceWidth))
  readonly property int messageWidth: Math.min(Math.ceil(messageMetrics.advanceWidth), root.maxMessageWidth)
  readonly property int contentWidth: root.hasProgress
    ? root.iconWidth + root.gap + root.barWidth + root.gap + root.valueWidth
    : (root.message === "" ? root.iconWidth : root.iconWidth + root.messageGap + root.messageWidth)

  readonly property int cardWidth: Math.max(1,
    cardSurface.borderLeft + root.pad + root.contentWidth + root.pad + cardSurface.borderRight)
  readonly property int cardHeight: Math.max(1,
    cardSurface.borderTop + root.pad + Style.font.displayLarge + root.pad + cardSurface.borderBottom)

  readonly property var _screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  readonly property real _screenW: _screen ? _screen.width : 0
  readonly property real _screenH: _screen ? _screen.height : 0
  readonly property int bottomMargin: Style.space(67)

  function iconFor(name, percent) {
    return OsdModel.iconFor(name, percent)
  }

  function show(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration) {
    var next = OsdModel.stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration, Commons.I18n.formatNumber)
    // Update before opening so a fresh OSD starts at its new value; only
    // subsequent updates while it remains open animate the progress bar.
    iconKey = next.iconKey
    maxValue = next.maxValue
    hasProgress = next.hasProgress
    value = next.value
    message = next.message
    icon = next.icon
    duration = next.duration
    opened = true
    // grabFocus:false ToolTip windows can lose a declarative visible binding
    // if something else writes visible; re-arm on every show (same as PopupCard).
    card.visible = Qt.binding(function() { return root.opened })
    if (duration > 0) hideTimer.restart()
    else hideTimer.stop()
  }

  function open(payloadJson) {
    try {
      var p = JSON.parse(payloadJson || "{}")
      show(p.icon || "", p.message || "", p.value === undefined ? "" : String(p.value), p.max === undefined ? "100" : String(p.max), p.progressText || "", p.duration === undefined ? "1200" : String(p.duration))
    } catch (e) {}
  }

  function close() { opened = false }

  Timer {
    id: hideTimer
    interval: root.duration
    onTriggered: root.opened = false
  }

  TextMetrics {
    id: messageMetrics
    font.family: Style.font.family
    font.bold: true
    font.pixelSize: Style.font.title
    text: root.message
  }

  TextMetrics {
    id: valueMetrics
    font: messageMetrics.font
    text: Commons.I18n.formatNumber(100) + "%"
  }

  TextMetrics {
    id: iconMetrics
    font.family: root.iconFontFamily
    font.pixelSize: Style.font.displayLarge
    text: root.icon
  }

  TextMetrics {
    id: widestIconMetrics
    font: iconMetrics.font
    text: OsdModel.widestIcon
  }

  ShellIpc {
    target: "osd"
    function show(payloadJson: string): string {
      root.open(payloadJson)
      return "ok"
    }
    function close(): string { root.close(); return "ok" }
    function state(): string { return root.opened ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  // 1px full-width strip: anchor space for the popup, never a full-screen
  // surface (picom glx unredirects those and paints clients black).
  PanelWindow {
    id: host
    visible: root.opened || card.visible
    screen: root._screen
    anchors { top: true; left: true; right: true }
    implicitHeight: 1
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
  }

  PopupWindow {
    id: card
    visible: root.opened
    color: "transparent"
    // See Ui/PopupCard.qml: opaque surfaces square off rounded OSD cards.
    surfaceFormat.opaque: false
    implicitWidth: root.cardWidth
    implicitHeight: root.cardHeight
    // Static false: PopupWindow latches grabFocus at create time. ToolTip is
    // correct here; the OSD must not grab pointer/keyboard from the focused app.
    grabFocus: false

    anchor {
      window: host
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      adjustment: PopupAdjustment.Slide
      rect.width: 1
      rect.height: 1
      rect.x: Math.round(Math.max(0, (root._screenW - card.implicitWidth) / 2))
      rect.y: Math.round(Math.max(0, root._screenH - card.implicitHeight - root.bottomMargin))
    }

    BorderSurface {
      id: cardSurface
      anchors.fill: parent
      color: Util.alpha(Commons.Color.background, 0.97)
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      opacity: root.opened ? 1 : 0

      Row {
        anchors.fill: parent
        anchors.topMargin: cardSurface.borderTop + root.pad
        anchors.rightMargin: cardSurface.borderRight + root.pad
        anchors.bottomMargin: cardSurface.borderBottom + root.pad
        anchors.leftMargin: cardSurface.borderLeft + root.pad
        spacing: root.hasProgress ? root.gap : root.messageGap
        Item {
          width: root.iconWidth
          height: parent.height
          Text {
            textFormat: Text.PlainText
            // Sit the glyph's ink flush in the column, centered when the
            // column is wider than this particular glyph.
            x: Math.round((root.iconWidth - root.iconInkWidth) / 2 - iconMetrics.tightBoundingRect.x)
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font: iconMetrics.font
            color: Commons.Color.popups.text
          }
        }
        Rectangle {
          visible: root.hasProgress
          width: root.barWidth
          height: Math.max(Style.space(6), Style.spacing.sm)
          anchors.verticalCenter: parent.verticalCenter
          color: Util.alpha(Commons.Color.popups.text, 0.45)
          Rectangle {
            // Anchored so a right-to-left layout fills from the right.
            anchors.left: parent.left
            height: parent.height
            width: parent.width * (root.hasProgress ? root.value / root.maxValue : 0)
            color: Commons.Color.accent

            Behavior on width {
              enabled: root.opened
              NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
            }
          }
        }
        Text {
          textFormat: Text.PlainText
          visible: root.message !== ""
          width: root.hasProgress ? root.valueWidth : root.messageWidth
          // The readout hugs the card edge so a short percentage doesn't leave
          // a hole in the padding; the slack lands in the gap after the bar.
          horizontalAlignment: root.hasProgress ? Text.AlignRight : Text.AlignLeft
          anchors.verticalCenter: parent.verticalCenter
          text: root.message
          font: messageMetrics.font
          color: Commons.Color.popups.text
          elide: Text.ElideRight
          maximumLineCount: 1
        }
      }
    }
  }
}

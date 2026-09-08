import QtQuick
import qs.Commons
import qs.Ui
import "ui"

// Bar item for Swiss Weather.
//
// The widget itself is deliberately thin: it owns the button in the bar slot
// and forwards the shell's open/close/toggle contract to the panel, which owns
// all the state and all the network work. That split is what the bar host
// expects — Bar.findPanelWidget looks for open/close/opened on the *widget*,
// not on the nested panel — and it keeps the panel free to be reloaded on its
// own during development without the bar losing its slot.
//
// Unconfigured, the button shows just the weather symbol for the detected
// region, which is the whole of the plugin's resting state.
BarWidget {
  id: root
  moduleName: "jmaeder.swissweather"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function cycleLocation() {
    if (panelLoader.item && panelLoader.item.cycleFavourite) panelLoader.item.cycleFavourite()
  }

  // --- shell open/close/toggle routing ------------------------------------

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.openFromHotkey) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // --- layout --------------------------------------------------------------

  readonly property string symbol: panelLoader.item ? panelLoader.item.barSymbol : ""
  readonly property string label: panelLoader.item ? panelLoader.item.barLabel : ""

  readonly property bool showSwissCross: setting("swissCross", true) !== false

  // Hide the slot entirely until there is something to say, rather than
  // parking a placeholder glyph in the bar for the seconds before the first
  // response lands.
  visible: symbol !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      // The bar can still be assigning its own properties when onLoaded runs;
      // a deferred second pass makes the injection independent of that order.
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The glyph and the temperature are both drawn by the composite below, so
    // the button's own label stays empty. `text` is still set because
    // WidgetButton derives hasVisualContent from it.
    text: root.symbol
    labelVisible: false

    // A bar icon button is a fixed square slot. Showing the temperature needs
    // more width than that, so the slot is widened by exactly the measured
    // width of the label — without this the text was drawn centred in a 21 px
    // slot and spilled over the widgets on either side.
    slotSize: Style.bar.statusSlot + (root.label !== ""
      ? Math.ceil(labelMetrics.width) + Style.space(5) : 0)


    // Composite icon: the weather glyph with the Swiss cross laid over it.
    //
    // iconComponent renders inside BarIconButton's optical canvas — a square
    // of Style.bar.iconCanvas centred in the slot — which is what keeps this
    // from touching bar geometry. Anchoring the mark to the button instead
    // put it at the bottom of the full slot height, several pixels below the
    // canvas the glyph is drawn in, where it hugged the bar's lower edge and
    // read as if it were stretching the bar.
    //
    // The glyph still comes from the Nerd Font rather than being redrawn.
    // Hand-drawing all 42 MeteoSwiss symbols would lose the hinting that makes
    // them legible at 16 px and would drift from the rest of the bar's icons
    // whenever a theme changes the font.
    iconComponent: root.symbol !== "" ? compositeIcon : null
    // No tooltip: the panel is the detail view, and a tooltip that duplicates
    // it just gets in the way of the click that opens it.
    tooltipText: ""

    onPressed: function(pressedButton) {
      if (pressedButton === Qt.MiddleButton) root.refresh()
      else if (pressedButton === Qt.RightButton) root.cycleLocation()
      else root.togglePanel()
    }

  }

  // The weather glyph, with the Swiss cross in its bottom-right corner. It
  // marks the widget as the Swiss one, and it does real work for anyone
  // running this beside the built-in weather widget: two cloud glyphs side by
  // side are indistinguishable. Turn it off with `"swissCross": false`.
  // How far the glyph slides left when a temperature is shown; the mark
  // follows it so the pair stays together.
  readonly property real labelShift: root.label !== ""
    ? (labelMetrics.width + Style.space(3)) / 2 : 0

  TextMetrics {
    id: labelMetrics
    font.family: button.fontFamily
    font.pixelSize: button.fontSize
    text: root.label
  }

  Component {
    id: compositeIcon

    Item {
      id: composite

      // How far the icon moves left to make room for the temperature, so the
      // glyph and the label together end up centred in the widened slot.
      readonly property real labelShift: root.label !== ""
        ? (labelMetrics.width + Style.space(3)) / 2 : 0

      Item {
        id: iconBox
        width: parent.width
        height: parent.height
        x: -composite.labelShift

        // The glyph keeps the optical centring the button would have applied
        // to it, so turning the badge on does not shift the symbol.
        OpticalGlyph {
          anchors.fill: parent
          text: root.symbol
          fontFamily: button.fontFamily
          fontSize: button.fontSize
          color: button.foreground
        }

        // Laid over the glyph's own bottom-right corner, inside the optical
        // canvas. Living inside the canvas is what makes it impossible for the
        // mark to affect the bar: the canvas is a fixed square centred in a
        // slot whose size the bar already decided. Hanging it below the canvas
        // instead — in the button's lower strip — left it detached from the
        // icon and reading as if it were stretching the bar downwards.
        //
        // A bit over half the canvas, with hairline arms, so it annotates the
        // corner rather than covering the symbol.
        SwissCross {
          visible: root.showSwissCross
          fine: true
          width: Math.max(Style.space(7), Math.round(parent.width * 0.55))
          height: width
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          crossColor: root.bar ? root.bar.barForeground : Color.foreground
          haloColor: root.bar ? root.bar.background : Color.background
        }
      }

      Text {
        visible: root.label !== ""
        anchors.left: iconBox.right
        anchors.leftMargin: Style.space(3)
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
      }
    }
  }
}

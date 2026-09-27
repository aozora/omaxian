import Quickshell
import QtQuick
import qs.Commons
import qs.Ui
import "CalcModel.js" as CalcModel

// Omaxian (X11/i3): upstream used a full-screen layer-shell scrim overlay
// (picom blacks that out). The card lives in Ui/CenteredModal — same pattern
// as ReminderFlow / wifiqr / keepass-picker. Enter copies via xclip (X11).

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  readonly property string result: CalcModel.evaluate(root.filterText) || ""
  property string fontFamily: Style.font.menuFamily

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Style.space(420)
  property int cardHeight: contentMargin * 2 + headerHeight

  // Anchor the card to the live bar PanelWindow so opening does not map a
  // second DOCK surface (i3 restack flash of bar + dock).
  readonly property var modalAnchorWindow: {
    var bar = root.shell && root.shell.bar
    if (!bar || typeof bar.panelWindowForScreen !== "function") return null
    return bar.panelWindowForScreen(Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
  }

  function open(payloadJson) {
    root.opened = true
    root.setText("", 0)
    Qt.callLater(function() {
      if (root.opened)
        input.forceActiveFocus()
    })
  }

  function setText(value, cursor) {
    root.filterText = value
    input.text = value
    input.cursorPosition = cursor
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.canclini.calculator")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function copyResult(value) {
    // Same X11 clipboard path as the network panel (xclip, else xsel).
    Quickshell.execDetached([
      "bash", "-c",
      'printf %s "$1" | { xclip -selection clipboard 2>/dev/null || xsel -b; }',
      "clip", value
    ])
  }

  function submit() {
    if (!root.filterText.trim()) {
      Qt.callLater(function() { root.dismiss() })
      return
    }
    if (!root.result) return
    root.copyResult(root.result)
    // Defer so CenteredModal can leave its Keys handler before unmap.
    Qt.callLater(function() { root.dismiss() })
  }

  CenteredModal {
    id: modal
    open: root.opened
    anchorWindow: root.modalAnchorWindow
    focusTarget: input
    contentWidth: root.cardWidth
    contentHeight: root.cardHeight
    padding: root.contentMargin
    background: root.background
    borderSpec: root.borderSpec
    onDismissed: root.dismiss()

    Item {
      anchors.fill: parent
      clip: true

      Row {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(8)

        Item {
          anchors.verticalCenter: parent.verticalCenter
          width: root.filterText ? input.implicitWidth : placeholder.implicitWidth
          height: input.implicitHeight

          Text {
            id: placeholder
            visible: !root.filterText
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Calculate..."
            color: root.foreground
            opacity: 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
          }

          TextInput {
            id: input
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText
            onTextEdited: {
              var pretty = CalcModel.prettify(text, cursorPosition)
              if (pretty.text !== text) {
                text = pretty.text
                cursorPosition = pretty.cursor
              }
              root.filterText = text
            }
            color: root.foreground
            selectionColor: Qt.rgba(Color.menu.selectedText.r, Color.menu.selectedText.g, Color.menu.selectedText.b, 0.35)
            selectedTextColor: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            selectByMouse: true
            focus: true

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (root.filterText) root.setText("", 0)
                else Qt.callLater(function() { root.dismiss() })
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.submit()
                event.accepted = true
              } else if ((event.text === "(" || event.text === ")") && input.selectedText.length > 0) {
                // Wrap the selection in parentheses instead of replacing it.
                var from = input.selectionStart
                var to = input.selectionEnd
                var wrapped = root.filterText.slice(0, from) + "(" + input.selectedText + ")" + root.filterText.slice(to)
                root.setText(wrapped, to + 2)
                event.accepted = true
              } else if ((event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete)
                         && !(event.modifiers & Qt.ControlModifier) && input.selectedText.length === 0) {
                // Deleting a parenthesis also deletes its partner.
                var index = event.key === Qt.Key_Backspace ? input.cursorPosition - 1 : input.cursorPosition
                var pair = index >= 0 ? CalcModel.deleteParenPair(root.filterText, index) : null
                if (pair) {
                  root.setText(pair.text, pair.cursor)
                  event.accepted = true
                }
              }
            }
          }
        }

        Rectangle {
          visible: root.result.length > 0
          anchors.verticalCenter: parent.verticalCenter
          width: resultText.implicitWidth + Style.space(8) * 2
          height: resultText.implicitHeight + Style.space(3) * 2
          radius: Math.max(2, root.cornerRadius / 2)
          color: Color.menu.selectedBackground
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
          border.width: 1

          Text {
            id: resultText
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "= " + root.result
            color: Color.menu.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }
  }
}

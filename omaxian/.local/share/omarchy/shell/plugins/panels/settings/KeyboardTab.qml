import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property color foreground: Color.popups.text

  readonly property string fontFamily: Style.font.family
  readonly property string keyboardPath: Quickshell.env("HOME") + "/.config/omarchy/keyboard.json"

  property var layouts: []
  property string toggle: "grp:alt_shift_toggle"
  property string statusMessage: ""
  property string keyboardReadBuf: ""

  function reloadKeyboardFile() {
    if (keyboardReadProc.running) {
      keyboardReadProc.signal(15)
      keyboardReadKill.start()
    }
    root.keyboardReadBuf = ""
    keyboardReadProc.command = [
      "/usr/bin/python3", "-I", "-S",
      Quickshell.shellDir + "/scripts/safe-read.py",
      "8192", root.keyboardPath
    ]
    keyboardReadProc.running = true
  }

  FileView {
    id: keyboardFile
    path: root.keyboardPath
    preload: false
    blockAllReads: true
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  Process {
    id: keyboardReadProc
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        root.keyboardReadBuf += String(chunk || "")
        if (root.keyboardReadBuf.length > 8192) {
          keyboardReadProc.signal(15)
          keyboardReadKill.start()
          root.keyboardReadBuf = ""
        }
      }
    }
    onExited: function(exitCode) {
      var raw = root.keyboardReadBuf
      root.keyboardReadBuf = ""
      var parsed = Model.parseKeyboard(exitCode === 0 ? raw : "")
      root.layouts = parsed.layouts
      root.toggle = parsed.toggle
    }
  }

  Timer {
    id: keyboardReadKill
    interval: 2000
    repeat: false
    onTriggered: keyboardReadProc.signal(9)
  }

  Process {
    id: applyProc
    command: ["omarchy-keyboard-apply"]
    onExited: function(exitCode) {
      root.statusMessage = exitCode === 0
        ? "Applied. The bar label updates when you switch layout."
        : "Apply failed (is setxkbmap installed?)."
    }
  }

  Component.onCompleted: root.reloadKeyboardFile()

  function persist(nextLayouts, nextToggle) {
    var layouts = nextLayouts !== undefined ? nextLayouts : root.layouts
    var toggle = nextToggle !== undefined ? nextToggle : root.toggle
    var payload = Model.serializeKeyboard({ layouts: layouts, toggle: toggle })
    var parsed = Model.parseKeyboard(payload)
    root.layouts = parsed.layouts
    root.toggle = parsed.toggle
    keyboardFile.setText(payload)
    root.statusMessage = "Saved to keyboard.json"
  }

  function addLayout() {
    var next = root.layouts.slice()
    if (next.length >= 8) {
      root.statusMessage = "At most 8 layouts."
      return
    }
    next.push({ layout: "us", variant: "" })
    root.persist(next, root.toggle)
  }

  function updateRow(index, key, value) {
    var next = root.layouts.slice()
    if (index < 0 || index >= next.length) return
    var row = {
      layout: next[index].layout,
      variant: next[index].variant
    }
    row[key] = value
    next[index] = row
    root.persist(next, root.toggle)
  }

  function removeRow(index) {
    var next = root.layouts.slice()
    if (index < 0 || index >= next.length) return
    if (next.length <= 1) {
      root.statusMessage = "Keep at least one layout."
      return
    }
    next.splice(index, 1)
    root.persist(next, root.toggle)
  }

  function moveRow(index, delta) {
    var next = root.layouts.slice()
    var dest = index + delta
    if (index < 0 || dest < 0 || dest >= next.length) return
    var item = next.splice(index, 1)[0]
    next.splice(dest, 0, item)
    root.persist(next, root.toggle)
  }

  function applyNow() {
    root.persist(root.layouts, root.toggle)
    if (applyProc.running) return
    root.statusMessage = "Applying…"
    applyProc.running = true
  }

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: col.implicitHeight
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: col
      width: flick.width
      spacing: Style.space(12)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: "XKB layouts for this session. Saved to ~/.config/omarchy/keyboard.json and applied at login. Use Apply now to switch without logging out. Layout ids are XKB names (us, it, ru, de, …); variant is optional (phonetic, nodeadkeys, …)."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Dropdown {
        width: parent.width
        label: "Toggle shortcut"
        value: root.toggle
        options: Model.keyboardToggleOptions()
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(v) { root.persist(root.layouts, v) }
      }

      Text {
        textFormat: Text.PlainText
        text: "Prefer Alt+Shift so Super+Space stays free for the Omarchy menu."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.layouts

        delegate: Item {
          required property var modelData
          required property int index
          width: col.width
          height: row.implicitHeight

          Row {
            id: row
            width: parent.width
            spacing: Style.space(6)

            Column {
              width: parent.width - actions.width - Style.space(6)
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                text: "Layout " + (index + 1)
                color: Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  width: Math.floor((parent.width - parent.spacing) / 2)
                  text: String(modelData.layout || "")
                  foreground: root.foreground
                  placeholderText: "layout (e.g. it)"
                  onEditingFinished: root.updateRow(index, "layout", text)
                }

                TextField {
                  width: Math.floor((parent.width - parent.spacing) / 2)
                  text: String(modelData.variant || "")
                  foreground: root.foreground
                  placeholderText: "variant (optional)"
                  onEditingFinished: root.updateRow(index, "variant", text)
                }
              }
            }

            Row {
              id: actions
              anchors.bottom: parent.bottom
              spacing: Style.space(4)

              Button {
                text: "▲"
                tooltipText: "Move up"
                bordered: true
                enabled: index > 0
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(4)
                onClicked: root.moveRow(index, -1)
              }

              Button {
                text: "▼"
                tooltipText: "Move down"
                bordered: true
                enabled: index < root.layouts.length - 1
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(4)
                onClicked: root.moveRow(index, 1)
              }

              Button {
                text: "×"
                tooltipText: "Remove"
                bordered: true
                enabled: root.layouts.length > 1
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(4)
                onClicked: root.removeRow(index)
              }
            }
          }
        }
      }

      Row {
        spacing: Style.space(8)

        Button {
          text: "Add layout"
          bordered: true
          enabled: root.layouts.length < 8
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.addLayout()
        }

        Button {
          text: "Apply now"
          bordered: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.applyNow()
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: root.statusMessage !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: Util.plain(root.statusMessage)
        color: Qt.darker(root.foreground, 1.3)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}

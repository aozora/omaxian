import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Ui

// Keybindings cheatsheet. Rows come from scripts/help-bindings.py, which
// prefers `i3-msg -t get_config` (live loaded config) over on-disk files so
// the sheet matches what i3 is actually running — not a stale Archcraft map.
BarWidget {
  id: root
  moduleName: "omaxian.help"

  property bool menuOpen: false
  property var rows: []
  property var filteredRows: []
  property string filterText: ""

  function refresh() { proc.running = true }

  function rowMatches(row, query) {
    if (!row || !query) return false
    var keys = String(row.keys || "").toLowerCase()
    var action = String(row.action || "").toLowerCase()
    var text = String(row.text || "").toLowerCase()
    return keys.indexOf(query) >= 0 || action.indexOf(query) >= 0 || text.indexOf(query) >= 0
  }

  function recomputeFiltered() {
    var source = root.rows || []
    var query = String(root.filterText || "").trim().toLowerCase()
    if (!query) {
      root.filteredRows = source
      return
    }

    var out = []
    var pendingHeader = null
    var headerEmitted = false
    for (var i = 0; i < source.length; i++) {
      var row = source[i]
      if (!row) continue
      if (row.type === "header") {
        pendingHeader = row
        headerEmitted = false
        continue
      }
      var headerMatch = pendingHeader && root.rowMatches(pendingHeader, query)
      if (headerMatch || root.rowMatches(row, query)) {
        if (pendingHeader && !headerEmitted) {
          out.push(pendingHeader)
          headerEmitted = true
        }
        out.push(row)
      }
    }
    root.filteredRows = out
  }

  onRowsChanged: root.recomputeFiltered()
  onFilterTextChanged: root.recomputeFiltered()

  IpcHandler {
    target: "help"
    function toggle(): void { root.menuOpen = !root.menuOpen }
    function hide(): void { root.menuOpen = false }
  }

  Process {
    id: proc
    property string stdoutBuf: ""
    property int maxStdout: 262144
    property bool overflowed: false
    command: ["python3", Quickshell.shellDir + "/scripts/help-bindings.py"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: function(chunk) {
        if (proc.overflowed) return
        proc.stdoutBuf += chunk
        if (proc.stdoutBuf.length > proc.maxStdout) {
          proc.overflowed = true
          proc.stdoutBuf = ""
          proc.signal(15)
          helpKillTimer.start()
        }
      }
    }
    onStarted: {
      helpKillTimer.stop()
      stdoutBuf = ""
      overflowed = false
    }
    onExited: function() {
      helpKillTimer.stop()
      var text = overflowed ? "" : String(stdoutBuf || "")
      stdoutBuf = ""
      overflowed = false
      try {
        root.rows = JSON.parse(text)
      } catch (e) {
        root.rows = []
      }
    }
  }

  Timer {
    id: helpKillTimer
    interval: 2000
    onTriggered: proc.signal(9)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body + 3
    text: "󰘥"
    foreground: Color.bar.text
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: root.menuOpen = !root.menuOpen
  }

  // Must live outside PopupCard: its default property aliases to contentItem
  // (QQuickItem children only). A Timer there fails the whole widget load.
  Timer {
    id: focusSearch
    interval: 80
    onTriggered: {
      if (root.menuOpen) searchField.forceActiveFocus()
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: helpOwner
    open: root.menuOpen
    contentWidth: Style.space(520)
    contentHeight: Style.space(480)

    onOpenChanged: {
      if (open) {
        root.filterText = ""
        searchField.text = ""
        root.refresh()
        focusSearch.restart()
      } else {
        root.filterText = ""
        searchField.text = ""
      }
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.spacing.sm

      Text {
        textFormat: Text.PlainText
        text: "Keybindings"
        color: BarPalette.popupHeaderAccent
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }

      TextField {
        id: searchField
        Layout.fillWidth: true
        placeholderText: "Search keybindings…"
        font.pixelSize: Style.font.caption
        verticalPadding: Style.spacing.xs
        onTextChanged: root.filterText = text
        Keys.onEscapePressed: function(event) {
          if (text.length > 0) {
            text = ""
            event.accepted = true
          } else {
            root.menuOpen = false
            event.accepted = true
          }
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          visible: helpList.count === 0
          text: root.filterText.trim() ? ("No matches for “" + root.filterText.trim() + "”") : "No keybindings"
          color: BarPalette.popupSubtext
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        ListView {
          id: helpList
          anchors.fill: parent
          clip: true
          visible: count > 0
          model: root.filteredRows
          delegate: Item {
            required property var modelData
            width: ListView.view.width
            height: modelData.type === "header" ? Style.space(26) : Style.space(24)

            Text {
              textFormat: Text.PlainText
              visible: parent.modelData.type === "header"
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: parent.modelData.text
              color: BarPalette.popupHeaderAccent
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            RowLayout {
              visible: parent.modelData.type === "bind"
              anchors.fill: parent
              anchors.leftMargin: Style.spacing.sm

              Text {
                textFormat: Text.PlainText
                Layout.preferredWidth: Style.space(220)
                text: parent.parent.modelData.keys
                color: BarPalette.popupHelpKeys
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: parent.parent.modelData.action
                color: BarPalette.popupSubtext
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
          }
        }
      }
    }
  }

  QtObject {
    id: helpOwner
    function close() { root.menuOpen = false }
  }
}

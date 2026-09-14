import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services
import qs.Ui

// Menu button: left-click / `launcher toggle` opens the Omarchy command
// palette (`omarchy.menu` — apps + commands). Right-click / `runner toggle`
// is the command runner. Glyph defaults to U+F011B (Archcraft cat); override
// via shell.json layout settings `icon` / `iconFont`.
// IPC for launcher/runner is owned by shell.qml (see callBarModule).
BarWidget {
  id: root
  moduleName: "omaxian.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string iconGlyph: {
    var _ = settings
    var v = String(setting("icon", "\u{f011b}"))
    return v.length > 0 ? v : "\u{f011b}"
  }
  readonly property string iconFontFamily: {
    var _ = settings
    return String(setting("iconFont", ""))
  }

  property bool runnerOpen: false

  function closeRunner() { root.runnerOpen = false }

  function togglePalette() {
    root.runnerOpen = false
    if (root.bar && root.bar.shell && typeof root.bar.shell.toggle === "function")
      root.bar.shell.toggle("omarchy.menu", '{"menu":"root"}')
  }

  function hidePalette() {
    if (root.bar && root.bar.shell && typeof root.bar.shell.hide === "function")
      root.bar.shell.hide("omarchy.menu")
  }

  // `launcher` IPC lives on shell.qml (singleton). Per-monitor IpcHandlers
  // here raced: after a plugin reload the dead instance kept the target and
  // Super+Space / `$qs launcher` stopped opening the menu while the bar
  // button still worked.
  //
  // Runner popup state is still per MenuButton; shell.qml's `runner` target
  // fans out via these methods so every screen stays in sync.
  function ipcToggleRunner() {
    root.hidePalette()
    root.runnerOpen = !root.runnerOpen
  }
  function ipcHideRunner() { root.runnerOpen = false }

  property QtObject runnerOwner: QtObject { function close() { root.runnerOpen = false } }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconGlyph
    fontFamily: root.iconFontFamily.length > 0
      ? root.iconFontFamily
      : (root.bar ? root.bar.fontFamily : Style.font.family)
    foreground: BarPalette.menuLogo
    fontSize: Style.font.display + 2
    horizontalMargin: 10
    verticalPadding: 4
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) {
        root.togglePalette()
      } else if (mouseButton === Qt.RightButton) {
        root.hidePalette()
        root.runnerOpen = !root.runnerOpen
      }
    }
  }

  PopupCard {
    id: runnerPopup
    anchorItem: button
    bar: root.bar
    owner: root.runnerOwner
    open: root.runnerOpen
    contentWidth: Style.space(420)
    contentHeight: Style.space(120)

    onOpenChanged: {
      if (open) {
        runField.text = ""
        focusDelay.restart()
      }
    }

    property Timer focusDelay: Timer {
      interval: 60
      onTriggered: {
        Quickshell.execDetached(["python3", Quickshell.shellDir + "/scripts/focus-window.py"])
        runField.forceActiveFocus()
      }
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.spacing.md

      Text {
        textFormat: Text.PlainText
        text: "Run"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
      }

      TextField {
        id: runField
        Layout.fillWidth: true
        placeholderText: "Command…"
        Keys.onReturnPressed: {
          if (text.length > 0) Quickshell.execDetached(["bash", Quickshell.shellDir + "/scripts/run.sh", text])
          root.closeRunner()
        }
        Keys.onEscapePressed: root.closeRunner()
      }
    }
  }
}

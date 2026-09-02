import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var pluginRegistry: null
  property var barWidgetRegistry: null
  property color foreground: Color.popups.text

  readonly property string fontFamily: Style.font.family
  readonly property string home: Quickshell.env("HOME")
  readonly property var idle: {
    var cfg = shell && shell.shellConfig ? shell.shellConfig : {}
    return (cfg && cfg.idle) ? cfg.idle : {}
  }

  function openFile(path) {
    Quickshell.execDetached(["omarchy-launch-config-editor", path])
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
      spacing: Style.space(10)

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "These open in your editor. There is no form UI for i3 / picom / dunst yet."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Button {
        text: "i3 keybindings"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openFile(root.home + "/.config/i3/config.d/02_keybindings.conf")
      }

      Button {
        text: "i3 theme / gaps"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openFile(root.home + "/.config/i3/config.d/01_theme.conf")
      }

      Button {
        text: "picom compositor"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openFile(root.home + "/.config/i3/picom.conf")
      }

      Button {
        text: "dunst notifications"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openFile(root.home + "/.config/dunst/dunstrc")
      }

      Button {
        text: "Menu extensions"
        bordered: true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.openFile(root.home + "/.config/omarchy/extensions/omarchy-menu.jsonc")
      }

      PanelSectionHeader {
        text: "Session notes"
        foreground: root.foreground
        fontFamily: root.fontFamily
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Keyboard layout is set in ~/.config/i3/scripts/i3_autostart (setxkbmap) — not a live setting."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Idle screensaver / lock in shell.json ("
              + String(idle.screensaver !== undefined ? idle.screensaver : 150)
              + "s / "
              + String(idle.lock !== undefined ? idle.lock : 300)
              + "s) is not enforced on X11."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}

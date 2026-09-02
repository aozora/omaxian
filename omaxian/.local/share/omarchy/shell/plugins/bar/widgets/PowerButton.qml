import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Ui

// Port of eww's sysmenu-btn + powermenu + confirm widgets
// (modules/menus.yuck). eww coordinates the confirm step across two
// separate top-level windows via the `eww` CLI + a scratch file
// (`confirm-ask.sh` writes the pending action, `confirm-run.sh` reads and
// clears it) because eww windows are independent processes with no shared
// state. This popup doesn't need any of that: the pending action is just a
// QML property inside one PopupCard, and `Ui/ConfirmDialog` (already
// ported, no Wayland dependency) overlays the same window instead of
// swapping to a second one. `scripts/power.sh` (the part that actually
// runs `loginctl`/`i3-msg exit`/`i3lock`) is reused unchanged. Only `lock`
// skips confirmation, matching eww exactly — every other action asks
// first, even suspend/hibernate.
BarWidget {
  id: root
  moduleName: "omaxian.powermenu"

  property bool menuOpen: false
  property string pendingAction: ""
  property string headerText: ""

  function close() { root.menuOpen = false; root.pendingAction = "" }

  // i3 keybinding toggles this directly (`qs ipc call powermenu toggle`,
  // matching eww's $MOD+x binding).
  IpcHandler {
    target: "powermenu"
    function toggle(): void { root.menuOpen = !root.menuOpen }
    function hide(): void { root.close() }
  }

  function run(action) {
    Quickshell.execDetached(["bash", Quickshell.shellDir + "/scripts/power.sh", action])
    root.close()
  }

  function ask(action) { root.pendingAction = action }

  Timer {
    interval: 60000
    running: root.menuOpen
    repeat: true
    triggeredOnStart: true
    onTriggered: headerProc.running = true
  }

  Process {
    id: headerProc
    command: ["bash", Quickshell.shellDir + "/scripts/powermenu-header.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = text.replace(/\n$/, "")
        if (t.length > 0) root.headerText = t
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body + 4
    text: "󰐥"
    foreground: BarPalette.power
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: root.menuOpen = !root.menuOpen
  }

  PopupCard {
    id: popup
    anchorItem: button
    bar: root.bar
    owner: root
    open: root.menuOpen
    contentWidth: Style.space(460)
    contentHeight: Style.space(330)

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.space(14)

      // Hero row — omarchy panel vocabulary (glyph left, title + uppercase
      // status line). `headerText` (powermenu-header.sh, uptime) is the
      // status line, mirroring the battery panel's status text.
      PanelHero {
        Layout.fillWidth: true
        title: "Power"
        meta: root.headerText
        foreground: Color.foreground
        fontFamily: Style.font.family
        iconComponent: Component {
          Text {
            text: "󰐥"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.display
          }
        }
      }

      PanelSeparator { Layout.fillWidth: true; foreground: Color.foreground }

      // Session actions. Icon via `iconText` (not baked into the label),
      // upstream profile-button sizing. Reboot/Shutdown carry the urgent
      // colour; the rest are neutral.
      GridLayout {
        Layout.fillWidth: true
        columns: 3
        rowSpacing: Style.space(10)
        columnSpacing: Style.space(10)

        Button {
          Layout.fillWidth: true
          iconText: "󰌾"
          iconSize: Style.font.title
          text: "Lock"
          fontSize: Style.font.bodySmall
          foreground: Color.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          onClicked: root.run("lock")
        }
        Button {
          Layout.fillWidth: true
          iconText: "󰍃"
          iconSize: Style.font.title
          text: "Logout"
          fontSize: Style.font.bodySmall
          foreground: Color.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          onClicked: root.ask("logout")
        }
        Button {
          Layout.fillWidth: true
          iconText: "󰤄"
          iconSize: Style.font.title
          text: "Suspend"
          fontSize: Style.font.bodySmall
          foreground: Color.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          onClicked: root.ask("suspend")
        }
        Button {
          Layout.fillWidth: true
          iconText: "󰋊"
          iconSize: Style.font.title
          text: "Hibernate"
          fontSize: Style.font.bodySmall
          foreground: Color.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          onClicked: root.ask("hibernate")
        }
        Button {
          Layout.fillWidth: true
          iconText: "󰜉"
          iconSize: Style.font.title
          text: "Reboot"
          fontSize: Style.font.bodySmall
          foreground: Color.urgent
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          onClicked: root.ask("reboot")
        }
        Button {
          Layout.fillWidth: true
          iconText: "󰐥"
          iconSize: Style.font.title
          text: "Shutdown"
          fontSize: Style.font.bodySmall
          foreground: Color.urgent
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          onClicked: root.ask("shutdown")
        }
      }
    }

    ConfirmDialog {
      anchors.fill: parent
      opened: root.pendingAction.length > 0
      message: "Are you sure? Action: " + root.pendingAction
      onCanceled: root.pendingAction = ""
      onConfirmed: {
        var action = root.pendingAction
        root.pendingAction = ""
        root.run(action)
      }
    }
  }
}

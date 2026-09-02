import QtQuick
import QtQuick.Layouts
import Quickshell.I3
import qs.Commons
import qs.Services
import qs.Ui

// X11 delta (T3, deltas.md): `Quickshell.Hyprland` → `Quickshell.I3`.
// `I3Workspace` (number/urgent/active/focused/monitor/activate()) is a
// near-1:1 match for `HyprlandWorkspace`. i3's workspace list only holds
// workspaces that exist, so "occupied" = present in the list. No `.id`
// (match on `.number`); no `.toplevels`. Focus via `i3-msg workspace`.
//
// The pill styling (`BarPalette.workspace.*`) was ported over from eww's
// `.ws-btn` states but never wired into this widget — the upstream T3
// source it was structurally copied from just swaps the glyph and dims
// unoccupied workspaces, no color at all. Wired up here so the focused
// workspace is actually visible, not just a slightly different icon.
BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceByNumber(n) {
    var values = I3.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].number === n) return values[i]
    }
    return null
  }

  function workspaceNumbers() {
    // Always show the full 1–10 row; occupied/focused state just changes opacity.
    var nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    var values = I3.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var n = values[i].number
      if (n > 0 && n <= 10 && nums.indexOf(n) === -1) nums.push(n)
    }

    nums.sort(function(left, right) { return left - right })
    return nums
  }

  function focusWorkspace(n) {
    if (!root.bar) return
    // `unset I3SOCK`: i3's own `/proc/environ` keeps the socket path from
    // before an i3 restart (e.g. `ipc-socket.2164` while the live one is
    // `ipc-socket.12603`), and the whole shell process tree inherits that
    // stale value — `i3-msg` then can't connect. With it unset, `i3-msg`
    // falls back to the live `I3_SOCKET_PATH` X root-window property.
    root.bar.run("unset I3SOCK; exec i3-msg -q workspace number " + n)
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceNumbers().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceNumbers()

      Item {
        id: cell
        required property int modelData

        readonly property var workspace: root.workspaceByNumber(modelData)
        readonly property bool occupied: workspace !== null
        readonly property bool focused: I3.focusedWorkspace !== null && I3.focusedWorkspace.number === modelData
        // "active" = currently shown on some output (i3's sense of the word);
        // on a single-monitor setup this is always the same workspace as
        // "focused", so this branch only differs once a second output exists.
        readonly property bool active: workspace !== null && workspace.active === true
        readonly property bool urgent: workspace !== null && workspace.urgent === true

        readonly property color pillColor: focused
          ? BarPalette.workspace.activeBackground
          : urgent
            ? BarPalette.workspace.urgentBackground
            : active
              ? BarPalette.workspace.visibleBackground
              : "transparent"
        readonly property color textColor: focused
          ? BarPalette.workspace.activeText
          : urgent
            ? BarPalette.workspace.urgentText
            : active
              ? BarPalette.workspace.visibleText
              : BarPalette.workspace.normalText

        // GridLayout sizes children off `implicitWidth`/`implicitHeight` (no
        // `Layout.preferredWidth` set here), same as `WidgetButton` used to
        // provide via `fixedWidth`/`fixedHeight` before this became a plain
        // `Item` wrapping the pill background + the button.
        implicitWidth: root.vertical ? root.barSize : Style.space(20)
        implicitHeight: root.barSize

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: cell.pillColor
        }

        WidgetButton {
          anchors.fill: parent
          bar: root.bar
          text: cell.focused ? "󱓻" : (cell.modelData === 10 ? "0" : String(cell.modelData))
          foreground: cell.textColor
          opacity: cell.occupied || cell.focused || cell.active || cell.urgent ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          onPressed: function() { root.focusWorkspace(cell.modelData) }
        }
      }
    }
  }
}

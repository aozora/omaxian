import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Port of eww's notifications-module: a thin button that pops the last
// dunst notification (`dunstctl history-pop`, or the i3 `i3_notifications`
// script if present) — no bar state of its own, and deliberately not
// replaced by omarchy-quattro's full DBus notification daemon (see
// docs/quickshell/README.md's "Decided" section: keep dunst). Glyph copied
// exactly from modules/bar.yuck (U+F0F3).
BarWidget {
  id: root
  moduleName: "omaxian.notifications"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body + 1
    text: ""
    foreground: Color.bar.text
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: root.bar.run(Quickshell.shellDir + "/scripts/notifications.sh")
  }
}

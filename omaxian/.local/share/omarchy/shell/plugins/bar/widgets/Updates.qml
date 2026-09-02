import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import qs.Ui

// Adapted from omarchy-quattro's bar/widgets/SystemUpdate.qml pattern
// (external poller + click-to-install), but the backing check is Debian's
// `apt list --upgradable` (`scripts/updates.sh`, copied unchanged) instead
// of omarchy's Arch-specific update checker. Same 30-minute poll interval
// as eww's `defpoll`. Glyph copied exactly from modules/bar.yuck
// (U+F06B0); updates.sh itself has no icon of its own (verified via a byte
// dump — its output is just a leading space + count/"None", easy to
// mistake for a missing glyph when eyeballing terminal output).
BarWidget {
  id: root
  moduleName: "omaxian.updates"

  property string suffix: " None"

  Timer {
    interval: 30 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: proc.running = true
  }

  Process {
    id: proc
    command: ["bash", Quickshell.shellDir + "/scripts/updates.sh"]
    stdout: StdioCollector {
      onStreamFinished: {
        var t = text.replace(/\n$/, "")
        if (t.length > 0) root.suffix = t
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    fontSize: Style.font.body
    text: "󰚰" + root.suffix
    foreground: BarPalette.updates
    horizontalMargin: 8.5
    verticalPadding: 6
    onPressed: root.bar.run(Quickshell.shellDir + "/scripts/updates-install.sh")
  }
}

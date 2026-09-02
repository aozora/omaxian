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
  readonly property int revision: pluginRegistry ? pluginRegistry.registryRevision : 0
  readonly property bool dockEnabled: {
    var _ = root.revision
    return pluginRegistry ? pluginRegistry.isEnabled("omaxian.dock") : false
  }

  property var settings: Model.parseDockSettings("")

  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.config/omarchy/dock-settings.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.settings = Model.parseDockSettings(text())
    onFileChanged: reload()
    onLoadFailed: root.settings = Model.parseDockSettings("")
  }

  function persist(next) {
    var merged = {
      fullWidth: next.fullWidth !== undefined ? next.fullWidth : root.settings.fullWidth,
      roundedCorners: next.roundedCorners !== undefined ? next.roundedCorners : root.settings.roundedCorners,
      hoverAnimation: next.hoverAnimation !== undefined ? next.hoverAnimation : root.settings.hoverAnimation
    }
    root.settings = merged
    settingsFile.setText(Model.serializeDockSettings(merged))
  }

  function setDockEnabled(value) {
    if (!pluginRegistry) return
    pluginRegistry.setEnabled("omaxian.dock", value)
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

      Toggle {
        width: parent.width
        label: "Show dock"
        description: "Persistent bottom dock. Pinned apps are managed on the dock itself (right-click / drag)."
        checked: root.dockEnabled
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.setDockEnabled(!root.dockEnabled)
      }

      Toggle {
        width: parent.width
        label: "Full width"
        description: "Span the whole screen edge. Off: a centered pill sized to its icons. Changing this may need a shell restart."
        checked: root.settings.fullWidth === true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.persist({ fullWidth: !root.settings.fullWidth })
      }

      Toggle {
        width: parent.width
        label: "Rounded corners"
        description: "Round the pill when it is not full width."
        checked: root.settings.roundedCorners === true
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.persist({ roundedCorners: !root.settings.roundedCorners })
      }

      Toggle {
        width: parent.width
        label: "Hover magnification"
        description: "Scale up the hovered icon."
        checked: root.settings.hoverAnimation !== false
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.persist({ hoverAnimation: !root.settings.hoverAnimation })
      }
    }
  }
}

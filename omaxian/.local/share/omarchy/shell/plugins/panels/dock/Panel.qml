// Panel.qml — omaxian.dock
// This is a stripped down port of https://github.com/rosakodu/omarchy-dock
// -------------------------------------------------------------------------------

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import "Model.js" as Model

// Persistent bottom dock. One PanelWindow per screen.
// Appearance: theme `dock.toml` ← user `~/.config/omarchy/dock.toml`
// (legacy `dock-settings.json` still overlays if no user toml yet).
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property string home: Quickshell.env("HOME")
  readonly property string themeDockPath: home + "/.local/state/omarchy/current/theme/dock.toml"
  readonly property string userDockPath: home + "/.config/omarchy/dock.toml"
  readonly property string legacyJsonPath: home + "/.config/omarchy/dock-settings.json"

  property var themeSparse: ({})
  property var userSparse: ({})
  property var legacySparse: ({})

  readonly property var settings: Model.mergeSettings(
    root.themeSparse,
    Object.keys(root.userSparse).length ? root.userSparse : root.legacySparse
  )

  property var pinned: []
  property bool editMode: false

  // Resolved appearance (from merged settings).
  readonly property bool fullWidth: settings.fullWidth
  readonly property bool hoverAnimation: settings.hoverAnimation
  readonly property string background: settings.background
  readonly property real backgroundOpacity: settings.opacity
  readonly property int iconSize: settings.iconSize
  readonly property real hoverScale: settings.hoverScale
  readonly property int cornerRadius: settings.cornerRadius
  readonly property int islandGap: settings.islandGap
  readonly property string runningIndicator: settings.runningIndicator
  readonly property bool autoHide: settings.autoHide
  // Thickness around icons; scales with configured icon size.
  readonly property int dockSize: iconSize + Style.space(20)
  readonly property int reservedHeight: dockSize + islandGap * 2

  readonly property color pillFill: root.background !== ""
    ? Style.colorFromHex(root.background, Color.bar.background)
    : Color.bar.background

  property int dockHoverCount: 0
  readonly property bool dockHovered: dockHoverCount > 0
  property bool hideHold: false

  readonly property bool dockShown: !autoHide || editMode || dockHovered || hideHold

  function setDockHovered(on) {
    if (on) {
      dockHoverCount++
      hideHold = false
      hideTimer.stop()
    } else {
      dockHoverCount = Math.max(0, dockHoverCount - 1)
      if (autoHide && !editMode && dockHoverCount === 0) {
        hideHold = true
        hideTimer.restart()
      }
    }
  }

  Timer {
    id: hideTimer
    interval: 500
    onTriggered: root.hideHold = false
  }

  onEditModeChanged: {
    if (editMode) {
      hideHold = false
      hideTimer.stop()
    } else if (autoHide && !dockHovered) {
      hideHold = true
      hideTimer.restart()
    }
  }

  onAutoHideChanged: {
    if (!autoHide) {
      hideHold = false
      hideTimer.stop()
    }
  }

  readonly property var dockItems: Model.buildDockItems(
    root.pinned,
    I3Windows.windows,
    root.appLibrary ? root.appLibrary.sortedEntries("") : []
  )

  function persistPinned() {
    pinnedFile.setText(Model.serializePinned(root.pinned))
  }

  function togglePinned(appId) {
    root.pinned = Model.togglePinned(root.pinned, appId)
    root.persistPinned()
  }

  function launchOrFocus(item) {
    if (item.running && item.windows.length > 0) {
      var target = item.windows[0]
      for (var i = 0; i < item.windows.length; i++) {
        if (item.windows[i].focused) {
          target = item.windows[i]
          break
        }
      }
      I3Windows.focusWindow(target.conId)
      return
    }
    if (root.appLibrary && item.entry)
      root.appLibrary.launch(item.entry)
  }

  FileView {
    id: pinnedFile
    path: root.home + "/.config/omarchy/dock-pinned.json"
    printErrors: false
    onLoaded: root.pinned = Model.parsePinned(text())
    onLoadFailed: root.pinned = []
  }

  FileView {
    id: themeDockFile
    path: root.themeDockPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.themeSparse = Model.parseSettingsSparse(text())
    }
    onFileChanged: reload()
    onLoadFailed: root.themeSparse = ({})
  }

  FileView {
    id: userDockFile
    path: root.userDockPath
    watchChanges: true
    printErrors: false
    onLoaded: root.userSparse = Model.parseSettingsSparse(text())
    onFileChanged: reload()
    onLoadFailed: root.userSparse = ({})
  }

  FileView {
    id: legacyJsonFile
    path: root.legacyJsonPath
    watchChanges: true
    printErrors: false
    onLoaded: root.legacySparse = Model.parseSettingsSparse(text())
    onFileChanged: reload()
    onLoadFailed: root.legacySparse = ({})
  }

  Variants {
    model: Quickshell.screens
    delegate: Component {
      DockPanel {
        required property var modelData
        screen: modelData
      }
    }
  }

  component DockPanel: PanelWindow {
    id: dockWindow

    anchors {
      bottom: true
      left: true
      right: true
    }

    implicitHeight: root.reservedHeight
    // Autohide parks almost off-screen (2px peek for hover-reveal) and drops
    // the strut so tiled windows use the full height.
    exclusionMode: root.dockShown ? ExclusionMode.Auto : ExclusionMode.Ignore
    margins.bottom: root.dockShown ? 0 : -(root.reservedHeight - 2)
    color: "transparent"
    surfaceFormat.opaque: false
    mask: (!root.fullWidth || root.islandGap > 0) ? pillMask : null

    Behavior on margins.bottom {
      NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Region {
      id: pillMask
      item: pillBackground
    }

    HoverHandler {
      onHoveredChanged: root.setDockHovered(hovered)
      Component.onDestruction: if (hovered) root.setDockHovered(false)
    }

    Item {
      id: dockContent
      anchors.fill: parent
      anchors.margins: root.islandGap
      clip: root.islandGap > 0

      Rectangle {
        id: pillBackground
        color: root.pillFill
        opacity: root.backgroundOpacity
        radius: root.fullWidth ? 0 : root.cornerRadius
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        height: parent.height
        width: root.fullWidth
          ? parent.width
          : Math.max(root.dockSize, iconRow.width + Style.space(24))

        Behavior on width {
          enabled: !root.fullWidth
          NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
          NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        Behavior on color {
          ColorAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
      }

      MouseArea {
        anchors.fill: parent
        enabled: root.editMode
        onClicked: root.editMode = false
      }

      Item {
        id: iconRow
        readonly property int cellStep: root.iconSize + Style.space(10)
        anchors.centerIn: parent
        width: root.dockItems.length > 0 ? root.dockItems.length * cellStep - Style.space(10) : 0
        height: root.iconSize

        Repeater {
          model: root.dockItems

          delegate: Item {
            id: cell
            required property var modelData
            required property int index

            width: root.iconSize
            height: root.iconSize
            z: dragArea.dragging ? 10 : (dragArea.containsMouse ? 5 : 0)

            transformOrigin: Item.Bottom
            scale: (root.hoverAnimation && dragArea.containsMouse && !dragArea.dragging && !root.editMode)
              ? root.hoverScale : 1.0
            Behavior on scale {
              NumberAnimation { duration: 120; easing.type: Easing.OutBack }
            }

            Binding {
              target: cell
              property: "x"
              value: cell.index * iconRow.cellStep
              when: !dragArea.dragging
            }
            Behavior on x {
              enabled: !dragArea.dragging
              NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Rectangle {
              anchors.fill: parent
              anchors.margins: -Style.space(4)
              radius: Style.cornerRadius
              color: "transparent"
              visible: root.editMode && cell.modelData.pinned
              border.width: Math.max(1, Style.space(2))
              border.color: Color.accent
            }

            Image {
              anchors.fill: parent
              source: root.appLibrary
                ? root.appLibrary.iconSource(
                    cell.modelData.entry
                      ? cell.modelData.entry.icon
                      : String(cell.modelData.id || "")
                  )
                : ""
              fillMode: Image.PreserveAspectFit
              smooth: true
              mipmap: true
              asynchronous: true
              sourceSize.width: Math.ceil(
                root.iconSize * (root.hoverAnimation ? root.hoverScale : 1.0) * Screen.devicePixelRatio
              )
              sourceSize.height: Math.ceil(
                root.iconSize * (root.hoverAnimation ? root.hoverScale : 1.0) * Screen.devicePixelRatio
              )
              opacity: root.editMode && !cell.modelData.pinned ? 0.5 : 1
            }

            // Running indicator
            Rectangle {
              visible: cell.modelData.running && root.runningIndicator === "dot"
              width: Style.space(6)
              height: Style.space(6)
              radius: width / 2
              color: cell.modelData.urgent ? Color.urgent : Color.accent
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: -Style.space(6)
            }

            Rectangle {
              visible: cell.modelData.running && root.runningIndicator === "bar"
              width: Math.max(Style.space(10), Math.round(parent.width * 0.55))
              height: Style.space(2)
              radius: height / 2
              color: cell.modelData.urgent ? Color.urgent : Color.accent
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              anchors.bottomMargin: -Style.space(4)
            }

            MouseArea {
              id: dragArea
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              hoverEnabled: true

              property bool longPressFired: false
              property bool dragging: false
              property real grabOffsetX: 0

              onPressed: function (mouse) {
                longPressFired = false
                dragging = false
                if (mouse.button === Qt.LeftButton) {
                  if (!root.editMode)
                    longPressTimer.restart()
                  if (cell.modelData.pinned)
                    grabOffsetX = mapToItem(iconRow, mouse.x, mouse.y).x - cell.x
                }
              }

              onPositionChanged: function (mouse) {
                if (!root.editMode || !cell.modelData.pinned)
                  return
                if (!(mouse.buttons & Qt.LeftButton))
                  return
                dragging = true
                var posInRow = mapToItem(iconRow, mouse.x, mouse.y).x
                cell.x = Math.max(0, Math.min(iconRow.width - cell.width, posInRow - grabOffsetX))
              }

              onReleased: function (mouse) {
                var app = root
                longPressTimer.stop()

                if (dragging) {
                  var targetIndex = Math.max(
                    0,
                    Math.min(app.pinned.length - 1, Math.round(cell.x / iconRow.cellStep))
                  )
                  dragging = false
                  var curIndex = app.pinned.indexOf(cell.modelData.id)
                  var draggedId = cell.modelData.id
                  if (curIndex !== -1 && targetIndex !== curIndex) {
                    Qt.callLater(function () {
                      var arr = app.pinned.slice()
                      var i = arr.indexOf(draggedId)
                      if (i === -1) return
                      arr.splice(i, 1)
                      arr.splice(Math.min(targetIndex, arr.length), 0, draggedId)
                      app.pinned = arr
                      app.persistPinned()
                    })
                  }
                  return
                }

                if (longPressFired || app.editMode)
                  return
                if (mouse.button === Qt.RightButton)
                  app.togglePinned(cell.modelData.id)
                else
                  app.launchOrFocus(cell.modelData)
              }

              onCanceled: function () {
                longPressTimer.stop()
                dragging = false
              }

              Timer {
                id: longPressTimer
                interval: 450
                onTriggered: {
                  dragArea.longPressFired = true
                  root.editMode = true
                }
              }
            }
          }
        }
      }
    }
  }
}

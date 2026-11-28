import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "NotificationsModel.js" as Model

// Bar bell and history panel for dunst. dunst draws the pop-ups and keeps the
// history; the state comes from NotificationsService.qml.
// Left click: history. Right click: Do Not Disturb. Middle: show the last again.
Panel {
  id: root
  moduleName: "omaxian.notifications"
  ipcTarget: "omaxian.notifications"

  readonly property var service: bar && bar.shell && typeof bar.shell.firstPartyServiceFor === "function"
    ? bar.shell.firstPartyServiceFor("omaxian.notifications") : null
  readonly property bool available: !!service && service.available
  readonly property bool paused: !!service && service.paused
  readonly property int unseenCount: service ? service.unseenCount : 0
  readonly property var rows: service ? Model.grouped(service.entries) : []

  // What arrived since the panel was last open, kept marked while it is open.
  property var freshKeys: ({})
  property int selectedIndex: 0
  property bool cursorActive: false
  property double now: Date.now()

  readonly property color foreground: bar ? bar.foreground : Commons.Color.popups.text
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function clampSelection() {
    selectedIndex = Math.max(0, Math.min(selectedIndex, rows.length - 1))
  }

  function moveSelection(step) {
    if (!cursorActive) {
      cursorActive = true
    } else {
      selectedIndex += step
    }
    clampSelection()
  }

  function selected() {
    return cursorActive && selectedIndex < rows.length ? rows[selectedIndex] : null
  }

  // The pop-up would sit under the panel, so the panel closes first.
  function showAgain(row) {
    if (!row || !service) return
    close()
    service.showAgain(row.id)
  }

  function remove(row) {
    if (row && service) service.remove(row.id)
  }

  function noteNew() {
    if (!opened || !service) return
    var next = Model.unseenKeys(service.entries, service.seen)
    if (Object.keys(next).length === 0) return
    for (var key in freshKeys) next[key] = true
    freshKeys = next
    service.markSeen()
  }

  onOpenedChanged: {
    if (!opened) return
    freshKeys = ({})
    selectedIndex = 0
    cursorActive = false
    now = Date.now()
    if (service) service.refresh()
    noteNew()
  }

  onRowsChanged: {
    clampSelection()
    now = Date.now()
    Qt.callLater(noteNew)
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.now = Date.now()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.paused ? "󰂛" : ""
    tooltipText: root.paused ? "Notifications silenced"
      : (root.unseenCount > 0 ? root.unseenCount + " new notifications" : "Notifications")
    onPressed: function(b) {
      if (!root.service) return
      if (b === Qt.RightButton) root.service.toggleDnd()
      else if (b === Qt.MiddleButton) Quickshell.execDetached(["dunstctl", "history-pop"])
      else root.toggle()
    }

    Rectangle {
      visible: root.unseenCount > 0
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.topMargin: Style.space(2)
      height: badgeText.implicitHeight
      width: Math.max(height, badgeText.implicitWidth + Style.space(4))
      radius: height / 2
      color: Commons.Color.accent

      Text {
        id: badgeText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.unseenCount > 9 ? "9+" : String(root.unseenCount)
        color: Commons.Color.popups.background
        font.family: root.fontFamily
        font.pixelSize: Math.max(8, Style.font.caption - 2)
        font.bold: true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveSelection(dy) }
      onActivateRequested: root.showAgain(root.selected())
      onDeleteRequested: root.remove(root.selected())
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (!root.service) return
        if (t === "d") root.service.toggleDnd()
        else if (t === "c") root.service.clearAll()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // ---------- Header: title · Do Not Disturb · clear ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(title.implicitHeight, controls.implicitHeight)

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Notifications"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Row {
            id: controls
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Do Not Disturb"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              checked: root.paused
              foreground: root.foreground
              onToggled: if (root.service) root.service.toggleDnd()
            }

            PanelActionButton {
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰆴"
              tooltipText: "Clear all"
              foreground: root.foreground
              hoverColor: Commons.Color.urgent
              fontFamily: root.fontFamily
              enabled: root.rows.length > 0
              onClicked: if (root.service) root.service.clearAll()
            }
          }
        }

        Text {
          width: parent.width
          visible: !!root.service && root.service.waiting > 0
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.service ? root.service.waiting + " held back until notifications are allowed again" : ""
          color: Commons.Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator { width: parent.width }

        Text {
          width: parent.width
          visible: root.rows.length === 0
          horizontalAlignment: Text.AlignHCenter
          topPadding: Style.space(24)
          bottomPadding: Style.space(24)
          textFormat: Text.PlainText
          text: root.available ? "No notifications" : "dunst is not running"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        // ---------- History, grouped by app ----------
        ListView {
          id: list
          width: parent.width
          height: Math.min(contentHeight, Style.space(460))
          visible: root.rows.length > 0
          clip: true
          spacing: Style.space(4)
          boundsBehavior: Flickable.StopAtBounds
          // Every row is built, so contentHeight is exact; history is short.
          cacheBuffer: 100000
          model: root.rows

          Connections {
            target: root
            function onSelectedIndexChanged() { list.positionViewAtIndex(root.selectedIndex, ListView.Contain) }
          }

          delegate: Column {
            id: entry
            required property var modelData
            required property int index
            readonly property bool hasCursor: root.cursorActive && root.selectedIndex === index
            readonly property bool fresh: root.freshKeys[modelData.key] === true

            width: ListView.view.width
            spacing: Style.space(4)

            Text {
              width: parent.width
              visible: entry.modelData.heading !== ""
              topPadding: entry.index > 0 ? Style.space(6) : 0
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: entry.modelData.heading
                + (entry.modelData.groupSize > 1 ? " · " + entry.modelData.groupSize : "")
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            CursorSurface {
              width: parent.width
              implicitHeight: Math.max(icon.height, labels.implicitHeight) + Style.space(16)
              hasCursor: entry.hasCursor
              bordered: true
              foreground: root.foreground

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: {
                  root.cursorActive = true
                  root.selectedIndex = entry.index
                }
                onClicked: root.showAgain(entry.modelData)
              }

              Item {
                id: icon
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                width: Style.space(28)
                height: width

                Image {
                  id: picture
                  anchors.fill: parent
                  source: Model.iconUrl(entry.modelData.icon)
                  sourceSize.width: 64
                  sourceSize.height: 64
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                }

                Text {
                  anchors.centerIn: parent
                  visible: picture.status !== Image.Ready
                  textFormat: Text.PlainText
                  text: ""
                  color: entry.modelData.critical ? Commons.Color.urgent : root.foreground
                  opacity: entry.modelData.low ? 0.5 : 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                }
              }

              Column {
                id: labels
                anchors.left: icon.right
                anchors.leftMargin: Style.space(10)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.top: parent.top
                anchors.topMargin: Style.space(8)
                spacing: Style.space(2)

                Item {
                  width: parent.width
                  implicitHeight: Math.max(summary.implicitHeight, age.implicitHeight)

                  Text {
                    id: summary
                    anchors.left: parent.left
                    anchors.right: age.left
                    anchors.rightMargin: Style.space(8)
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: entry.modelData.summary
                    color: entry.modelData.critical ? Commons.Color.urgent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  Text {
                    id: age
                    anchors.right: parent.right
                    anchors.verticalCenter: summary.verticalCenter
                    // Hidden, not removed, so the title doesn't reflow on hover.
                    opacity: entry.hasCursor ? 0 : 0.6
                    textFormat: Text.PlainText
                    text: (entry.fresh ? "● " : "") + Model.ageLabel(entry.modelData.arrived, root.now)
                    color: entry.fresh ? Commons.Color.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  width: parent.width
                  visible: text !== ""
                  textFormat: Text.PlainText
                  wrapMode: Text.Wrap
                  elide: Text.ElideRight
                  maximumLineCount: 3
                  text: entry.modelData.body
                  color: root.foreground
                  opacity: 0.8
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(4)
                visible: entry.hasCursor
                iconText: "󰅖"
                tooltipText: "Remove"
                foreground: root.foreground
                hoverColor: Commons.Color.urgent
                fontFamily: root.fontFamily
                onClicked: root.remove(entry.modelData)
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.rows.length > 0
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: "Enter show again · x remove · c clear all · d do not disturb"
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}

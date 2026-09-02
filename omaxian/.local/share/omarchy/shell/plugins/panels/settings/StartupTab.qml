import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
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
  readonly property var appLibrary: shell ? shell.appLibrary : null

  property var apps: []
  property string addValue: ""

  FileView {
    id: startupFile
    path: Quickshell.env("HOME") + "/.config/omarchy/startup.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.apps = Model.parseStartup(text()).apps
    onFileChanged: reload()
    onLoadFailed: root.apps = []
  }

  readonly property var addOptions: {
    var lib = root.appLibrary
    var query = ""
    var entries = lib && typeof lib.sortedEntries === "function" ? lib.sortedEntries(query) : []
    var taken = {}
    for (var i = 0; i < root.apps.length; i++) taken[root.apps[i].desktopId] = true
    var out = [{ value: "", label: "Add an app…" }]
    for (var j = 0; j < entries.length; j++) {
      var entry = entries[j]
      if (!entry || !entry.id) continue
      var id = Model.stripDesktop(entry.id)
      if (!id || taken[id]) continue
      var name = lib && typeof lib.entryName === "function" ? lib.entryName(entry) : String(entry.name || id)
      out.push({ value: id, label: name })
    }
    return out
  }

  function persist(nextApps) {
    root.apps = nextApps
    startupFile.setText(Model.serializeStartup(nextApps))
  }

  function entryLabel(desktopId) {
    var lib = root.appLibrary
    if (lib && typeof lib.normalizeDesktopId === "function") {
      var entry = DesktopEntries.byId(desktopId)
      if (entry && typeof lib.entryName === "function") return lib.entryName(entry)
    }
    var byId = DesktopEntries.byId(desktopId)
    if (byId && byId.name) return String(byId.name)
    return desktopId
  }

  function entryIcon(desktopId) {
    var lib = root.appLibrary
    var entry = DesktopEntries.byId(desktopId)
    var icon = entry && entry.icon ? entry.icon : ""
    if (lib && typeof lib.iconSource === "function") return lib.iconSource(icon)
    return ""
  }

  function addApp(desktopId) {
    var id = Model.stripDesktop(desktopId)
    if (!id) return
    var next = root.apps.slice()
    for (var i = 0; i < next.length; i++) if (next[i].desktopId === id) return
    next.push({ desktopId: id, enabled: true })
    root.persist(next)
    root.addValue = ""
  }

  function toggleApp(index) {
    var next = root.apps.slice()
    if (index < 0 || index >= next.length) return
    next[index] = { desktopId: next[index].desktopId, enabled: !next[index].enabled }
    root.persist(next)
  }

  function removeApp(index) {
    var next = root.apps.slice()
    if (index < 0 || index >= next.length) return
    next.splice(index, 1)
    root.persist(next)
  }

  function moveApp(index, delta) {
    var next = root.apps.slice()
    var dest = index + delta
    if (index < 0 || dest < 0 || dest >= next.length) return
    var item = next.splice(index, 1)[0]
    next.splice(dest, 0, item)
    root.persist(next)
  }

  function launchNow(desktopId) {
    var id = Model.stripDesktop(desktopId)
    if (!id) return
    // Do not gate on `typeof … === "function"` — QML methods on AppLibrary
    // often fail that check from another file's JS even when callable.
    if (root.appLibrary) {
      root.appLibrary.launch(id)
      return
    }
    Quickshell.execDetached(["setsid", "-f", "gtk-launch", id + ".desktop"])
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

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Extra apps started at login, after the session daemons. Changes save immediately and take effect on the next login — use Launch now to test."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      SearchableDropdown {
        width: parent.width
        label: "Add application"
        value: root.addValue
        options: root.addOptions
        placeholderText: "Search apps…"
        emptyText: "No matching apps"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(v) {
          root.addValue = v
          if (v) root.addApp(v)
        }
      }

      Repeater {
        model: root.apps

        delegate: Item {
          required property var modelData
          required property int index
          width: col.width
          height: Math.max(labelCol.implicitHeight, actions.implicitHeight)

          Image {
            id: appIcon
            width: Style.space(22)
            height: Style.space(22)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            fillMode: Image.PreserveAspectFit
            source: root.entryIcon(modelData.desktopId)
            visible: source !== ""
          }

          Column {
            id: labelCol
            anchors.left: appIcon.visible ? appIcon.right : parent.left
            anchors.leftMargin: appIcon.visible ? Style.space(6) : 0
            anchors.right: actions.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
              width: parent.width
              elide: Text.ElideRight
              text: root.entryLabel(modelData.desktopId)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              width: parent.width
              elide: Text.ElideMiddle
              text: modelData.desktopId
              color: Qt.darker(root.foreground, 1.5)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: actions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              cursorRing: false
              checked: modelData.enabled
              foreground: root.foreground
              onToggled: root.toggleApp(index)
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: "Launch"
              tooltipText: "Launch now"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: root.launchNow(modelData.desktopId)
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: "▲"
              tooltipText: "Move up"
              bordered: true
              enabled: index > 0
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: root.moveApp(index, -1)
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: "▼"
              tooltipText: "Move down"
              bordered: true
              enabled: index < root.apps.length - 1
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: root.moveApp(index, 1)
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: "×"
              tooltipText: "Remove"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: root.removeApp(index)
            }
          }
        }
      }

      Text {
        visible: root.apps.length === 0
        text: "No extra startup apps yet."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}

import QtQuick
import Quickshell
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
  readonly property bool barHidden: !!(shell && shell.bar && shell.bar.barHidden)

  // Clone through JSON so layout arrays are real JS arrays in this engine
  // (QML `property var` lists fail Array.isArray and confuse Repeaters).
  readonly property string configJson: {
    var _ = root.revision
    var raw = (shell && shell.shellConfig) ? shell.shellConfig : null
    if (!raw) return "{}"
    try { return JSON.stringify(raw) } catch (e) { return "{}" }
  }
  readonly property var config: {
    try { return JSON.parse(root.configJson) } catch (e) { return {} }
  }
  readonly property var bar: (config && config.bar) ? config.bar : {}
  readonly property string position: {
    var p = String(bar.position || "top")
    return /^(top|bottom|left|right)$/.test(p) ? p : "top"
  }
  readonly property bool transparent: bar.transparent === true
  ListModel { id: leftModel }
  ListModel { id: centerModel }
  ListModel { id: rightModel }
  ListModel { id: availableModel }

  function entryId(entry) {
    if (typeof entry === "string") return String(entry).trim()
    if (entry && typeof entry === "object") {
      var id = entry.id !== undefined ? entry.id : entry["id"]
      return id !== undefined && id !== null ? String(id).trim() : ""
    }
    return ""
  }

  function sectionEntries(layout, name) {
    var out = []
    if (!layout) return out
    var arr = layout[name]
    if (!arr || typeof arr.length !== "number") return out
    for (var i = 0; i < arr.length; i++) {
      var id = entryId(arr[i])
      if (id) out.push(id)
    }
    return out
  }

  function fillSection(model, ids, name) {
    model.clear()
    for (var i = 0; i < ids.length; i++)
      model.append({ wid: ids[i], sectionName: name, idx: i })
  }

  function hasKind(manifest, kind) {
    if (!manifest || manifest.kinds === undefined || manifest.kinds === null) return false
    var kinds = manifest.kinds
    if (typeof kinds.indexOf === "function") {
      try { return kinds.indexOf(kind) !== -1 } catch (e) {}
    }
    if (typeof kinds.length === "number") {
      for (var i = 0; i < kinds.length; i++) {
        if (String(kinds[i]) === kind) return true
      }
    }
    return false
  }

  function pluginKeys(plugins) {
    var keys = []
    if (!plugins) return keys
    try { keys = Object.keys(plugins) } catch (e) { keys = [] }
    if (keys.length === 0) {
      for (var id in plugins) keys.push(id)
    }
    return keys
  }

  function widgetName(id) {
    var m = pluginRegistry && pluginRegistry.installedPlugins ? pluginRegistry.installedPlugins[id] : null
    return Model.displayNameOf(m, id)
  }

  function defaultSection(manifest) {
    var meta = manifest && manifest.barWidget ? manifest.barWidget : null
    var section = meta ? String(meta.defaultSection || "") : ""
    return (section === "left" || section === "center" || section === "right") ? section : "right"
  }

  function rebuild() {
    var layout = (root.bar && root.bar.layout) ? root.bar.layout : null
    if (!layout && shell && shell.shellConfig && shell.shellConfig.bar)
      layout = shell.shellConfig.bar.layout
    if (!layout) layout = {}
    var left = sectionEntries(layout, "left")
    var center = sectionEntries(layout, "center")
    var right = sectionEntries(layout, "right")
    fillSection(leftModel, left, "left")
    fillSection(centerModel, center, "center")
    fillSection(rightModel, right, "right")

    var onIds = {}
    var i
    for (i = 0; i < left.length; i++) onIds[left[i]] = true
    for (i = 0; i < center.length; i++) onIds[center[i]] = true
    for (i = 0; i < right.length; i++) onIds[right[i]] = true

    var plugins = pluginRegistry && pluginRegistry.installedPlugins ? pluginRegistry.installedPlugins : null
    var keys = pluginKeys(plugins)
    var avail = []
    for (i = 0; i < keys.length; i++) {
      var id = keys[i]
      var m = plugins[id]
      if (!hasKind(m, "bar-widget")) continue
      if (onIds[id]) continue
      avail.push({
        wid: id,
        displayName: root.widgetName(id),
        sectionName: defaultSection(m)
      })
    }
    avail.sort(function(a, b) {
      if (a.displayName < b.displayName) return -1
      if (a.displayName > b.displayName) return 1
      return String(a.wid).localeCompare(String(b.wid))
    })
    availableModel.clear()
    for (i = 0; i < avail.length; i++) availableModel.append(avail[i])
  }

  onConfigJsonChanged: rebuild()
  onRevisionChanged: rebuild()
  onPluginRegistryChanged: rebuild()
  onShellChanged: rebuild()
  Component.onCompleted: rebuild()

  function mutateBar(mutator) {
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    shell.mutateShellConfig(function(cfg) {
      if (!cfg.bar) cfg.bar = {}
      mutator(cfg)
    })
  }

  function setPosition(value) {
    mutateBar(function(cfg) { cfg.bar.position = value })
  }

  function setTransparent(next) {
    mutateBar(function(cfg) { cfg.bar.transparent = next === true })
  }

  function toggleBarVisible() {
    Quickshell.execDetached(["omarchy-toggle-bar"])
  }

  function removeWidget(id) {
    if (!pluginRegistry) return
    pluginRegistry.setEnabled(id, false)
  }

  function addWidget(id, section) {
    if (!pluginRegistry) return
    pluginRegistry.putBarWidget(id, { section: section || "right" })
  }

  function moveWidget(id, section, index, delta) {
    if (!pluginRegistry) return
    var next = index + delta
    if (next < 0) return
    pluginRegistry.moveBarWidget(id, {
      fromSection: section,
      fromIndex: index,
      section: section,
      index: next
    })
  }

  component WidgetRow: Row {
    id: row
    required property string wid
    required property string sectionName
    required property int idx
    property int sectionCount: 0
    width: parent.width
    spacing: Style.space(6)

    Text {
      width: parent.width - upBtn.width - downBtn.width - removeBtn.width - parent.spacing * 3
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: root.widgetName(row.wid)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Button {
      id: upBtn
      text: "▲"
      tooltipText: "Move up"
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      horizontalPadding: Style.space(8)
      verticalPadding: Style.space(4)
      enabled: row.idx > 0
      onClicked: root.moveWidget(row.wid, row.sectionName, row.idx, -1)
    }

    Button {
      id: downBtn
      text: "▼"
      tooltipText: "Move down"
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      horizontalPadding: Style.space(8)
      verticalPadding: Style.space(4)
      enabled: row.idx < row.sectionCount - 1
      onClicked: root.moveWidget(row.wid, row.sectionName, row.idx, 1)
    }

    Button {
      id: removeBtn
      text: "×"
      tooltipText: "Remove from bar"
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      horizontalPadding: Style.space(8)
      verticalPadding: Style.space(4)
      onClicked: root.removeWidget(row.wid)
    }
  }

  component SectionBlock: BorderSurface {
    id: card
    property string title: ""
    property var sectionModel: null
    property string emptyText: "No widgets in this section"
    width: col.width
    radius: Style.cornerRadius
    clip: true
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
    borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.normalBorderWidth))
    implicitHeight: sectionCol.implicitHeight

    Column {
      id: sectionCol
      width: parent.width
      spacing: 0

      Rectangle {
        width: parent.width
        height: headerLabel.implicitHeight + Style.space(14)
        color: Style.hoverFillFor(root.foreground, Color.accent)

        Text {
          id: headerLabel
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          text: title
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      Item {
        width: parent.width
        height: bodyCol.implicitHeight + Style.space(16)

        Column {
          id: bodyCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          anchors.topMargin: Style.space(8)
          spacing: Style.space(4)

          Repeater {
            model: sectionModel
            delegate: WidgetRow {
              sectionCount: sectionModel ? sectionModel.count : 0
            }
          }

          Text {
            visible: !sectionModel || sectionModel.count === 0
            width: parent.width
            wrapMode: Text.Wrap
            text: emptyText
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  component AvailableRow: Row {
    id: availRow
    required property string wid
    required property string displayName
    required property string sectionName
    width: parent.width
    spacing: Style.space(6)

    Text {
      width: parent.width - addBtn.width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: displayName
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Button {
      id: addBtn
      text: "Add"
      tooltipText: "Add to " + availRow.sectionName
      bordered: true
      foreground: root.foreground
      fontFamily: root.fontFamily
      fontSize: Style.font.caption
      horizontalPadding: Style.space(10)
      verticalPadding: Style.space(4)
      onClicked: root.addWidget(availRow.wid, availRow.sectionName)
    }
  }

  component AvailableBlock: BorderSurface {
    id: availCard
    width: col.width
    radius: Style.cornerRadius
    clip: true
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
    borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.normalBorderWidth))
    implicitHeight: availCol.implicitHeight

    Column {
      id: availCol
      width: parent.width
      spacing: 0

      Rectangle {
        width: parent.width
        height: availHeader.implicitHeight + Style.space(14)
        color: Style.hoverFillFor(root.foreground, Color.accent)

        Text {
          id: availHeader
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          text: "Available widgets"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      Item {
        width: parent.width
        height: availBody.implicitHeight + Style.space(16)

        Column {
          id: availBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          anchors.topMargin: Style.space(8)
          spacing: Style.space(4)

          Repeater {
            model: availableModel
            delegate: AvailableRow {}
          }

          Text {
            visible: availableModel.count === 0
            width: parent.width
            wrapMode: Text.Wrap
            text: (leftModel.count + centerModel.count + rightModel.count) === 0
              ? "No bar widgets found. If the bar itself is populated, the Settings plugin needs a shell restart after deploy."
              : "Every installed bar widget is already on the bar."
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
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
        label: "Show bar"
        description: "Hide the bar without killing the shell (same as Super menu → Toggle → Menu Bar)."
        checked: !root.barHidden
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.toggleBarVisible()
      }

      Dropdown {
        width: parent.width
        label: "Position"
        value: root.position
        options: [
          { value: "top", label: "Top" },
          { value: "bottom", label: "Bottom" },
          { value: "left", label: "Left" },
          { value: "right", label: "Right" }
        ]
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function(v) { root.setPosition(v) }
      }

      Toggle {
        width: parent.width
        label: "Transparent bar"
        description: "Fully transparent background; text color is sampled from the wallpaper."
        checked: root.transparent
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.setTransparent(!root.transparent)
      }

      SectionBlock { title: "Left"; sectionModel: leftModel }
      SectionBlock { title: "Center"; sectionModel: centerModel }
      SectionBlock { title: "Right"; sectionModel: rightModel }
      AvailableBlock {}
    }
  }
}

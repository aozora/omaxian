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
  readonly property int rowSpacing: Style.space(4)

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
  readonly property bool island: bar.island === true
  readonly property int islandMargin: {
    var n = Number(bar.islandMargin)
    return (isFinite(n) && n >= 0) ? Math.min(48, Math.round(n)) : 8
  }
  readonly property int islandRadius: {
    var n = Number(bar.islandRadius)
    return (isFinite(n) && n >= 0) ? Math.min(48, Math.round(n)) : Style.radiusPopup
  }

  ListModel { id: leftModel }
  ListModel { id: centerModel }
  ListModel { id: rightModel }
  ListModel { id: availableModel }

  // --- drag state ----------------------------------------------------------
  property bool dragging: false
  property var dragPayload: null
  property string dropTargetKind: ""
  property int dropInsertIndex: -1
  property real dragGhostX: 0
  property real dragGhostY: 0
  property string sectionChooserWid: ""
  property var dropZones: []

  function registerDropZone(zone) {
    if (!zone) return
    var next = []
    var i
    for (i = 0; i < dropZones.length; i++) {
      if (dropZones[i] && dropZones[i] !== zone)
        next.push(dropZones[i])
    }
    next.push(zone)
    dropZones = next
  }

  function unregisterDropZone(zone) {
    var next = []
    var i
    for (i = 0; i < dropZones.length; i++) {
      if (dropZones[i] && dropZones[i] !== zone)
        next.push(dropZones[i])
    }
    dropZones = next
  }

  function clearDropHighlight() {
    dropTargetKind = ""
    dropInsertIndex = -1
  }

  function endDrag() {
    dragging = false
    dragPayload = null
    clearDropHighlight()
    if (flick) flick.interactive = true
  }

  function beginDrag(payload) {
    sectionChooserWid = ""
    dragPayload = payload
    dragging = true
    if (flick) flick.interactive = false
  }

  function insertIndexAtY(listColumn, y) {
    if (!listColumn) return 0
    var children = listColumn.children
    var idx = 0
    var i
    for (i = 0; i < children.length; i++) {
      var row = children[i]
      if (!row || !row.visible || row.wid === undefined) continue
      var mid = row.y + row.height / 2
      if (y >= mid) idx++
      else break
    }
    return idx
  }

  // MouseArea keeps the grab while dragging, so drop zones never see hover.
  // Hit-test from the handle's pointer position instead.
  function trackDragPoint(rootX, rootY) {
    dragGhostX = rootX
    dragGhostY = rootY
    var i
    for (i = 0; i < dropZones.length; i++) {
      var zone = dropZones[i]
      if (!zone || !zone.width) continue
      var local = zone.mapFromItem(root, rootX, rootY)
      if (local.x < 0 || local.y < 0 || local.x > zone.width || local.y > zone.height)
        continue
      dropTargetKind = zone.kind
      var flickY = zone.contentYOffset ? zone.contentYOffset() : 0
      var listY = local.y - Style.space(6) + flickY
      dropInsertIndex = insertIndexAtY(zone.listColumn, listY)
      return
    }
    clearDropHighlight()
  }

  function applyDrop(toKind, insertIndex) {
    var payload = root.dragPayload
    if (!payload || !payload.id) {
      endDrag()
      return
    }
    if (!toKind) {
      endDrag()
      return
    }
    var id = String(payload.id)
    var fromKind = String(payload.fromKind || "")
    var fromIndex = Math.floor(Number(payload.fromIndex))
    var targetIndex = Math.max(0, Math.floor(Number(insertIndex) || 0))

    if (fromKind === "available") {
      if (toKind === "available") {
        endDrag()
        return
      }
      addWidget(id, toKind, targetIndex)
      endDrag()
      return
    }

    if (toKind === "available") {
      removeWidget(id)
      endDrag()
      return
    }

    if (fromKind === toKind && fromIndex < targetIndex)
      targetIndex = targetIndex - 1
    if (fromKind === toKind && targetIndex === fromIndex) {
      endDrag()
      return
    }
    placeWidget(id, fromKind, fromIndex, toKind, targetIndex)
    endDrag()
  }

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

  function setIsland(next) {
    mutateBar(function(cfg) { cfg.bar.island = next === true })
  }

  function setIslandMargin(value) {
    var n = Math.min(48, Math.max(0, Math.round(Number(value) || 0)))
    mutateBar(function(cfg) { cfg.bar.islandMargin = n })
  }

  function setIslandRadius(value) {
    var n = Math.min(48, Math.max(0, Math.round(Number(value) || 0)))
    mutateBar(function(cfg) { cfg.bar.islandRadius = n })
  }

  function toggleBarVisible() {
    Quickshell.execDetached(["omarchy-toggle-bar"])
  }

  function removeWidget(id) {
    if (!pluginRegistry) return
    pluginRegistry.setEnabled(id, false)
  }

  function addWidget(id, section, index) {
    if (!pluginRegistry) return
    var placement = { section: section || "right" }
    if (index !== undefined && index !== null && isFinite(Number(index)))
      placement.index = Math.max(0, Math.floor(Number(index)))
    pluginRegistry.putBarWidget(id, placement)
  }

  function placeWidget(id, fromSection, fromIndex, toSection, toIndex) {
    if (!pluginRegistry) return
    pluginRegistry.moveBarWidget(id, {
      fromSection: fromSection,
      fromIndex: fromIndex,
      section: toSection,
      index: toIndex
    })
  }

  function moveWidget(id, section, index, delta) {
    if (!pluginRegistry) return
    var next = index + delta
    if (next < 0) return
    placeWidget(id, section, index, section, next)
  }

  component GrabHandle: Item {
    id: handle
    property string dragId: ""
    property string fromKind: ""
    property int fromIndex: 0
    property string dragLabel: ""
    width: handleText.implicitWidth + Style.space(8)
    height: Math.max(handleText.implicitHeight + Style.space(8), Style.space(28))

    Text {
      id: handleText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "⠿"
      color: Qt.darker(root.foreground, 1.35)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: handleMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.OpenHandCursor
      preventStealing: true
      property real pressX: 0
      property real pressY: 0
      property bool armed: false

      onPressed: function(mouse) {
        pressX = mouse.x
        pressY = mouse.y
        armed = false
        cursorShape = Qt.ClosedHandCursor
      }
      onReleased: function(mouse) {
        cursorShape = Qt.OpenHandCursor
        if (root.dragging) {
          var p = mapToItem(root, mouse.x, mouse.y)
          root.trackDragPoint(p.x, p.y)
          root.applyDrop(root.dropTargetKind, root.dropInsertIndex >= 0 ? root.dropInsertIndex : 0)
        } else {
          root.endDrag()
        }
        armed = false
      }
      onCanceled: {
        cursorShape = Qt.OpenHandCursor
        root.endDrag()
        armed = false
      }
      onPositionChanged: function(mouse) {
        if (!pressed) return
        var dx = mouse.x - pressX
        var dy = mouse.y - pressY
        if (!armed && (dx * dx + dy * dy) < 64) return
        if (!armed) {
          armed = true
          root.beginDrag({
            id: handle.dragId,
            fromKind: handle.fromKind,
            fromIndex: handle.fromIndex,
            name: handle.dragLabel
          })
        }
        var p = mapToItem(root, mouse.x, mouse.y)
        root.trackDragPoint(p.x, p.y)
      }
    }
  }

  component InsertMarker: Rectangle {
    property bool active: false
    width: parent ? parent.width : 0
    height: 2
    radius: 1
    visible: active
    color: Color.accent
    z: 10
  }

  component WidgetRow: Item {
    id: row
    required property string wid
    required property string sectionName
    required property int idx
    property int sectionCount: 0
    property bool showInsertBefore: root.dragging
      && root.dropTargetKind === row.sectionName
      && root.dropInsertIndex === row.idx
      && !(root.dragPayload && root.dragPayload.fromKind === row.sectionName && root.dragPayload.fromIndex === row.idx)

    width: parent ? parent.width : 0
    height: rowCol.implicitHeight
    opacity: root.dragging && root.dragPayload && root.dragPayload.id === row.wid
      && root.dragPayload.fromKind === row.sectionName ? 0.35 : 1

    Column {
      id: rowCol
      width: parent.width
      spacing: 0

      InsertMarker {
        width: parent.width
        active: row.showInsertBefore
      }

      Row {
        id: controls
        width: parent.width
        spacing: Style.space(6)

        GrabHandle {
          id: grab
          anchors.verticalCenter: parent.verticalCenter
          dragId: row.wid
          fromKind: row.sectionName
          fromIndex: row.idx
          dragLabel: root.widgetName(row.wid)
        }

        Text {
          textFormat: Text.PlainText
          width: Math.max(40, parent.width - grab.width - upBtn.width - downBtn.width - removeBtn.width - parent.spacing * 4)
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
    }
  }

  component AvailableRow: Item {
    id: availRow
    required property int index
    required property string wid
    required property string displayName
    required property string sectionName
    property bool choosing: root.sectionChooserWid === availRow.wid
    property bool showInsertBefore: root.dragging
      && root.dropTargetKind === "available"
      && root.dropInsertIndex === availRow.index

    width: parent ? parent.width : 0
    height: availCol.implicitHeight
    opacity: root.dragging && root.dragPayload && root.dragPayload.id === availRow.wid
      && root.dragPayload.fromKind === "available" ? 0.35 : 1

    Column {
      id: availCol
      width: parent.width
      spacing: 0

      InsertMarker {
        width: parent.width
        active: availRow.showInsertBefore
      }

      Row {
        width: parent.width
        spacing: Style.space(6)

        GrabHandle {
          id: availGrab
          anchors.verticalCenter: parent.verticalCenter
          dragId: availRow.wid
          fromKind: "available"
          fromIndex: availRow.index
          dragLabel: availRow.displayName
        }

        Text {
          textFormat: Text.PlainText
          width: Math.max(40, parent.width - availGrab.width - addArea.width - parent.spacing * 2)
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: displayName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Item {
          id: addArea
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(addIdle.implicitWidth, addPick.implicitWidth)
          height: Math.max(addIdle.implicitHeight, addPick.implicitHeight)

          Row {
            id: addIdle
            spacing: Style.space(4)
            visible: !availRow.choosing

            Button {
              text: "Add"
              tooltipText: "Choose section (default " + availRow.sectionName + ")"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(4)
              onClicked: root.sectionChooserWid = availRow.wid
            }
          }

          Row {
            id: addPick
            spacing: Style.space(4)
            visible: availRow.choosing

            Button {
              text: "L"
              tooltipText: "Add to Left"
              bordered: true
              selected: availRow.sectionName === "left"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: {
                root.addWidget(availRow.wid, "left")
                root.sectionChooserWid = ""
              }
            }
            Button {
              text: "C"
              tooltipText: "Add to Center"
              bordered: true
              selected: availRow.sectionName === "center"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: {
                root.addWidget(availRow.wid, "center")
                root.sectionChooserWid = ""
              }
            }
            Button {
              text: "R"
              tooltipText: "Add to Right"
              bordered: true
              selected: availRow.sectionName === "right"
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: {
                root.addWidget(availRow.wid, "right")
                root.sectionChooserWid = ""
              }
            }
          }
        }
      }
    }
  }

  component DropListBody: Item {
    id: dropBody
    property string kind: ""
    property var listModel: null
    property int bodyMaxHeight: Style.space(140)
    property string emptyText: ""
    property bool availableMode: false
    property alias listColumn: bodyCol

    width: parent ? parent.width : 0
    height: Math.min(bodyMaxHeight, Math.max(Style.space(48), innerFlick.contentHeight + Style.space(16)))

    readonly property bool showEndMarker: root.dragging
      && root.dropTargetKind === dropBody.kind
      && listModel
      && root.dropInsertIndex >= listModel.count

    readonly property bool dropHover: root.dragging && root.dropTargetKind === dropBody.kind

    function contentYOffset() {
      return innerFlick.contentY
    }

    Component.onCompleted: root.registerDropZone(dropBody)
    Component.onDestruction: root.unregisterDropZone(dropBody)

    Rectangle {
      anchors.fill: parent
      visible: dropBody.dropHover
      color: "transparent"
      border.width: Math.max(1, Style.normalBorderWidth)
      border.color: Color.accent
      radius: Style.cornerRadius
      opacity: 0.85
    }

    Flickable {
      id: innerFlick
      anchors.fill: parent
      anchors.margins: Style.space(2)
      clip: true
      contentWidth: width
      contentHeight: bodyCol.implicitHeight + Style.space(8)
      boundsBehavior: Flickable.StopAtBounds
      interactive: !root.dragging && contentHeight > height

      Column {
        id: bodyCol
        width: innerFlick.width - Style.space(16)
        x: Style.space(8)
        y: Style.space(6)
        spacing: root.rowSpacing

        Repeater {
          model: dropBody.availableMode ? null : dropBody.listModel
          delegate: WidgetRow {
            width: bodyCol.width
            sectionCount: dropBody.listModel ? dropBody.listModel.count : 0
          }
        }

        Repeater {
          model: dropBody.availableMode ? dropBody.listModel : null
          delegate: AvailableRow {
            width: bodyCol.width
          }
        }

        InsertMarker {
          width: parent.width
          active: dropBody.showEndMarker
        }

        Text {
          textFormat: Text.PlainText
          visible: !dropBody.listModel || dropBody.listModel.count === 0
          width: parent.width
          wrapMode: Text.Wrap
          text: dropBody.emptyText
          color: Qt.darker(root.foreground, 1.5)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  component SectionBlock: BorderSurface {
    id: card
    property string title: ""
    property string kind: ""
    property var sectionModel: null
    property string emptyText: "No widgets in this section"
    property int bodyMaxHeight: Style.space(120)
    width: parent ? parent.width : 0
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
          textFormat: Text.PlainText
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

      DropListBody {
        kind: card.kind
        listModel: card.sectionModel
        bodyMaxHeight: card.bodyMaxHeight
        emptyText: card.emptyText
        availableMode: false
      }
    }
  }

  component AvailableBlock: BorderSurface {
    id: availCard
    property int bodyMaxHeight: Style.space(280)
    width: parent ? parent.width : 0
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
          textFormat: Text.PlainText
          id: availHeader
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(10)
          anchors.rightMargin: Style.space(10)
          text: "Available"
          color: Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }

      DropListBody {
        kind: "available"
        listModel: availableModel
        bodyMaxHeight: availCard.bodyMaxHeight
        availableMode: true
        emptyText: (leftModel.count + centerModel.count + rightModel.count) === 0
          ? "No bar widgets found. If the bar itself is populated, the Settings plugin needs a shell restart after deploy."
          : "Every installed bar widget is already on the bar. Drag a placed widget here to remove it."
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.sectionChooserWid !== "" && !root.dragging
    z: -1
    onClicked: root.sectionChooserWid = ""
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

      Toggle {
        width: parent.width
        label: "Floating island"
        description: "Inset the bar from the screen edges with rounded corners. Outer padding shows the wallpaper and is click-through. Toggling this may need a shell restart."
        checked: root.island
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.setIsland(!root.island)
      }

      NumberField {
        width: parent.width
        enabled: root.island
        opacity: root.island ? 1 : 0.45
        label: "Island margin"
        value: root.islandMargin
        from: 0
        to: 48
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) { root.setIslandMargin(v) }
      }

      NumberField {
        width: parent.width
        enabled: root.island
        opacity: root.island ? 1 : 0.45
        label: "Island corner radius"
        value: root.islandRadius
        from: 0
        to: 48
        foreground: root.foreground
        fontFamily: root.fontFamily
        onModified: function(v) { root.setIslandRadius(v) }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        wrapMode: Text.Wrap
        text: "Drag ⠿ to rearrange. Drop onto Available to remove. Add opens a section picker."
        color: Qt.darker(root.foreground, 1.45)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Row {
        id: arrangeRow
        width: parent.width
        spacing: Style.space(12)

        AvailableBlock {
          width: (parent.width - parent.spacing) / 2
          bodyMaxHeight: Math.max(Style.space(200), rightColumn.implicitHeight - Style.space(36))
        }

        Column {
          id: rightColumn
          width: (parent.width - parent.spacing) / 2
          spacing: Style.space(8)

          SectionBlock {
            title: "Left"
            kind: "left"
            sectionModel: leftModel
            bodyMaxHeight: Style.space(120)
          }
          SectionBlock {
            title: "Center"
            kind: "center"
            sectionModel: centerModel
            bodyMaxHeight: Style.space(120)
          }
          SectionBlock {
            title: "Right"
            kind: "right"
            sectionModel: rightModel
            bodyMaxHeight: Style.space(120)
          }
        }
      }
    }
  }

  Rectangle {
    id: ghost
    visible: root.dragging && root.dragPayload
    x: root.dragGhostX + Style.space(8)
    y: root.dragGhostY + Style.space(8)
    z: 100
    width: ghostLabel.implicitWidth + Style.space(16)
    height: ghostLabel.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: Color.popups.background
    border.width: Math.max(1, Style.normalBorderWidth)
    border.color: Color.accent
    opacity: 0.95

    Text {
      id: ghostLabel
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.dragPayload ? String(root.dragPayload.name || root.dragPayload.id || "") : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}

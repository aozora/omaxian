import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.indicators"

  // X11 delta: "Dictation" (Wayland) stays off the default list.
  // ScreenRecording uses Flatpak/PATH gpu-screen-recorder via
  // omarchy-capture-screenrecording.
  readonly property var defaultIndicatorEntries: [ "NightLight", "Reminder", "Dnd", "StayAwake", "ScreenRecording" ]
  readonly property var indicatorEntries: indicatorEntriesFromSettings(settings)
  property var activeIndicatorIds: []
  property var indicatorActiveStates: ({})
  property bool indicatorAreaHovered: false
  property bool indicatorItemHovered: false
  // Held a moment after the pointer leaves, so crossing between icons, or a
  // frame where the widget moves under a still pointer, doesn't flicker them.
  property bool hoverRevealHeld: false
  readonly property bool alwaysShowIndicators: {
    var _ = settings
    return setting("alwaysShow", false) === true
  }
  // The tray's drawer already hides them until hovered, and an empty widget
  // there would leave no room to hover for a second reveal.
  readonly property bool revealInactiveIndicators: alwaysShowIndicators || inTraySection || hoverRevealHeld

  signal refreshRequested()

  ListModel { id: activeIndicatorModel }

  function entryId(entry) {
    if (typeof entry === "string") return entry
    if (Util.isPlainObject(entry)) {
      var id = entry["id"]
      if (id !== undefined && id !== null && String(id) !== "") return String(id)
    }
    return ""
  }

  function entrySettings(entry) {
    if (!Util.isPlainObject(entry)) return {}
    var copy = {}
    for (var key in entry) {
      if (key === "id") continue
      copy[key] = entry[key]
    }
    return copy
  }

  function indicatorEntriesFromSettings(settings) {
    var source = defaultIndicatorEntries
    if (settings.items && typeof settings.items.length === "number" && settings.items.length > 0) source = settings.items
    else if (settings.indicators && typeof settings.indicators.length === "number" && settings.indicators.length > 0) source = settings.indicators

    var result = []
    for (var i = 0; i < source.length; i++) {
      var item = source[i]
      if (typeof item !== "string" && item !== null && typeof item === "object") {
        try {
          item = JSON.parse(JSON.stringify(item))
        } catch (error) {
        }
      }
      var id = entryId(item)
      if (id !== "") result.push(item)
    }
    return result
  }

  function setIndicatorAreaHovered(hovered) {
    indicatorAreaHovered = hovered
    syncHoverReveal()
  }

  function setIndicatorItemHovered(hovered) {
    indicatorItemHovered = hovered
    syncHoverReveal()
  }

  function syncHoverReveal() {
    if (indicatorAreaHovered || indicatorItemHovered) {
      indicatorHideTimer.stop()
      hoverRevealHeld = true
    } else {
      indicatorHideTimer.restart()
    }
  }

  function hasIndicatorId(id) {
    for (var i = 0; i < indicatorEntries.length; i++) {
      if (entryId(indicatorEntries[i]) === id) return true
    }
    return false
  }

  function entryForId(id) {
    for (var i = 0; i < indicatorEntries.length; i++) {
      var entry = indicatorEntries[i]
      if (entryId(entry) === id) return entry
    }

    return { id: id }
  }

  function activeModelIndex(id) {
    for (var i = 0; i < activeIndicatorModel.count; i++) {
      if (activeIndicatorModel.get(i).activeId === id) return i
    }
    return -1
  }

  function copyActiveStates() {
    var states = {}
    for (var id in indicatorActiveStates) {
      if (indicatorActiveStates[id] === true) states[id] = true
    }
    return states
  }

  function orderedActiveIds(states, preferredOrder) {
    var ids = []

    for (var i = 0; i < preferredOrder.length; i++) {
      var id = preferredOrder[i]
      if (ids.indexOf(id) === -1 && hasIndicatorId(id) && states[id] === true) ids.push(id)
    }

    return ids
  }

  function syncActiveIndicatorModel() {
    for (var i = activeIndicatorModel.count - 1; i >= 0; i--) {
      if (activeIndicatorIds.indexOf(activeIndicatorModel.get(i).activeId) === -1)
        activeIndicatorModel.remove(i)
    }

    for (var j = 0; j < activeIndicatorIds.length; j++) {
      var id = activeIndicatorIds[j]
      var index = activeModelIndex(id)
      if (index === -1) activeIndicatorModel.insert(j, { activeId: id })
      else if (index !== j) activeIndicatorModel.move(index, j, 1)
    }
  }

  function setIndicatorActive(entry, active) {
    var id = entryId(entry)
    if (id === "") return

    var states = copyActiveStates()
    if (active) states[id] = true
    else delete states[id]

    indicatorActiveStates = states

    var ids = orderedActiveIds(states, activeIndicatorIds)
    // The active block sits closest to the clock, so newcomers go on the far
    // side of it. Appending would shove everything already showing sideways.
    if (active && ids.indexOf(id) === -1 && hasIndicatorId(id)) ids.unshift(id)
    activeIndicatorIds = ids
    syncActiveIndicatorModel()
  }

  function syncActiveIndicatorOrder() {
    activeIndicatorIds = orderedActiveIds(indicatorActiveStates, activeIndicatorIds)
    syncActiveIndicatorModel()
  }

  function refresh() { root.refreshRequested() }

  onIndicatorEntriesChanged: syncActiveIndicatorOrder()

  // Only the tree for the current orientation exists (see orientationLoader
  // below); its wrapper keeps the stock sizing expressions, so the root's
  // implicit size still follows the blocks synchronously rather than waiting
  // on a positioner's polish.
  implicitWidth: orientationLoader.item ? orientationLoader.item.implicitWidth : 0
  implicitHeight: orientationLoader.item ? orientationLoader.item.implicitHeight : 0

  IpcHandler {
    target: "omarchy.indicators"

    function refresh(): void {
      root.broadcast("refresh")
    }
  }

  Timer {
    id: indicatorHideTimer
    interval: 120
    onTriggered: if (!root.indicatorAreaHovered && !root.indicatorItemHovered) root.hoverRevealHeld = false
  }

  Component.onCompleted: root.refreshRequested()

  // Instantiating both orientation trees and toggling `visible` doubled every
  // indicator per bar (and every process an indicator spawns, once per
  // monitor). Load only the tree that matches the bar orientation instead.
  Loader {
    id: orientationLoader
    sourceComponent: root.vertical ? verticalIndicatorsTree : horizontalIndicatorsTree
  }

  // Where the hidden icons would show: hovering there reveals them, and the
  // rest of the bar leaves them hidden. Hidden, they take no room, so the zone
  // reaches past the widget on the side they grow toward. Revealed, it keeps
  // half that reach: in the centered box the widget slides half its growth
  // back the other way as the box re-centers, and a zone that stopped at the
  // widget's edge would lose the pointer that opened it, closing and
  // reopening in a loop. Above the icons, which a hover handler doesn't block.
  Item {
    objectName: "hiddenBlockZone"

    readonly property real reach: (orientationLoader.item ? orientationLoader.item.inactiveLength : 0) * (root.revealInactiveIndicators ? 0.5 : 1)
    readonly property real alongStart: root.fixedEdge === "start" ? 0 : -reach
    readonly property real alongLength: (root.vertical ? root.implicitHeight : root.implicitWidth) + reach

    x: root.vertical ? 0 : alongStart
    y: root.vertical ? alongStart : 0
    width: root.vertical ? (root.implicitWidth || root.barSize) : alongLength
    height: root.vertical ? alongLength : (root.implicitHeight || root.barSize)

    HoverHandler {
      onHoveredChanged: root.setIndicatorAreaHovered(hovered)
    }
  }

  Component {
    id: horizontalIndicatorsTree

    Item {
      readonly property real inactiveLength: inactiveHorizontalBlock.implicitWidth

      implicitWidth: activeHorizontalBlock.implicitWidth + inactiveHorizontalArea.implicitWidth
      implicitHeight: Math.max(activeHorizontalBlock.implicitHeight, inactiveHorizontalArea.implicitHeight)
      width: implicitWidth
      height: implicitHeight

      Row {
        id: horizontalIndicators

        spacing: 0

        Item {
          id: inactiveHorizontalArea

          implicitWidth: root.revealInactiveIndicators ? inactiveHorizontalBlock.implicitWidth : 0
          implicitHeight: Math.max(inactiveHorizontalBlock.implicitHeight, root.barSize)
          width: implicitWidth
          height: implicitHeight
          clip: true

          IndicatorBlock {
            id: inactiveHorizontalBlock
            anchors.verticalCenter: parent.verticalCenter
            indicatorsModule: root
            indicatorEntries: root.indicatorEntries
            indicatorBlock: "inactive"
            horizontal: true
            reportActiveState: !root.vertical
          }
        }

        ActiveIndicatorBlock {
          id: activeHorizontalBlock
          indicatorsModule: root
          indicatorModel: activeIndicatorModel
          horizontal: true
          reportActiveState: !root.vertical
        }
      }
    }
  }

  Component {
    id: verticalIndicatorsTree

    Item {
      readonly property real inactiveLength: inactiveVerticalBlock.implicitHeight

      implicitWidth: Math.max(activeVerticalBlock.implicitWidth, inactiveVerticalArea.implicitWidth)
      implicitHeight: activeVerticalBlock.implicitHeight + inactiveVerticalArea.implicitHeight
      width: implicitWidth
      height: implicitHeight

      Column {
        id: verticalIndicators

        spacing: 0

        Item {
          id: inactiveVerticalArea

          implicitWidth: Math.max(inactiveVerticalBlock.implicitWidth, root.barSize)
          implicitHeight: root.revealInactiveIndicators ? inactiveVerticalBlock.implicitHeight : 0
          width: implicitWidth
          height: implicitHeight
          clip: true

          IndicatorBlock {
            id: inactiveVerticalBlock
            anchors.horizontalCenter: parent.horizontalCenter
            indicatorsModule: root
            indicatorEntries: root.indicatorEntries
            indicatorBlock: "inactive"
            horizontal: false
            reportActiveState: root.vertical
          }
        }

        ActiveIndicatorBlock {
          id: activeVerticalBlock
          indicatorsModule: root
          indicatorModel: activeIndicatorModel
          horizontal: false
          reportActiveState: root.vertical
        }
      }
    }
  }

  component ActiveIndicatorBlock: Item {
    id: activeIndicatorBlockRoot

    property var indicatorModel: null
    property var indicatorsModule: null
    property bool horizontal: true
    property bool reportActiveState: false

    implicitWidth: blockLoader.item ? blockLoader.item.implicitWidth : 0
    implicitHeight: blockLoader.item ? blockLoader.item.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
      id: blockLoader

      anchors.centerIn: parent
      sourceComponent: activeIndicatorBlockRoot.horizontal ? horizontalActiveIndicatorBlock : verticalActiveIndicatorBlock
    }

    Component {
      id: horizontalActiveIndicatorBlock

      Row {
        spacing: 0

        Repeater {
          model: activeIndicatorBlockRoot.indicatorModel

          IndicatorLoader {
            required property string activeId
            indicatorsModule: activeIndicatorBlockRoot.indicatorsModule
            entry: activeIndicatorBlockRoot.indicatorsModule.entryForId(activeId)
            indicatorBlock: "active"
            reportActiveState: activeIndicatorBlockRoot.reportActiveState
          }
        }
      }
    }

    Component {
      id: verticalActiveIndicatorBlock

      Column {
        spacing: 0

        Repeater {
          model: activeIndicatorBlockRoot.indicatorModel

          IndicatorLoader {
            required property string activeId
            indicatorsModule: activeIndicatorBlockRoot.indicatorsModule
            entry: activeIndicatorBlockRoot.indicatorsModule.entryForId(activeId)
            indicatorBlock: "active"
            reportActiveState: activeIndicatorBlockRoot.reportActiveState
          }
        }
      }
    }
  }

  component IndicatorBlock: Item {
    id: indicatorBlockRoot

    property var indicatorEntries: []
    property var indicatorsModule: null
    property string indicatorBlock: "active"
    property bool horizontal: true
    property bool reportActiveState: false

    implicitWidth: blockLoader.item ? blockLoader.item.implicitWidth : 0
    implicitHeight: blockLoader.item ? blockLoader.item.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    Loader {
      id: blockLoader

      anchors.centerIn: parent
      sourceComponent: indicatorBlockRoot.horizontal ? horizontalIndicatorBlock : verticalIndicatorBlock
    }

    Component {
      id: horizontalIndicatorBlock

      Row {
        spacing: 0

        Repeater {
          model: indicatorBlockRoot.indicatorEntries

          IndicatorLoader {
            required property var modelData
            indicatorsModule: indicatorBlockRoot.indicatorsModule
            entry: modelData
            indicatorBlock: indicatorBlockRoot.indicatorBlock
            reportActiveState: indicatorBlockRoot.reportActiveState
          }
        }
      }
    }

    Component {
      id: verticalIndicatorBlock

      Column {
        spacing: 0

        Repeater {
          model: indicatorBlockRoot.indicatorEntries

          IndicatorLoader {
            required property var modelData
            indicatorsModule: indicatorBlockRoot.indicatorsModule
            entry: modelData
            indicatorBlock: indicatorBlockRoot.indicatorBlock
            reportActiveState: indicatorBlockRoot.reportActiveState
          }
        }
      }
    }
  }

  component IndicatorLoader: Item {
    id: indicatorSlot

    required property var entry
    property var indicatorsModule: null
    required property string indicatorBlock
    property bool reportActiveState: false
    property bool activeStateObserved: false
    readonly property string indicatorId: root.entryId(entry)
    readonly property var indicatorSettings: root.entrySettings(entry)
    readonly property var barRef: root.bar

    implicitWidth: indicatorSource.item && indicatorSource.item.visible ? indicatorSource.item.implicitWidth : 0
    implicitHeight: indicatorSource.item && indicatorSource.item.visible ? indicatorSource.item.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    onEntryChanged: {
      activeStateObserved = false
      injectProps()
      syncActiveState()
    }
    onIndicatorBlockChanged: injectProps()
    onIndicatorSettingsChanged: injectProps()
    onIndicatorsModuleChanged: {
      injectProps()
      syncActiveState()
    }
    onReportActiveStateChanged: syncActiveState()
    onBarRefChanged: injectProps()

    Loader {
      id: indicatorSource

      anchors.fill: parent
      source: indicatorSlot.indicatorId ? Qt.resolvedUrl("../indicators/" + indicatorSlot.indicatorId + ".qml") : ""
      onLoaded: {
        indicatorSlot.injectProps()
        indicatorSlot.syncActiveState()
      }
      onStatusChanged: if (status === Loader.Error) console.warn("Indicator loader error", indicatorSlot.indicatorId, source)
    }

    Connections {
      target: indicatorSource.item
      ignoreUnknownSignals: true
      function onActiveChanged() { indicatorSlot.syncActiveState() }
    }

    function injectProps() {
      var target = indicatorSource.item
      if (!target) return
      if ("bar" in target) target.bar = root.bar
      if ("moduleName" in target) target.moduleName = indicatorId
      if ("settings" in target) target.settings = indicatorSettings
      if ("indicatorBlock" in target) target.indicatorBlock = indicatorBlock
      if ("indicatorHost" in target) target.indicatorHost = root
      if ("activeOverride" in target) target.activeOverride = indicatorBlock === "active" ? true : null
    }

    function syncActiveState() {
      if (!reportActiveState || !indicatorsModule || !indicatorsModule.setIndicatorActive) return

      var active = !!indicatorSource.item && indicatorSource.item.active === true
      if (indicatorBlock === "active") {
        if (active) activeStateObserved = true
        else if (!activeStateObserved) return
      }

      indicatorsModule.setIndicatorActive(entry, active)
    }
  }
}

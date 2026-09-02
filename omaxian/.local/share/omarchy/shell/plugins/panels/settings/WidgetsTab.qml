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
  readonly property var config: {
    var _ = root.revision
    return (shell && shell.shellConfig) ? shell.shellConfig : {}
  }

  // Stable id list for the Repeater. Replaced only when the set of schema-
  // bearing widgets changes — not on every setBarWidget write — so open
  // MultiSelect / Dropdown popups survive value updates.
  property var widgetIds: []

  function collectWidgetIds() {
    var plugins = pluginRegistry && pluginRegistry.installedPlugins ? pluginRegistry.installedPlugins : {}
    var rows = []
    for (var id in plugins) {
      var m = plugins[id]
      if (!Model.isBarWidgetManifest(m)) continue
      var schema = Model.widgetSchema(m)
      if (!schema.length) continue
      rows.push({ id: id, name: Model.displayNameOf(m, id) })
    }
    rows.sort(function(a, b) {
      if (a.name < b.name) return -1
      if (a.name > b.name) return 1
      return String(a.id).localeCompare(String(b.id))
    })
    var out = []
    for (var i = 0; i < rows.length; i++) out.push(rows[i].id)
    return out
  }

  function idsEqual(a, b) {
    if (a === b) return true
    if (!a || !b || a.length !== b.length) return false
    for (var i = 0; i < a.length; i++) if (String(a[i]) !== String(b[i])) return false
    return true
  }

  function syncWidgetIds() {
    var next = collectWidgetIds()
    if (!idsEqual(root.widgetIds, next)) root.widgetIds = next
  }

  function manifestFor(id) {
    var plugins = pluginRegistry && pluginRegistry.installedPlugins ? pluginRegistry.installedPlugins : {}
    return plugins[id] || null
  }

  function widgetName(id) {
    return Model.displayNameOf(manifestFor(id), id)
  }

  function widgetSchema(id) {
    return Model.widgetSchema(manifestFor(id))
  }

  function widgetDefaults(id) {
    return Model.widgetDefaults(manifestFor(id))
  }

  function widgetValues(id) {
    var _ = root.revision
    var loc = Model.findBarEntry(root.config, id)
    return loc.found ? Model.entrySettings(loc.entry) : {}
  }

  function widgetOnBar(id) {
    var _ = root.revision
    return Model.findBarEntry(root.config, id).found
  }

  function setWidgetKey(id, key, value) {
    if (!pluginRegistry) return
    var loc = Model.findBarEntry(root.config, id)
    if (!loc.found) return
    pluginRegistry.setBarWidget(id, key, value, { fromSection: loc.section, fromIndex: loc.index })
  }

  onRevisionChanged: syncWidgetIds()
  Component.onCompleted: syncWidgetIds()

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
      spacing: Style.space(16)

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Per-widget options stored on the bar layout entry in shell.json. Add a widget on the Bar tab before editing it here."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.widgetIds

        delegate: Column {
          required property var modelData
          readonly property string widgetId: String(modelData)
          width: col.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: root.widgetName(widgetId)
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            visible: !root.widgetOnBar(widgetId)
            width: parent.width
            wrapMode: Text.Wrap
            text: "Not on the bar — add it under Bar to persist these settings."
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          SchemaForm {
            width: parent.width
            schema: root.widgetSchema(widgetId)
            values: root.widgetValues(widgetId)
            defaults: root.widgetDefaults(widgetId)
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.widgetOnBar(widgetId)
            onChanged: function(key, value) { root.setWidgetKey(widgetId, key, value) }
          }
        }
      }

      Text {
        visible: root.widgetIds.length === 0
        text: "No bar widgets currently expose a settings schema."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}

import QtQuick
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
  readonly property var rows: {
    var _ = root.revision
    var plugins = pluginRegistry && pluginRegistry.installedPlugins ? pluginRegistry.installedPlugins : {}
    var out = []
    for (var id in plugins) {
      var m = plugins[id]
      if (!Model.isPluginsTabCandidate(m)) continue
      out.push({
        id: id,
        name: String(m.name || id),
        description: String(m.description || ""),
        firstParty: !!m.__isFirstParty,
        enabled: pluginRegistry.isEnabled(id),
        note: id === "omarchy.idle" ? "Idle lock times in shell.json are not enforced on X11." : ""
      })
    }
    out.sort(function(a, b) {
      if (a.firstParty !== b.firstParty) return a.firstParty ? -1 : 1
      if (a.name < b.name) return -1
      if (a.name > b.name) return 1
      return String(a.id).localeCompare(String(b.id))
    })
    return out
  }

  function setPlugin(id, enabled) {
    if (!pluginRegistry) return
    pluginRegistry.setEnabled(id, enabled)
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
      spacing: Style.space(10)

      Text {
        width: parent.width
        wrapMode: Text.Wrap
        text: "Enable or disable first-party panels and services, and third-party plugins. Add / clone / remove still lives under Menu → Setup → Plugins."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: root.rows

        delegate: Toggle {
          required property var modelData
          width: col.width
          label: modelData.name
          description: {
            var bits = []
            if (modelData.description) bits.push(modelData.description)
            bits.push(modelData.firstParty ? "Built-in" : "Third-party")
            bits.push(modelData.id)
            if (modelData.note) bits.push(modelData.note)
            return bits.join(" · ")
          }
          checked: modelData.enabled
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.setPlugin(modelData.id, !modelData.enabled)
        }
      }
    }
  }
}

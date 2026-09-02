import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Renders a barWidget.schema array as labeled controls. Emits `changed(key, value)`
// when the user edits a field; the parent persists via PluginRegistry.setBarWidget.
Column {
  id: root

  property var schema: []
  property var values: ({})
  property var defaults: ({})
  property color foreground: Color.popups.text
  property string fontFamily: Style.font.family
  property bool enabled: true

  signal changed(string key, var value)

  width: parent ? parent.width : Style.space(400)
  spacing: Style.space(10)

  function fieldValue(item) {
    return Model.schemaFieldValue(item, root.values, root.defaults)
  }

  function emitValue(key, value) {
    if (!root.enabled) return
    root.changed(String(key), value)
  }

  Repeater {
    model: Model.arrayFrom(root.schema)

    delegate: Item {
      required property var modelData
      readonly property string fieldKey: modelData && modelData.key !== undefined ? String(modelData.key) : ""
      readonly property string fieldType: String((modelData && modelData.type) || "string").toLowerCase()
      readonly property string fieldLabel: String((modelData && modelData.label) || fieldKey)
      readonly property string fieldDescription: String((modelData && modelData.description) || "")
      width: root.width
      height: fieldColumn.implicitHeight

      Column {
        id: fieldColumn
        width: parent.width
        spacing: Style.space(4)

        Toggle {
          visible: fieldType === "boolean" || fieldType === "bool"
          width: parent.width
          label: fieldLabel
          description: fieldDescription
          checked: fieldValue(modelData) === true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.emitValue(fieldKey, !checked)
        }

        Dropdown {
          visible: fieldType === "select" || fieldType === "enum"
          width: parent.width
          label: fieldLabel
          value: String(fieldValue(modelData) !== undefined && fieldValue(modelData) !== null ? fieldValue(modelData) : "")
          options: Model.arrayFrom(modelData && modelData.options)
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.emitValue(fieldKey, v) }
        }

        MultiSelect {
          visible: fieldType === "multiselect"
          width: parent.width
          label: fieldLabel
          values: {
            var v = fieldValue(modelData)
            return Model.arrayFrom(v).map(function(x) { return String(x) })
          }
          options: Model.arrayFrom(modelData && modelData.options)
          noSelectionText: String((modelData && modelData.noSelectionText) || "None selected")
          placeholderText: String((modelData && modelData.placeholderText) || "Search...")
          emptyText: String((modelData && modelData.emptyText) || "No options")
          foreground: root.foreground
          fontFamily: root.fontFamily
          onChanged: function(v) { root.emitValue(fieldKey, v) }
        }

        NumberField {
          visible: fieldType === "number" || fieldType === "integer" || fieldType === "int"
          width: parent.width
          label: fieldLabel
          value: {
            var n = Number(fieldValue(modelData))
            return isFinite(n) ? Math.round(n) : Number(modelData && modelData.defaultValue || 0)
          }
          from: modelData && modelData.from !== undefined ? Number(modelData.from) : 0
          to: modelData && modelData.to !== undefined ? Number(modelData.to) : 1000
          foreground: root.foreground
          fontFamily: root.fontFamily
          onModified: function(v) { root.emitValue(fieldKey, v) }
        }

        Column {
          visible: fieldType === "string" || fieldType === "text"
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: fieldLabel
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }

          Text {
            visible: fieldDescription !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: fieldDescription
            color: Qt.darker(root.foreground, 1.5)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          TextField {
            width: parent.width
            text: String(fieldValue(modelData) !== undefined && fieldValue(modelData) !== null ? fieldValue(modelData) : "")
            foreground: root.foreground
            onEditingFinished: root.emitValue(fieldKey, text)
          }
        }
      }
    }
  }
}

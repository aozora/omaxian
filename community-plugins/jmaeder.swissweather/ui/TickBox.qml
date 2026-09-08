import QtQuick
import qs.Commons

// A labelled tick, for the panel's on/off settings.
//
// Deliberately plain: an outlined box that fills when checked, next to its
// label, with the whole row as the hit target. The panel's other controls are
// chips showing a current choice out of several; this one has to read as "on
// or off" at a glance, from the footer, without a legend.
//
// Filled versus empty carries the state, with no check-mark glyph involved.
// A "✓" is not in every font a theme might select, and at eleven pixels a
// missing-glyph box is indistinguishable from an unchecked one.
Item {
  id: root

  property string label: ""
  property bool checked: true

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal toggled(bool checked)

  implicitWidth: row.implicitWidth + Style.space(10)
  implicitHeight: row.implicitHeight + Style.space(8)

  readonly property color _onColor: Style.selectedStateColor(foreground, accent)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: hover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Rectangle {
      id: box
      width: Style.space(11)
      height: width
      anchors.verticalCenter: parent.verticalCenter
      radius: Math.min(2, Style.cornerRadius)
      color: "transparent"
      border.width: Math.max(1, Style.space(1))
      border.color: root.checked
        ? root._onColor
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.45)

      Behavior on border.color { ColorAnimation { duration: 120 } }

      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.5
        height: width
        radius: Math.min(1, box.radius)
        color: root._onColor
        opacity: root.checked ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
      }
    }

    Text {
      text: root.label
      color: root.checked ? Qt.darker(root.foreground, 1.2) : Qt.darker(root.foreground, 1.7)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
    }
  }

  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

  MouseArea {
    anchors.fill: parent
    onClicked: root.toggled(!root.checked)
  }
}

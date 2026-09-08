import QtQuick
import qs.Commons

// A town in the favourites strip.
//
// Selecting and removing are the same chip because they are the same object:
// splitting the remove action into a separate list would cost a screen the
// panel does not have. The remove target only appears on hover so a stray
// click on a chip switches town rather than deleting it.
Item {
  id: root

  property string label: ""
  property bool selected: false
  property bool removable: true
  // Leading glyph — a location pin marks the detected town, which is shown
  // alongside the favourites without being one of them.
  property string glyph: ""
  property string removeTooltip: ""

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  signal activated()
  signal removeRequested()

  implicitWidth: row.implicitWidth + Style.space(20)
  implicitHeight: row.implicitHeight + Style.space(10)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: root.selected ? Style.selectedFillFor(root.foreground, root.accent)
      : (chipHover.hovered ? Style.hoverFillFor(root.foreground, root.accent) : Style.normalFillFor(root.foreground, root.accent))
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      visible: root.glyph !== ""
      text: root.glyph
      color: Qt.darker(root.foreground, 1.35)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
    }

    Text {
      text: root.label
      color: root.selected ? Style.selectedStateColor(root.foreground, root.accent) : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.selected
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
    }

    // Reserves its width whether or not it is showing, so revealing it on
    // hover does not shove the neighbouring chips sideways.
    Item {
      width: root.removable ? removeGlyph.implicitWidth : 0
      height: removeGlyph.implicitHeight
      anchors.verticalCenter: parent.verticalCenter
      visible: root.removable

      Text {
        id: removeGlyph
        text: "✕"
        opacity: chipHover.hovered ? 1 : 0
        color: removeHover.hovered ? Color.urgent : Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        textFormat: Text.PlainText

        Behavior on opacity { NumberAnimation { duration: 120 } }

        HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          enabled: root.removable && chipHover.hovered
          onClicked: root.removeRequested()
        }
      }
    }
  }

  HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }

  MouseArea {
    anchors.fill: parent
    // Below the remove target in stacking order, so the ✕ wins the click it
    // overlaps.
    z: -1
    onClicked: root.activated()
  }
}

import QtQuick
import qs.Commons

// One measured quantity, with the forecast uncertainty that goes with it.
//
// The two lines are deliberately different things and are labelled as such:
// the large number is what the nearest MeteoSwiss station actually recorded,
// the small range beneath it is the 10-90 % band the forecast gives for the
// same hour. Presenting a measurement as if it carried that spread — or a
// forecast as if it were a reading — would be the easiest way for this panel
// to mislead, so the wording never merges them.
Item {
  id: root

  property string label: ""
  property string value: "—"
  property string unit: ""
  property string band: ""
  property string bandUnit: ""
  property string note: ""

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool interactive: false

  signal activated()

  implicitWidth: content.implicitWidth + Style.space(20)
  implicitHeight: content.implicitHeight + Style.space(12)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: (root.interactive && hover.hovered) ? Style.hoverFillFor(root.foreground, root.accent) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(3)

    Text {
      text: root.label.toUpperCase()
      color: Qt.darker(root.foreground, 1.55)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
      textFormat: Text.PlainText
    }

    Row {
      spacing: Style.space(3)

      Text {
        id: valueText
        text: root.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
        textFormat: Text.PlainText
      }

      Text {
        visible: root.unit !== ""
        text: root.unit
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.baseline: valueText.baseline
        textFormat: Text.PlainText
      }
    }

    Text {
      visible: root.band !== ""
      // The chevrons mark this line as a forecast interval rather than a
      // reading, without spending a word on it in every cell.
      text: "‹ " + root.band + (root.bandUnit !== "" ? " " + root.bandUnit : "") + " ›"
      color: Qt.darker(root.foreground, 1.7)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }

    Text {
      visible: root.note !== ""
      text: root.note
      color: Qt.darker(root.foreground, 1.7)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }
  }

  HoverHandler {
    id: hover
    enabled: root.interactive
    cursorShape: Qt.PointingHandCursor
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
    acceptedButtons: Qt.LeftButton
    onClicked: root.activated()
  }
}

import QtQuick
import qs.Commons

// A key, drawn as one.
//
// The panel's shortcut list has to say "press this" without a sentence saying
// it, and a bordered box around a letter is the one convention every reader
// already knows. Kept quieter than the panel's chips — no fill, a dimmed
// border — because these are labels to be read, not controls to be clicked.
//
// Wide enough for its label and never narrower than it is tall: a lone "h"
// in a box as wide as "Enter" reads as an empty field, and a square is what
// a single key looks like.
Rectangle {
  id: root

  property string label: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  implicitWidth: Math.max(implicitHeight, text.implicitWidth + Style.space(10))
  implicitHeight: text.implicitHeight + Style.space(6)

  radius: Math.min(3, Style.cornerRadius)
  color: "transparent"
  border.width: Math.max(1, Style.space(1))
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.35)

  Text {
    id: text
    anchors.centerIn: parent
    text: root.label
    color: Qt.darker(root.foreground, 1.3)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    textFormat: Text.PlainText
  }
}

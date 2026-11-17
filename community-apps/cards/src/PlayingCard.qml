import QtQuick

// One card, drawn in the look of the series in play. It knows which side is
// up and how it is marked; where it lies is the table's business.
Item {
  id: card
  property int cardId: 0
  property bool faceUp: false
  property var look
  // Every measure is given for a card 112 wide and scaled by this.
  property real unit: 1
  property bool motion: true
  property bool target: false
  property bool cursor: false
  property bool lifted: false
  readonly property int suit: Math.floor(cardId / 13)
  readonly property int rank: cardId % 13
  readonly property color ink: suit === 1 || suit === 2 ? look.red : look.black
  readonly property string label: ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"][rank]
  // The side being drawn, which changes over halfway through a turn.
  property bool shown: false
  Component.onCompleted: shown = faceUp
  onFaceUpChanged: {
    if (motion) {
      flip.restart()
    } else {
      flip.stop()
      turn.xScale = 1
      shown = faceUp
    }
  }
  transform: Scale { id: turn; origin.x: card.width / 2; xScale: 1 }
  SequentialAnimation {
    id: flip
    NumberAnimation { target: turn; property: "xScale"; to: 0; duration: 80; easing.type: Easing.InQuad }
    ScriptAction { script: card.shown = card.faceUp }
    NumberAnimation { target: turn; property: "xScale"; to: 1; duration: 90; easing.type: Easing.OutQuad }
  }

  Rectangle {
    visible: card.lifted
    x: 5 * card.unit
    y: 6 * card.unit
    width: parent.width
    height: parent.height
    radius: card.look.radius * card.unit
    color: card.look.shadow
  }
  Rectangle {
    id: face
    objectName: "face"
    visible: card.shown
    anchors.fill: parent
    radius: card.look.radius * card.unit
    color: card.look.face
    border.color: card.look.edge
    border.width: 1
    clip: card.look.bleed
    Row {
      x: card.look.padX * card.unit
      y: card.look.padY * card.unit
      spacing: 5 * card.unit
      Text {
        id: index
        objectName: "rank"
        text: card.label
        color: card.ink
        font.family: card.look.family
        font.weight: card.look.weight
        font.pixelSize: Math.round(card.look.indexSize * card.unit)
      }
      Suit { objectName: "pip"; anchors.verticalCenter: index.verticalCenter; suit: card.suit; color: card.ink; size: card.look.pipSize * card.unit }
    }
    // Nocturne sets its suit in a moon: a gold ring with a fainter one around it.
    Rectangle {
      visible: card.look.disc
      width: 86 * card.unit
      height: width
      radius: width / 2
      anchors.horizontalCenter: parent.horizontalCenter
      y: 37 * card.unit
      color: "transparent"
      border.color: Qt.alpha(card.look.edge, .3)
      Rectangle {
        anchors.centerIn: parent
        width: 76 * card.unit
        height: width
        radius: width / 2
        color: "transparent"
        border.color: Qt.alpha(card.look.edge, .75)
      }
    }
    Suit {
      suit: card.suit
      color: card.ink
      outline: card.look.centreOutline
      size: card.look.centreSize * card.unit
      // Riso runs its suit off the corner of the card; the others centre it.
      x: card.look.bleed ? parent.width - size + 26 * card.unit : (parent.width - size) / 2
      y: card.look.bleed ? parent.height - size + 22 * card.unit : card.look.centreY * card.unit
    }
    Loader {
      active: card.look.bottomIndex
      anchors { right: parent.right; bottom: parent.bottom; rightMargin: card.look.padX * card.unit; bottomMargin: card.look.padY * card.unit }
      sourceComponent: Row {
        rotation: 180
        spacing: 5 * card.unit
        Text {
          id: foot
          text: card.label
          color: card.ink
          font.family: card.look.family
          font.weight: card.look.weight
          font.pixelSize: Math.round(card.look.indexSize * card.unit)
        }
        Suit { anchors.verticalCenter: foot.verticalCenter; suit: card.suit; color: card.ink; size: card.look.pipSize * card.unit }
      }
    }
  }
  Rectangle {
    visible: !card.shown
    anchors.fill: parent
    radius: card.look.radius * card.unit
    color: card.look.backFrame
    border.color: card.look.backEdge
    border.width: 1
    CardBack {
      anchors.fill: parent
      anchors.margins: Math.round(card.look.backInset * card.unit)
      series: card.look.index
      fill: card.look.backFill
      line: card.look.backLine
      unit: card.unit
    }
  }
  // Somewhere the cards in hand may be put down.
  Rectangle {
    objectName: "targetRing"
    visible: card.target
    anchors.fill: parent
    anchors.margins: -5 * card.unit
    radius: (card.look.radius + 5) * card.unit
    color: "transparent"
    border.color: card.look.ring
    border.width: Math.max(1, 1.5 * card.unit)
    opacity: .8
  }
  Rectangle {
    objectName: "cursorRing"
    visible: card.cursor
    anchors.fill: parent
    anchors.margins: -8 * card.unit
    radius: (card.look.radius + 8) * card.unit
    color: "transparent"
    border.color: card.look.cursor
    border.width: Math.max(1, 1.5 * card.unit)
  }
}

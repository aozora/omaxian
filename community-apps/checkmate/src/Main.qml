import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Shapes

ApplicationWindow {
  id: window
  width: 1280
  height: 850
  minimumWidth: 920
  minimumHeight: 650
  visible: true
  title: "Checkmate"
  color: theme.background
  Material.theme: theme.light ? Material.Light : Material.Dark
  Material.accent: theme.accent
  Material.background: theme.background
  Material.foreground: theme.foreground
  Overlay.modal: Rectangle { color: "#80000000" }
  font.family: "sans-serif"
  font.pixelSize: 14
  property color line: Qt.alpha(theme.foreground,.13)
  property color muted: Qt.alpha(theme.foreground,.58)
  property var setNames: [qsTr("Orbital Orders"),qsTr("Midnight Atelier"),qsTr("Moss & Myth"),qsTr("Candy Kingdom")]
  property var setDescriptions: [qsTr("Across the stars"),qsTr("Wood, ivory & brass"),qsTr("A woodland tale"),qsTr("A little sweetness")]
  property var setColors: ["#d9ad69","#c99b6b","#93a775","#db9eb2"]
  property color tint: setColors[backend.pieceSet]
  property var difficultyNames: [qsTr("Casual"),qsTr("Thoughtful"),qsTr("Challenging")]
  // Tab clears the footer and the moves away so only the board is left; they come back with every launch.
  property bool chrome: true
  property bool modalOpen: newGameDialog.visible || helpDialog.visible || promotionDialog.visible
  function statusText() {
    if (backend.outcome === "white-wins") return qsTr("White wins by checkmate")
    if (backend.outcome === "black-wins") return qsTr("Black wins by checkmate")
    if (backend.outcome === "stalemate") return qsTr("Draw by stalemate")
    if (backend.outcome === "material") return qsTr("Draw · insufficient material")
    if (backend.outcome === "fifty-moves") return qsTr("Draw · fifty-move rule")
    if (backend.outcome === "repetition") return qsTr("Draw · threefold repetition")
    if (backend.thinking) return qsTr("Considering the next move…")
    if (backend.checked) return backend.whiteTurn ? qsTr("White is in check") : qsTr("Black is in check")
    return backend.whiteTurn ? qsTr("White to move") : qsTr("Black to move")
  }
  component FlatButton: Button {
    id: control
    Material.roundedScale: theme.radius
    implicitHeight: 38
    background: Rectangle {
      radius: theme.radius
      color: control.down ? Qt.alpha(theme.accent,.22) : control.hovered ? Qt.alpha(theme.foreground,.09) : "transparent"
      border.color: window.line
    }
    contentItem: Text {
      text: control.text
      color: control.enabled ? theme.foreground : window.muted
      opacity: control.enabled ? 1 : .5
      font: control.font
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
  }
  // A small icon drawn as strokes, from a path in a 24-unit square.
  component Glyph: Item {
    id: glyph
    property string path
    property color ink: theme.foreground
    implicitWidth: 16
    implicitHeight: 16
    Shape {
      width: 24; height: 24
      anchors.centerIn: parent
      scale: 16 / 24
      preferredRendererType: Shape.CurveRenderer
      ShapePath {
        fillColor: "transparent"
        strokeColor: glyph.ink
        strokeWidth: 1.9
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: glyph.path }
      }
    }
  }
  // A footer action: an icon, with its name and key on hover.
  component FooterIcon: Button {
    id: action
    hoverEnabled: true
    // Material pads a button unevenly for its label; an icon sits dead centre.
    leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
    property string path
    property string name
    property string key
    property bool lit: false
    implicitWidth: 30
    implicitHeight: 26
    topInset: 0; bottomInset: 0; leftInset: 0; rightInset: 0
    focusPolicy: Qt.NoFocus
    Accessible.name: name
    ToolTip.visible: hovered
    ToolTip.delay: 400
    ToolTip.text: name + "  ·  " + key
    background: Rectangle {
      radius: theme.radius
      color: action.down ? Qt.alpha(window.tint,.26) : action.lit ? Qt.alpha(window.tint,action.hovered ? .22 : .13) : action.hovered ? Qt.alpha(theme.foreground,.09) : "transparent"
      border.color: action.lit ? Qt.alpha(window.tint,.5) : "transparent"
    }
    contentItem: Item {
      opacity: action.enabled ? 1 : .35
      Glyph { anchors.centerIn: parent; path: action.path; ink: action.hovered || action.lit ? theme.foreground : Qt.alpha(theme.foreground,.78) }
    }
  }
  Item {
    anchors.fill: parent
    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true
    ColumnLayout {
      anchors.fill: parent
      spacing: 0
      BoardView { id: board; objectName: "board"; Layout.fillWidth: true; Layout.fillHeight: true }
      // Everything that isn't the board, in one slim line under it.
      Rectangle {
        objectName: "footer"
        visible: window.chrome
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        color: theme.background
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: window.line }
        RowLayout {
          id: tools
          anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
          spacing: 12
          // The name is also the way to the shortcuts.
          AbstractButton {
            id: wordmark
            hoverEnabled: true
            objectName: "wordmark"
            implicitWidth: mark.implicitWidth + 12
            implicitHeight: 26
            focusPolicy: Qt.NoFocus
            Accessible.name: qsTr("Keyboard shortcuts")
            ToolTip.visible: hovered
            ToolTip.delay: 400
            ToolTip.text: qsTr("Keyboard shortcuts") + "  ·  ?"
            onClicked: helpDialog.open()
            background: Rectangle { radius: theme.radius; color: wordmark.down ? Qt.alpha(theme.foreground,.16) : wordmark.hovered ? Qt.alpha(theme.foreground,.09) : "transparent" }
            contentItem: Item {
              Row {
                id: mark
                anchors.centerIn: parent
                spacing: 7
                Text { anchors.verticalCenter: parent.verticalCenter; text: "♔"; color: window.tint; font.pixelSize: 17 }
                Text { anchors.verticalCenter: parent.verticalCenter; text: "Checkmate"; color: theme.foreground; font.family: "serif"; font.pixelSize: 17 }
              }
            }
          }
          // The four sets, each by its own sign, with a ring round the one on the board.
          RowLayout {
            spacing: 4
            Repeater {
              model: 4
              AbstractButton {
                id: swatch
                hoverEnabled: true
                required property int index
                objectName: "set-" + index
                implicitWidth: 26
                implicitHeight: 26
                focusPolicy: Qt.NoFocus
                Accessible.name: window.setNames[index]
                ToolTip.visible: hovered
                ToolTip.delay: 400
                ToolTip.text: { translator.language; return window.setNames[index] + "  ·  " + window.setDescriptions[index] + "  ·  " + (index + 1).toLocaleString(Qt.locale(),'f',0) }
                onClicked: backend.pieceSet = index
                background: Rectangle {
                  radius: theme.radius
                  color: swatch.down ? Qt.alpha(window.setColors[swatch.index],.26) : swatch.hovered ? Qt.alpha(theme.foreground,.09) : "transparent"
                  border.color: backend.pieceSet === swatch.index ? window.setColors[swatch.index] : "transparent"
                  border.width: 1.5
                }
                contentItem: Text {
                  text: ["◎","♞","❧","♛"][swatch.index]
                  color: window.setColors[swatch.index]
                  opacity: backend.pieceSet === swatch.index || swatch.hovered ? 1 : .7
                  font.pixelSize: 15
                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }
              }
            }
          }
        }
        // What the game has to say for itself: who is playing, and whose move it is. It sits dead centre while
        // there is room, and otherwise keeps to the gap between the two groups of buttons, whichever side each is on:
        // the players give way first, then the status shortens, and a save that is failing is always said in full.
        RowLayout {
          id: say
          objectName: "say"
          readonly property real from: Math.min(tools.x + tools.width,actions.x + actions.width) + 16
          readonly property real to: Math.max(tools.x,actions.x) - 16
          width: Math.max(0,Math.min(implicitWidth,to - from))
          x: Math.max(from,Math.min(parent.width / 2 - width / 2,to - width))
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10
          Text { text: backend.computer ? qsTr("Computer") + "  ·  " + window.difficultyNames[backend.difficulty] : qsTr("Two players"); color: window.muted; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true; Layout.minimumWidth: 0 }
          Text { objectName: "status"; text: window.statusText(); color: backend.checked ? theme.colors.red : theme.foreground; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true; Layout.minimumWidth: Math.min(implicitWidth,120) }
          Text { visible: !backend.saveHealthy; text: qsTr("Game is not being saved"); color: theme.colors.red; font.pixelSize: 12 }
        }
        RowLayout {
          id: actions
          anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
          spacing: 2
          FooterIcon { objectName: "movesButton"; name: qsTr("Moves"); key: "B"; path: "M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01"; lit: backend.movesOpen; onClicked: backend.movesOpen = !backend.movesOpen }
          FooterIcon { objectName: "undoButton"; name: qsTr("Undo"); key: "Ctrl+Z"; path: "M8 5L3.5 9.5L8 14M3.5 9.5H14a5 5 0 0 1 0 10h-3"; enabled: backend.canUndo; onClicked: backend.undo() }
          FooterIcon { objectName: "newGameButton"; name: qsTr("New game"); key: "N"; path: "M12 5v14M5 12h14"; lit: true; Layout.leftMargin: 4; Layout.rightMargin: 4; onClicked: newGameDialog.open() }
        }
      }
    }
    // The moves so far, laid over a corner of the board when asked for.
    Rectangle {
      objectName: "moves"
      visible: backend.movesOpen && window.chrome
      anchors { top: parent.top; right: parent.right; margins: 16 }
      width: 236
      height: Math.min(parent.height - 90, 58 + Math.max(2,history.count) * 35)
      radius: theme.radius
      color: Qt.alpha(theme.background,.9)
      border.color: window.line
      // A press on the list never falls through to the board beneath it.
      MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }
      ColumnLayout {
        anchors { fill: parent; margins: 14 }
        spacing: 10
        Text { text: qsTr("MOVE HISTORY"); color: window.muted; font.pixelSize: 10; font.letterSpacing: Qt.application.layoutDirection === Qt.RightToLeft ? 0 : 1.8 }
        ListView {
          id: history
          objectName: "history"
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: Math.ceil(backend.moves.length / 2)
          spacing: 3
          ScrollBar.vertical: ScrollBar { }
          onCountChanged: Qt.callLater(positionViewAtEnd)
          delegate: Rectangle {
            required property int index
            width: history.width
            height: 32
            color: index % 2 === 0 ? Qt.alpha(theme.foreground,.035) : "transparent"
            RowLayout {
              anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
              Text { text: { translator.language; return (index + 1).toLocaleString(Qt.locale(),'f',0) + "." } color: window.muted; Layout.preferredWidth: 30; font.pixelSize: 12 }
              Text { text: backend.moves[index * 2] || ""; color: theme.foreground; Layout.fillWidth: true; font.pixelSize: 13 }
              Text { text: backend.moves[index * 2 + 1] || "·"; color: theme.foreground; Layout.preferredWidth: 66; font.pixelSize: 13 }
            }
          }
          Text { anchors { top: parent.top; left: parent.left } visible: history.count === 0; text: qsTr("Every great game starts\nwith a single move."); color: window.muted; font.pixelSize: 12; lineHeight: 1.6 }
        }
      }
    }
    Rectangle {
      visible: backend.error.length > 0
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16; bottomMargin: window.chrome ? 58 : 16 }
      height: errorRow.implicitHeight + 28
      color: theme.background
      border.color: theme.colors.red
      radius: theme.radius
      RowLayout {
        id: errorRow
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
        Text { text: backend.error; color: theme.foreground; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        FlatButton { text: qsTr("Dismiss"); onClicked: backend.dismissError() }
      }
    }
  }
  Dialog {
    id: newGameDialog
    objectName: "newGameDialog"
    anchors.centerIn: parent
    width: 420
    modal: true
    focus: true
    title: qsTr("A new match")
    footer: DialogButtonBox {
      LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
      LayoutMirroring.childrenInherit: true
      Button { text: qsTr("Start game"); DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole; Material.roundedScale: theme.radius }
      Button { text: qsTr("Cancel"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole; Material.roundedScale: theme.radius }
      onAccepted: newGameDialog.accept()
      onRejected: newGameDialog.reject()
    }
    Material.roundedScale: theme.radius
    // The choices are in place before the dialog is seen, not after it has finished arriving.
    onAboutToShow: {
      mode.currentIndex = backend.computer ? 0 : 1
      level.currentIndex = backend.difficulty
      side.currentIndex = backend.humanWhite ? 0 : 1
    }
    onOpened: mode.forceActiveFocus()
    onAccepted: { backend.newGame(mode.currentIndex === 0,level.currentIndex,side.currentIndex === 0); board.resetCamera() }
    contentItem: ColumnLayout {
      LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
      LayoutMirroring.childrenInherit: true
      spacing: 16
      Label { text: backend.canUndo ? qsTr("Starting a new match replaces the saved game.") : qsTr("Choose your opponent and settle in."); wrapMode: Text.WordWrap; Layout.fillWidth: true }
      ComboBox { leftPadding: mirrored ? 40 : 16; rightPadding: mirrored ? 16 : 40; id: mode; objectName: "mode"; Layout.fillWidth: true; model: [qsTr("Play against the computer"),qsTr("Two players · same device")]; Material.roundedScale: theme.radius }
      ComboBox { leftPadding: mirrored ? 40 : 16; rightPadding: mirrored ? 16 : 40; id: level; Layout.fillWidth: true; model: window.difficultyNames; visible: mode.currentIndex === 0; Material.roundedScale: theme.radius }
      ComboBox { leftPadding: mirrored ? 40 : 16; rightPadding: mirrored ? 16 : 40; id: side; Layout.fillWidth: true; model: [qsTr("Play as White"),qsTr("Play as Black")]; visible: mode.currentIndex === 0; Material.roundedScale: theme.radius }
    }
  }
  Dialog {
    id: helpDialog
    objectName: "help"
    anchors.centerIn: parent
    width: 430
    modal: true
    focus: true
    title: qsTr("At your fingertips")
    footer: DialogButtonBox {
      LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
      LayoutMirroring.childrenInherit: true
      Button { text: qsTr("Close"); DialogButtonBox.buttonRole: DialogButtonBox.RejectRole; Material.roundedScale: theme.radius }
      onRejected: helpDialog.close()
    }
    Material.roundedScale: theme.radius
    contentItem: Label {
      LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
      text: qsTr("Click a piece, then a highlighted square.\n\nArrow keys  ·  Navigate the board\nSpace / Enter  ·  Select or move\nEscape  ·  Cancel selection\nCtrl+Z  ·  Undo\nN  ·  New game\nF  ·  Flip board\nR  ·  Reset camera\n1–4  ·  Piece set\nB  ·  Show or hide the moves\nTab  ·  Show or hide the interface\n?  ·  Keyboard shortcuts\nQ  ·  Quit (your game is saved)\n\nRight-drag to orbit. Scroll to zoom.")
      wrapMode: Text.WordWrap
      lineHeight: 1.4
    }
  }
  Dialog {
    id: promotionDialog
    objectName: "promotionDialog"
    anchors.centerIn: parent
    width: 420
    modal: true
    focus: true
    title: qsTr("Choose your promotion")
    closePolicy: Popup.CloseOnEscape
    Material.roundedScale: theme.radius
    onRejected: backend.cancelSelection()
    contentItem: RowLayout {
      LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
      LayoutMirroring.childrenInherit: true
      Repeater {
        model: [5,4,3,2]
        FlatButton {
          required property int modelData
          objectName: "promotion-" + modelData
          text: ["","","♘","♗","♖","♕"][modelData]
          font.pixelSize: 32
          Layout.fillWidth: true
          Accessible.name: modelData === 5 ? qsTr("Queen") : modelData === 4 ? qsTr("Rook") : modelData === 3 ? qsTr("Bishop") : qsTr("Knight")
          onClicked: { backend.promote(modelData); promotionDialog.close() }
        }
      }
    }
  }
  Connections {
    target: backend
    function onChanged() {
      if (backend.promotionPending && !promotionDialog.opened) promotionDialog.open()
      else if (!backend.promotionPending && promotionDialog.opened) promotionDialog.close()
    }
  }
  Shortcut { sequence: "?"; enabled: !window.modalOpen; onActivated: helpDialog.open() }
  Shortcut { sequence: "Q"; enabled: !window.modalOpen; onActivated: window.close() }
  Shortcut { sequence: "N"; enabled: !window.modalOpen; onActivated: newGameDialog.open() }
  Shortcut { sequences: [StandardKey.Undo]; enabled: !window.modalOpen; onActivated: backend.undo() }
  Shortcut { sequence: "F"; enabled: !window.modalOpen; onActivated: board.manualAzimuth += 180 }
  Shortcut { sequence: "1"; enabled: !window.modalOpen; onActivated: backend.pieceSet = 0 }
  Shortcut { sequence: "2"; enabled: !window.modalOpen; onActivated: backend.pieceSet = 1 }
  Shortcut { sequence: "3"; enabled: !window.modalOpen; onActivated: backend.pieceSet = 2 }
  Shortcut { sequence: "4"; enabled: !window.modalOpen; onActivated: backend.pieceSet = 3 }
  Shortcut { sequence: "B"; enabled: !window.modalOpen; onActivated: backend.movesOpen = !backend.movesOpen }
  Shortcut { sequence: "Tab"; enabled: !window.modalOpen; onActivated: window.chrome = !window.chrome }
  Shortcut { sequence: "R"; enabled: !window.modalOpen; onActivated: board.resetCamera() }
  Shortcut { sequence: "Escape"; enabled: !window.modalOpen; onActivated: backend.cancelSelection() }
  Shortcut { sequences: ["Space","Return","Enter"]; enabled: !window.modalOpen; onActivated: board.keyboardSelect() }
  Shortcut { sequence: "Left"; enabled: !window.modalOpen; onActivated: board.navigate(-1,0) }
  Shortcut { sequence: "Right"; enabled: !window.modalOpen; onActivated: board.navigate(1,0) }
  Shortcut { sequence: "Up"; enabled: !window.modalOpen; onActivated: board.navigate(0,1) }
  Shortcut { sequence: "Down"; enabled: !window.modalOpen; onActivated: board.navigate(0,-1) }
}

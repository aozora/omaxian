import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Shapes

ApplicationWindow {
  id: window
  width: 1280
  height: 850
  minimumWidth: 720
  minimumHeight: 540
  visible: true
  title: "Cards"
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
  property var seriesNames: [qsTr("Phosphor"),qsTr("Baize"),qsTr("Riso"),qsTr("Nocturne")]
  property var seriesDescriptions: [qsTr("Follows your theme"),qsTr("Felt, ivory & brass"),qsTr("Two inks on paper"),qsTr("Gold on a night sky")]
  property var seriesColors: [theme.accent,"#8fbf9f","#8ea6ff","#d9b872"]
  property color tint: seriesColors[backend.series]
  // How each series draws its cards and its table. Phosphor is made of the
  // Omarchy theme's own colors, so it changes with the theme; the others keep
  // theirs. Measures are for a card 112 wide.
  readonly property var looks: [
    {
      index: 0, radius: Math.min(theme.radius,12),
      table: theme.light ? Qt.darker(theme.background,1.08) : Qt.darker(theme.background,1.7),
      pattern: "dots", patternColor: Qt.alpha(theme.foreground,.12),
      face: theme.background, edge: Qt.tint(theme.background,Qt.alpha(theme.foreground,.32)), red: window.phosphorRed, black: theme.foreground,
      backFrame: theme.light ? Qt.darker(theme.background,1.04) : Qt.darker(theme.background,1.25),
      backFill: theme.light ? Qt.darker(theme.background,1.04) : Qt.darker(theme.background,1.25),
      backLine: Qt.alpha(theme.foreground,.2), backEdge: Qt.tint(theme.background,Qt.alpha(theme.foreground,.32)), backInset: 1 + Math.min(theme.radius,12) * .3,
      slot: Qt.alpha(theme.foreground,.26), slotWidth: 1, slotFill: "transparent", mark: Qt.alpha(theme.foreground,.26),
      ring: theme.accent, cursor: theme.foreground, shadow: "#59000000",
      family: "monospace", weight: Font.Bold, indexSize: 17, pipSize: 14, padX: 9, padY: 6,
      centreSize: 60, centreY: 52, centreOutline: true, bleed: false, disc: false, bottomIndex: false
    },
    {
      index: 1, radius: 9, table: "#1d4a38", pattern: "", patternColor: "transparent",
      face: "#f6efdd", edge: "#cbbd98", red: "#b0271f", black: "#1c1a17",
      backFrame: "#f6efdd", backFill: "#6e1f2a", backLine: "#47f6efdd", backEdge: "#cbbd98", backInset: 5,
      slot: "#99debe76", slotWidth: 1.5, slotFill: "#24000000", mark: "#80debe76",
      ring: "#f2c14e", cursor: "#ffffff", shadow: "#66000000",
      family: "serif", weight: Font.ExtraBold, indexSize: 20, pipSize: 14, padX: 9, padY: 3,
      centreSize: 50, centreY: 53, centreOutline: false, bleed: false, disc: false, bottomIndex: true
    },
    {
      index: 2, radius: 4, table: "#d3d9de", pattern: "", patternColor: "transparent",
      face: "#fbfaf6", edge: "#bfc4d0", red: "#cf3209", black: "#1b3bbb",
      backFrame: "#fbfaf6", backFill: "#1b3bbb", backLine: "#fbfaf6", backEdge: "#bfc4d0", backInset: 5,
      slot: "#521b3bbb", slotWidth: 2, slotFill: "transparent", mark: "#521b3bbb",
      ring: "#14151a", cursor: "#cf3209", shadow: "#cf3209",
      family: "sans-serif", weight: Font.Black, indexSize: 22, pipSize: 15, padX: 8, padY: 3,
      centreSize: 108, centreY: 0, centreOutline: false, bleed: true, disc: false, bottomIndex: false
    },
    {
      index: 3, radius: 10, table: "#111027", pattern: "stars", patternColor: "#ece7d5",
      face: "#1f1e44", edge: "#c9a961", red: "#f08f7e", black: "#ece7d5",
      backFrame: "#17163a", backFill: "#17163a", backLine: "#8cc9a961", backEdge: "#c9a961", backInset: 5,
      slot: "#73c9a961", slotWidth: 1, slotFill: "#b3111027", mark: "#80c9a961",
      ring: "#f4dc9c", cursor: "#ffffff", shadow: "#80000000",
      family: "serif", weight: Font.Bold, indexSize: 24, pipSize: 13, padX: 10, padY: 1,
      centreSize: 40, centreY: 60, centreOutline: false, bleed: false, disc: true, bottomIndex: false
    }
  ]
  // Phosphor's hearts and diamonds take the accent, unless a theme's accent is
  // too near its text or its background to tell the suits apart; then the
  // theme's red, orange, magenta, or blue stands in, whichever first stands out.
  readonly property color phosphorRed: {
    const apart = (a, b) => Math.abs(a.r - b.r) + Math.abs(a.g - b.g) + Math.abs(a.b - b.b)
    const candidates = [theme.accent, theme.colors.red, theme.colors.orange, theme.colors.magenta, theme.colors.blue]
    for (const candidate of candidates)
      if (candidate !== undefined && apart(candidate, theme.foreground) > .45 && apart(candidate, theme.background) > .45) return candidate
    return theme.accent
  }
  // Every shortcut, for the overlay: the keys stay as they are on the keyboard, the rest is translated.
  readonly property var shortcuts: [
    { keys: ["←","→","↑","↓"], text: qsTr("Move around the table") },
    { keys: ["Space","Enter"], text: qsTr("Pick up or put down") },
    { keys: ["F"], text: qsTr("Send to the best place") },
    { keys: ["D"], text: qsTr("Draw from the stock") },
    { keys: ["Esc"], text: qsTr("Put the cards back") },
    { keys: ["H"], text: qsTr("Hint") },
    { keys: ["Ctrl","Z"], text: qsTr("Undo") },
    { keys: ["N"], text: qsTr("New game") },
    { keys: ["1","2","3","4"], text: qsTr("Card series") },
    { keys: ["?"], text: qsTr("Keyboard shortcuts") },
    { keys: ["Q"], text: qsTr("Quit (your game is saved)") }
  ]
  // Single keys wait while the shortcuts are up or cards are in the hand.
  property bool busy: helpDialog.visible || table.dragging
  // The clock stops while another window is in front.
  onActiveChanged: backend.active = active
  Component.onCompleted: backend.active = active
  function whole(number) {
    translator.language
    return number.toLocaleString(Qt.locale(),'f',0)
  }
  function clock(seconds) {
    const two = (number) => (number < 10 ? whole(0) : "") + whole(number)
    const minutes = two(Math.floor(seconds % 3600 / 60)) + ":" + two(seconds % 60)
    return seconds >= 3600 ? whole(Math.floor(seconds / 3600)) + ":" + minutes : minutes
  }
  component FlatButton: Button {
    id: control
    // Asked for outright: left to the platform, hover and so the tooltip can be off.
    hoverEnabled: true
    property bool lit: false
    implicitHeight: 38
    topInset: 0; bottomInset: 0; leftInset: 0; rightInset: 0
    focusPolicy: Qt.NoFocus
    background: Rectangle {
      radius: theme.radius
      color: control.down ? Qt.alpha(window.tint,.26) : control.lit ? Qt.alpha(window.tint,control.hovered ? .22 : .13) : control.hovered ? Qt.alpha(theme.foreground,.09) : "transparent"
      border.color: control.lit ? Qt.alpha(window.tint,.5) : window.line
    }
    contentItem: Text {
      text: control.text
      color: control.enabled ? theme.foreground : window.muted
      opacity: control.enabled ? 1 : .5
      font: control.font
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
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
    // Asked for outright: left to the platform, hover and so the tooltip can be off.
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
  // A number with an icon saying what it counts, and the word for it on hover.
  // The number is given the room of its widest self, in digits of one width,
  // so nothing beside it moves as it counts.
  component Stat: Row {
    id: stat
    property string path
    property string name
    property string value
    // The longest text the number is expected to reach.
    property string reserve
    spacing: 6
    Accessible.name: name + " " + value
    Glyph { anchors.verticalCenter: parent.verticalCenter; path: stat.path; ink: window.muted }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(room.advanceWidth, implicitWidth)
      text: stat.value
      color: theme.foreground
      font.pixelSize: 12
      font.features: { "tnum": 1 }
      TextMetrics { id: room; text: stat.reserve; font.pixelSize: 12; font.features: { "tnum": 1 } }
    }
    HoverHandler { id: over }
    ToolTip.visible: over.hovered
    ToolTip.delay: 400
    ToolTip.text: name
  }
  Item {
    anchors.fill: parent
    LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true
    ColumnLayout {
      anchors.fill: parent
      spacing: 0
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        CardTable { id: table; objectName: "table"; anchors.fill: parent; look: window.looks[backend.series] }
        Rectangle {
          objectName: "wonPanel"
          visible: backend.won
          anchors.centerIn: parent
          width: Math.min(parent.width - 48, 380)
          height: wonColumn.implicitHeight + 56
          color: theme.background
          radius: theme.radius
          border.color: Qt.alpha(window.tint,.6)
          ColumnLayout {
            id: wonColumn
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 28 }
            spacing: 12
            Text { text: qsTr("Every card is home"); color: theme.foreground; font.family: "serif"; font.pixelSize: 27; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignHCenter; Layout.fillWidth: true }
            Text { text: qsTr("%1 moves in %2").arg(window.whole(backend.moves)).arg(window.clock(backend.elapsed)); color: window.muted; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            FlatButton { objectName: "dealAgainButton"; text: qsTr("Deal again"); lit: true; Layout.fillWidth: true; Layout.topMargin: 8; onClicked: backend.newGame() }
          }
        }
      }
      // Everything that isn't a card, in one slim line under the table.
      Rectangle {
        objectName: "footer"
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        color: theme.background
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: window.line }
        // The top edge fills in as the cards go home.
        Rectangle { anchors { left: parent.left; top: parent.top } height: 2; width: parent.width * backend.home / 52; color: window.tint }
        // The name is also the way to the shortcuts.
        RowLayout {
          anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
          spacing: 12
          AbstractButton {
            id: wordmark
            // Asked for outright: left to the platform, hover and so the tooltip can be off.
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
                Suit { anchors.verticalCenter: parent.verticalCenter; suit: 0; color: window.tint; size: 15 }
                Text { text: "Cards"; color: theme.foreground; font.family: "serif"; font.pixelSize: 17 }
              }
            }
          }
          RowLayout {
            spacing: 7
            Repeater {
              model: 4
              // A very small ace of spades in each series' own hand.
              AbstractButton {
                id: swatch
                // Asked for outright: left to the platform, hover and so the tooltip can be off.
                hoverEnabled: true
                required property int index
                readonly property var look: window.looks[index]
                objectName: "series-" + index
                implicitWidth: 16
                implicitHeight: 22
                focusPolicy: Qt.NoFocus
                Accessible.name: window.seriesNames[index]
                ToolTip.visible: hovered
                ToolTip.delay: 400
                ToolTip.text: window.seriesNames[index] + "  ·  " + window.seriesDescriptions[index] + "  ·  " + window.whole(index + 1)
                onClicked: backend.series = index
                background: Item {
                  Rectangle {
                    visible: backend.series === swatch.index
                    anchors.fill: parent
                    anchors.margins: -3
                    radius: swatch.look.radius * .25 + 3
                    color: "transparent"
                    border.color: window.seriesColors[swatch.index]
                    border.width: 1.5
                  }
                  Rectangle {
                    anchors.fill: parent
                    radius: swatch.look.radius * .25
                    color: swatch.look.face
                    border.color: swatch.look.edge
                    Suit { anchors.centerIn: parent; suit: 0; color: swatch.look.black; outline: swatch.look.centreOutline; stroke: 2.2; size: 10 }
                  }
                }
              }
            }
          }
        }
        // What the game has to say for itself: the clock dead centre, the moves
        // before it and the stock after, each held at a fixed distance from the
        // middle so none of them shifts as the others count.
        Item {
          objectName: "stats"
          anchors.centerIn: parent
          width: 280
          height: parent.height
          visible: !backend.stuck
          Stat {
            objectName: "movesStat"; name: qsTr("Moves"); value: window.whole(backend.moves); path: "M4 8h13M13 4l4 4-4 4M20 16H7M11 12l-4 4 4 4"
            reserve: window.whole(8888)
            anchors { right: parent.horizontalCenter; rightMargin: 52; verticalCenter: parent.verticalCenter }
          }
          Stat {
            objectName: "timeStat"; name: qsTr("Time"); value: window.clock(backend.elapsed); path: "M21 12a9 9 0 1 1-18 0a9 9 0 1 1 18 0ZM12 7v5l3.2 2"
            reserve: backend.elapsed >= 3600 ? window.clock(8 * 3600 + 88 * 60 + 28) : window.clock(88 * 60 + 28)
            anchors.centerIn: parent
          }
          Stat {
            objectName: "stockStat"; name: qsTr("Stock"); value: window.whole(backend.stock); path: "M9 4h9a2 2 0 0 1 2 2v11M5 8h10a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"
            reserve: window.whole(88)
            anchors { left: parent.horizontalCenter; leftMargin: 52; verticalCenter: parent.verticalCenter }
          }
        }
        // A hint that found nothing says so in their place. It says only that:
        // the hints look for moves that lead somewhere, not for every move there is.
        Text {
          objectName: "status"
          visible: backend.stuck
          anchors.centerIn: parent
          text: qsTr("Nothing more to suggest. Undo, or deal again.")
          color: theme.foreground
          font.pixelSize: 12
        }
        RowLayout {
          anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
          spacing: 2
          // Shown for as long as nothing is being written, whether or not the reason was dismissed.
          Item {
            objectName: "unsavedMark"
            visible: !backend.saveHealthy
            implicitWidth: 30
            implicitHeight: 26
            Accessible.name: qsTr("Game is not being saved")
            Glyph { anchors.centerIn: parent; path: "M12 4L21 20H3ZM12 10v5M12 17.6v.1"; ink: theme.colors.red }
            HoverHandler { id: overUnsaved }
            ToolTip.visible: overUnsaved.hovered
            ToolTip.delay: 400
            ToolTip.text: qsTr("Game is not being saved")
          }
          FooterIcon { objectName: "undoButton"; name: qsTr("Undo"); key: "Ctrl+Z"; path: "M8 5L3.5 9.5L8 14M3.5 9.5H14a5 5 0 0 1 0 10h-3"; enabled: backend.canUndo; onClicked: backend.undo() }
          FooterIcon { objectName: "hintButton"; name: qsTr("Hint"); key: "H"; path: "M9 17.5h6M10 20.5h4M8.5 14a6 6 0 1 1 7 0c-.6.5-.9 1.1-1 2h-5c-.1-.9-.4-1.5-1-2Z"; enabled: !backend.won; onClicked: backend.hint() }
          FooterIcon { objectName: "newGameButton"; name: qsTr("New game"); key: "N"; path: "M12 5v14M5 12h14"; lit: true; Layout.leftMargin: 4; Layout.rightMargin: 4; onClicked: backend.newGame() }
        }
      }
    }
    Rectangle {
      visible: backend.error.length > 0
      anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16; bottomMargin: 58 }
      height: errorRow.implicitHeight + 28
      color: theme.background
      border.color: theme.colors.red
      radius: theme.radius
      RowLayout {
        id: errorRow
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
        Text { text: backend.error; color: theme.foreground; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        FlatButton { text: qsTr("Dismiss"); leftPadding: 14; rightPadding: 14; onClicked: backend.dismissError() }
      }
    }
  }
  Dialog {
    id: helpDialog
    objectName: "help"
    anchors.centerIn: parent
    width: 480
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
    background: Rectangle { color: theme.background; radius: theme.radius; border.color: Qt.alpha(theme.foreground,.22) }
    contentItem: ColumnLayout {
      LayoutMirroring.enabled: Qt.application.layoutDirection === Qt.RightToLeft
      LayoutMirroring.childrenInherit: true
      spacing: 0
      Label {
        text: qsTr("Click a card, then where it goes, or drag it. A double click sends it to the best place.")
        color: window.muted
        wrapMode: Text.WordWrap
        lineHeight: 1.3
        Layout.fillWidth: true
        Layout.bottomMargin: 14
      }
      // One row per shortcut: its keys as caps in a column of their own, then what they do.
      Repeater {
        model: window.shortcuts
        Rectangle {
          id: shortcut
          required property var modelData
          required property int index
          objectName: "shortcut-" + index
          Layout.fillWidth: true
          implicitHeight: 34
          color: "transparent"
          Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: window.line }
          RowLayout {
            anchors.fill: parent
            spacing: 16
            Item {
              Layout.preferredWidth: 150
              Layout.fillHeight: true
              // Keys keep their order as pressed, Ctrl before Z, in every language.
              Row {
                LayoutMirroring.enabled: false
                anchors.verticalCenter: parent.verticalCenter
                x: Qt.application.layoutDirection === Qt.RightToLeft ? parent.width - width : 0
                spacing: 5
                Repeater {
                  model: shortcut.modelData.keys
                  Rectangle {
                    required property string modelData
                    width: Math.max(24, cap.implicitWidth + 14)
                    height: 22
                    radius: Math.min(4, theme.radius)
                    color: Qt.alpha(theme.foreground,.07)
                    border.color: window.line
                    Text { id: cap; anchors.centerIn: parent; text: parent.modelData; color: theme.foreground; font.family: "monospace"; font.pixelSize: 12 }
                  }
                }
              }
            }
            Label { text: shortcut.modelData.text; elide: Text.ElideRight; Layout.fillWidth: true }
          }
        }
      }
    }
  }
  Shortcut { sequence: "?"; enabled: !window.busy; onActivated: helpDialog.open() }
  Shortcut { sequence: "Q"; enabled: !window.busy; onActivated: window.close() }
  Shortcut { sequence: "N"; enabled: !window.busy; onActivated: backend.newGame() }
  Shortcut { sequences: [StandardKey.Undo]; enabled: !window.busy; onActivated: backend.undo() }
  Shortcut { sequence: "H"; enabled: !window.busy; onActivated: backend.hint() }
  Shortcut { sequence: "D"; enabled: !window.busy; onActivated: backend.draw() }
  Shortcut { sequence: "F"; enabled: !window.busy; onActivated: table.keyboardSend() }
  Shortcut { sequence: "1"; enabled: !window.busy; onActivated: backend.series = 0 }
  Shortcut { sequence: "2"; enabled: !window.busy; onActivated: backend.series = 1 }
  Shortcut { sequence: "3"; enabled: !window.busy; onActivated: backend.series = 2 }
  Shortcut { sequence: "4"; enabled: !window.busy; onActivated: backend.series = 3 }
  // Escape also lets go of cards being dragged, back where they were.
  Shortcut { sequence: "Escape"; enabled: !helpDialog.visible; onActivated: { table.cancelDrag(); backend.cancelSelection() } }
  Shortcut { sequences: ["Space","Return","Enter"]; enabled: !window.busy; onActivated: table.keyboardSelect() }
  Shortcut { sequence: "Left"; enabled: !window.busy; onActivated: table.navigate(-1,0) }
  Shortcut { sequence: "Right"; enabled: !window.busy; onActivated: table.navigate(1,0) }
  Shortcut { sequence: "Up"; enabled: !window.busy; onActivated: table.navigate(0,-1) }
  Shortcut { sequence: "Down"; enabled: !window.busy; onActivated: table.navigate(0,1) }
}

import QtQuick
import QtQuick3D
import Checkmate 1.0

Node {
  id: piece
  objectName: "figure-" + pieceId
  required property int pieceId
  required property var record
  required property int design
  required property bool motion
  required property bool selected
  required property real seat
  // The scene's shared surfaces: the set's own, and Atelier's pale wood.
  required property Texture grain
  required property Texture paleGrain
  property real lift: 0
  // Followed by hand, like `place`, so a capture can be timed to its captor's arrival.
  property bool alive: record.alive
  property real presence: 0
  property int reprieve: 0
  property bool ready: false
  // Moss & Myth is one carved figure per piece, painted in its mesh rather than by part.
  property bool woodland: design === 2
  property color bodyColor: design === 0 ? (record.white ? "#e2d8c2" : "#343a44")
                            : design === 1 ? (record.white ? "#eed8aa" : "#59321b")
                            : design === 2 ? "#ffffff"
                            : (record.white ? "#f7949b" : "#9a5fa6")
  property color trimColor: design === 0 ? "#b99050" : design === 1 ? "#c89b51" : "#f2c653"
  property color secondaryColor: design === 0 ? (record.white ? "#52cdd0" : "#ffb84d")
                                 : design === 1 ? (record.white ? "#c8ac7e" : "#362115")
                                 : (record.white ? "#d25a82" : "#7b4a9c")
  // Sugar passes light through itself, so candy never falls into dark shadow: each sweet glows faintly in its own colour.
  property bool candy: design === 3
  property vector3d sugarGlow: !candy ? Qt.vector3d(0,0,0) : record.white ? Qt.vector3d(.24,.085,.095) : Qt.vector3d(.105,.05,.125)
  property vector3d secondGlow: design === 0 ? (record.white ? Qt.vector3d(.22,.95,1.05) : Qt.vector3d(1.25,.55,.08))
                                : !candy ? Qt.vector3d(0,0,0) : record.white ? Qt.vector3d(.15,.03,.06) : Qt.vector3d(.06,.025,.1)
  // Each set moves in its own manner. Orbital craft hover, bank into a glide and scan with their lights up. Atelier's pieces
  // are handled: tilted in unseen fingers, carried over, set down with a rock, and tipped over when taken. The woodland
  // creatures breathe, look and leap. The sweets wobble like jelly and pop.
  required property real clock
  required property int attention
  readonly property var manners: [
    { breath: 0, bulge: 0, sway: 0, hover: .035, drift: .02, raise: .2, raiseTime: 380, spring: false, bob: .06, pinch: 0,
      windup: 0, crouch: 1, stretch: 1, squash: 1, lean: 11, counter: -6, dip: .03, settle: Easing.OutCubic, settleTime: 320, glide: Easing.InOutCubic,
      arc: .04, arcPer: .01, arcMax: .1, knightArc: .45, pace: 340, pacePer: 60, start: 1, reach: 1, shake: 20, shakeTime: 170,
      look: 9, glance: 14, skip: 0, fade: 320, pop: false, twirl: 0, topple: 0 },
    { breath: 0, bulge: 0, sway: 0, hover: 0, drift: 0, raise: .14, raiseTime: 220, spring: false, bob: 0, pinch: 3.5,
      windup: 0, crouch: 1, stretch: 1, squash: 1, lean: 5, counter: -4, dip: 0, settle: Easing.OutElastic, settleTime: 650, glide: Easing.InOutCubic,
      arc: .16, arcPer: .03, arcMax: .34, knightArc: .5, pace: 320, pacePer: 45, start: 1, reach: 1, shake: 0, shakeTime: 100,
      look: 0, glance: 0, skip: 0, fade: 380, pop: false, twirl: 0, topple: 80 },
    { breath: .011, bulge: .6, sway: 1.2, hover: 0, drift: 0, raise: .17, raiseTime: 300, spring: true, bob: .1, pinch: 0,
      windup: 70, crouch: .9, stretch: 1.07, squash: .88, lean: 9, counter: -5, dip: 0, settle: Easing.OutBack, settleTime: 320, glide: Easing.InOutSine,
      arc: .12, arcPer: .04, arcMax: .36, knightArc: .55, pace: 300, pacePer: 50, start: .93, reach: 1.08, shake: 9, shakeTime: 110,
      look: 20, glance: 15, skip: .07, fade: 300, pop: false, twirl: 160, topple: 0 },
    { breath: .014, bulge: .9, sway: .6, hover: 0, drift: 0, raise: .17, raiseTime: 320, spring: true, bob: .12, pinch: 0,
      windup: 80, crouch: .84, stretch: 1.1, squash: .8, lean: 6, counter: -3, dip: 0, settle: Easing.OutElastic, settleTime: 560, glide: Easing.InOutSine,
      arc: .16, arcPer: .04, arcMax: .4, knightArc: .6, pace: 320, pacePer: 50, start: .88, reach: 1.13, shake: 0, shakeTime: 100,
      look: 12, glance: 0, skip: .05, fade: 280, pop: true, twirl: 0, topple: 0 }
  ]
  readonly property var manner: manners[design]
  property int square: record.square
  // The figure shown. A promoting pawn stays a pawn until it lands, then becomes what it was promoted to.
  property int kind: record.kind
  property int shownKind: 1
  onKindChanged: Qt.callLater(function() { if (!leap.running) piece.shownKind = piece.kind })
  // A figure taken off the board is not drawn at all, rather than drawn at no size.
  visible: presence > 0
  // Where the figure stands. It follows `square` by hand so a journey is measured before the slide starts.
  property int place: 0
  property int travel: 360
  property real raise: selected ? manner.raise : 0
  property real held: raise / manner.raise
  property real stretch: 1
  property real lean: 0
  property real leanX: 0
  property real leanZ: 0
  property real wiggle: 0
  // Idle life pauses with the clock when the window is left, and is gone altogether under reduced motion.
  property real vigor: backend.reducedMotion ? 0 : 1
  // A tree stump stirs far less than the creatures around it.
  property real liveliness: woodland && record.kind === 4 ? .3 : 1
  property real phase: pieceId * 2.399
  property real breath: vigor * liveliness * Math.sin(clock * (1.5 + pieceId % 5 * .11) + phase)
  property real tall: stretch * (1 + manner.breath * breath * (1 + raise * 6))
  property real wide: 1 + (1 - tall) * manner.bulge
  // A piece in the fingers tips toward the player and is never held quite still.
  property real tilt: held * manner.pinch * (1 + vigor * .35 * Math.sin(clock * 1.7 + phase))
  // Orbital lights idle at a slow pulse, come up in the hand and when a neighbour is chosen, and go out with a capture.
  property real pulse: design === 0 ? presence * (1 + vigor * .2 * Math.sin(clock * 1.3 + phase) + held * .9 + Math.abs(look) / 18) : 1
  // Every figure faces whoever is seated at the board. Knights turn in toward its middle: the foxes
  // a little, the horses far enough to show their profile.
  property real knightTurn: woodland ? 32 : 58
  property real facing: 180 + seat + (record.kind === 2 ? (pieceId % 2 ? knightTurn : -knightTurn) * Math.cos(seat * Math.PI / 180) : 0)
  // Neighbours turn part of the way toward the figure in hand; one standing behind them is left alone.
  property real look: regard()
  function regard() {
    if (!motion || attention < 0 || selected || !record.alive) return 0
    let dx = attention % 8 - place % 8, dz = Math.floor(place / 8) - Math.floor(attention / 8)
    let reach = Math.hypot(dx, dz)
    if (reach < .5 || reach > 3.3) return 0
    return manner.look * liveliness * Math.sin(Math.atan2(-dx, -dz) - facing * Math.PI / 180) * Math.min(1, (3.3 - reach) / 2)
  }
  x: place % 8 - 3.5
  z: 3.5 - Math.floor(place / 8)
  y: .12 + manner.hover + vigor * manner.drift * Math.sin(clock * .9 + phase) + lift + raise * (1 + vigor * manner.bob * Math.sin(clock * 3.1 + phase))
  scale: Qt.vector3d(presence * wide, presence * tall, presence * wide)
  // A captured woodland figure twirls as it goes; a captured Atelier piece is tipped onto its side.
  eulerRotation.y: facing + wiggle + look + vigor * liveliness * manner.sway * Math.sin(clock * .7 + phase * 1.7) + (1 - presence) * manner.twirl
  eulerRotation.x: lean * leanZ + tilt
  eulerRotation.z: -lean * leanX + Math.min(1, (1 - presence) * 2.2) * manner.topple * (pieceId % 2 ? 1 : -1)
  Behavior on x {
    id: xBehavior; enabled: piece.ready && piece.motion
    SequentialAnimation {
      PauseAnimation { duration: piece.manner.windup }
      NumberAnimation { duration: piece.travel; easing.type: piece.manner.glide }
    }
  }
  Behavior on z {
    id: zBehavior; enabled: piece.ready && piece.motion
    SequentialAnimation {
      PauseAnimation { duration: piece.manner.windup }
      NumberAnimation { duration: piece.travel; easing.type: piece.manner.glide }
    }
  }
  Behavior on raise {
    id: raiseBehavior; enabled: piece.ready && piece.motion
    NumberAnimation { duration: piece.manner.raiseTime; easing.type: piece.manner.spring && piece.selected ? Easing.OutBack : Easing.OutCubic }
  }
  Behavior on look {
    id: lookBehavior; enabled: piece.ready && piece.motion
    SequentialAnimation {
      PauseAnimation { duration: piece.pieceId * 53 % 140 }
      NumberAnimation { duration: 380; easing.type: piece.manner.spring ? Easing.OutBack : Easing.InOutCubic }
    }
  }
  // The captured figure waits for its captor to arrive. A sweet swells before it pops.
  Behavior on presence {
    id: presenceBehavior; enabled: piece.ready && piece.motion
    SequentialAnimation {
      PauseAnimation { duration: piece.reprieve }
      NumberAnimation { duration: piece.manner.fade; easing.type: piece.manner.pop && !piece.record.alive ? Easing.InBack : Easing.InCubic }
    }
  }
  onMotionChanged: {
    if (!motion) {
      xBehavior.enabled = false; zBehavior.enabled = false
      raiseBehavior.enabled = false; lookBehavior.enabled = false; presenceBehavior.enabled = false
      compose()
      // Resolve moves queued before the first animation frame as well.
      x = Qt.binding(function() { return piece.place % 8 - 3.5 })
      z = Qt.binding(function() { return 3.5 - Math.floor(piece.place / 8) })
      raise = Qt.binding(function() { return piece.selected ? piece.manner.raise : 0 })
      look = Qt.binding(function() { return piece.regard() })
      presence = alive ? 1 : 0
      xBehavior.enabled = Qt.binding(function() { return piece.ready && piece.motion })
      zBehavior.enabled = Qt.binding(function() { return piece.ready && piece.motion })
      raiseBehavior.enabled = Qt.binding(function() { return piece.ready && piece.motion })
      lookBehavior.enabled = Qt.binding(function() { return piece.ready && piece.motion })
      presenceBehavior.enabled = Qt.binding(function() { return piece.ready && piece.motion })
    }
  }
  onSquareChanged: {
    if (ready && motion && record.alive) {
      let dx = square % 8 - 3.5 - x, dz = 3.5 - Math.floor(square / 8) - z, reach = Math.hypot(dx, dz)
      if (reach > .01) {
        // Further is slower and higher; knights clear whatever stands between.
        travel = Math.min(manner.pace + 320, manner.pace + manner.pacePer * reach)
        leap.height = record.kind === 2 ? manner.knightArc : Math.min(manner.arcMax, manner.arc + manner.arcPer * reach)
        // The figure leans along its path, which is turned into its own frame.
        let turn = eulerRotation.y * Math.PI / 180
        leanX = (dx * Math.cos(turn) - dz * Math.sin(turn)) / reach
        leanZ = (dx * Math.sin(turn) + dz * Math.cos(turn)) / reach
        // The journey takes over whatever pose an interrupted stir left behind.
        perk.stop(); skip.stop(); glance.stop()
        leap.restart()
      }
    }
    place = square
  }
  onAliveChanged: {
    // The captor's journey is the last move's; the taken figure starts to go just before it lands.
    let from = backend.lastFrom, to = backend.lastTo
    let reach = from < 0 ? 0 : Math.hypot(to % 8 - from % 8, Math.floor(to / 8) - Math.floor(from / 8))
    reprieve = alive ? 0 : Math.max(0, manner.windup + Math.min(manner.pace + 320, manner.pace + manner.pacePer * reach) - manner.fade * .4)
    presence = alive ? 1 : 0
  }
  onSelectedChanged: if (selected && motion && ready) { skip.stop(); glance.stop(); perk.restart() }
  // A new set starts from rest rather than finishing the last one's gesture.
  onDesignChanged: compose()
  Component.onCompleted: { place = square; shownKind = kind; presence = alive ? 1 : 0; ready = true }
  function compose() {
    leap.stop(); perk.stop(); glance.stop(); skip.stop()
    lift = 0; stretch = 1; lean = 0; wiggle = 0
  }
  // Now and then the board asks an idle figure to stir: a look to one side, or a small skip from the sweets, the young and the foxes.
  function fidget() {
    if (!motion || !record.alive || liveliness < 1 || selected || look !== 0) return
    if (leap.running || perk.running || glance.running || skip.running) return
    if (manner.skip > 0 && (manner.glance === 0 || (record.kind <= 2 && Math.random() < .4))) skip.restart()
    else if (manner.glance > 0) { glance.side = Math.random() < .5 ? -1 : 1; glance.restart() }
  }
  // The journey: a crouch where the set has one, an arc leaning into the way ahead, and a landing that settles in character.
  SequentialAnimation {
    id: leap
    objectName: "leap"
    onRunningChanged: if (!running) piece.shownKind = piece.kind
    property real height: .2
    NumberAnimation { target: piece; property: "stretch"; to: piece.manner.crouch; duration: piece.manner.windup; easing.type: Easing.OutQuad }
    ParallelAnimation {
      SequentialAnimation {
        NumberAnimation { target: piece; property: "lift"; to: leap.height; duration: piece.travel * .5; easing.type: Easing.OutQuad }
        NumberAnimation { target: piece; property: "lift"; to: 0; duration: piece.travel * .5; easing.type: Easing.InQuad }
      }
      SequentialAnimation {
        NumberAnimation { target: piece; property: "stretch"; to: piece.manner.stretch; duration: piece.travel * .3; easing.type: Easing.OutQuad }
        NumberAnimation { target: piece; property: "stretch"; to: 1; duration: piece.travel * .7 }
      }
      SequentialAnimation {
        NumberAnimation { target: piece; property: "lean"; to: piece.manner.lean; duration: piece.travel * .35; easing.type: Easing.OutQuad }
        NumberAnimation { target: piece; property: "lean"; to: piece.manner.counter; duration: piece.travel * .65; easing.type: Easing.InOutQuad }
      }
      NumberAnimation { target: piece; property: "wiggle"; to: 0; duration: piece.travel * .5; easing.type: Easing.OutQuad }
    }
    ParallelAnimation {
      SequentialAnimation {
        NumberAnimation { target: piece; property: "stretch"; to: piece.manner.squash; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: piece; property: "stretch"; to: 1; duration: piece.manner.settleTime; easing.type: piece.manner.settle }
      }
      NumberAnimation { target: piece; property: "lean"; to: 0; duration: piece.manner.settleTime; easing.type: piece.manner.settle }
      // A hovering craft sinks a little under its own arrival.
      SequentialAnimation {
        NumberAnimation { target: piece; property: "lift"; to: -piece.manner.dip; duration: 130; easing.type: Easing.OutQuad }
        NumberAnimation { target: piece; property: "lift"; to: 0; duration: 260; easing.type: Easing.InOutQuad }
      }
    }
  }
  // Picked up: a start and a stretch, then a shake of the head or a scan to either side.
  ParallelAnimation {
    id: perk
    objectName: "perk"
    NumberAnimation { target: piece; property: "lift"; to: 0; duration: 150; easing.type: Easing.OutQuad }
    SequentialAnimation {
      NumberAnimation { target: piece; property: "stretch"; to: piece.manner.start; duration: 70; easing.type: Easing.OutQuad }
      NumberAnimation { target: piece; property: "stretch"; to: piece.manner.reach; duration: 150; easing.type: Easing.OutQuad }
      NumberAnimation { target: piece; property: "stretch"; to: 1; duration: piece.manner.settleTime; easing.type: piece.manner.settle }
    }
    SequentialAnimation {
      PauseAnimation { duration: 120 }
      NumberAnimation { target: piece; property: "wiggle"; to: piece.manner.shake; duration: piece.manner.shakeTime; easing.type: Easing.InOutSine }
      NumberAnimation { target: piece; property: "wiggle"; to: -piece.manner.shake * .8; duration: piece.manner.shakeTime * 1.4; easing.type: Easing.InOutSine }
      NumberAnimation { target: piece; property: "wiggle"; to: 0; duration: piece.manner.shakeTime * 2; easing.type: piece.manner.spring ? Easing.OutBack : Easing.InOutCubic }
    }
  }
  SequentialAnimation {
    id: glance
    property int side: 1
    NumberAnimation { target: piece; property: "wiggle"; to: glance.side * piece.manner.glance; duration: 380; easing.type: Easing.InOutSine }
    PauseAnimation { duration: 500 }
    NumberAnimation { target: piece; property: "wiggle"; to: 0; duration: 520; easing.type: Easing.InOutSine }
  }
  ParallelAnimation {
    id: skip
    SequentialAnimation {
      NumberAnimation { target: piece; property: "lift"; to: piece.manner.skip; duration: 130; easing.type: Easing.OutQuad }
      NumberAnimation { target: piece; property: "lift"; to: 0; duration: 170; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
      NumberAnimation { target: piece; property: "stretch"; to: 1.05; duration: 130 }
      NumberAnimation { target: piece; property: "stretch"; to: .94; duration: 170 }
      NumberAnimation { target: piece; property: "stretch"; to: 1; duration: piece.manner.settleTime; easing.type: piece.manner.settle }
    }
  }
  Model {
    objectName: "piece-" + piece.pieceId
    property int boardSquare: piece.record.square
    pickable: piece.record.alive
    geometry: sculptures.geometry(piece.design,piece.shownKind,0,piece.record.white ? 0 : 1)
    // Ceramic or gunmetal, polished wood, painted carving, boiled sugar.
    materials: PrincipledMaterial {
      baseColorMap: piece.woodland ? null : piece.design === 1 && piece.record.white ? piece.paleGrain : piece.grain
      baseColor: piece.bodyColor
      vertexColorsEnabled: true
      metalness: piece.design === 0 ? (piece.record.white ? .2 : .5) : 0
      roughness: piece.candy ? .24 : piece.design === 1 ? .34 : piece.design === 0 ? (piece.record.white ? .3 : .36) : .7
      specularAmount: piece.woodland ? .3 : .5
      // Polished wood keeps its mirror for the lights it faces; the glancing sheen is held to the very edge.
      fresnelPower: piece.design === 1 ? 8 : 5
      // A full lacquer mirrors the dark of the room at every grazing edge, so the sweets wear only a light glaze.
      clearcoatAmount: piece.woodland ? 0 : piece.design === 0 ? .2 : .35
      clearcoatRoughnessAmount: piece.design === 1 ? .14 : piece.candy ? .08 : .2
      // A sweet warms a little in the hand.
      emissiveFactor: piece.sugarGlow.times(1 + piece.held * .6)
      cullMode: Material.NoCulling
    }
  }
  // The cast sets add metalwork, dark inlay and a second colour, each a solid of its own.
  Model {
    property int boardSquare: piece.record.square
    pickable: piece.record.alive
    visible: !piece.woodland
    geometry: sculptures.geometry(piece.design,piece.shownKind,1,0)
    materials: PrincipledMaterial {
      baseColor: piece.trimColor
      vertexColorsEnabled: true
      // Gold leaf on a sweet is warmer and softer than cast metal.
      metalness: piece.candy ? .6 : .9
      roughness: piece.candy ? .3 : .26
      emissiveFactor: piece.candy ? Qt.vector3d(.12,.08,.015) : Qt.vector3d(0,0,0)
      cullMode: Material.NoCulling
    }
  }
  Model {
    property int boardSquare: piece.record.square
    pickable: piece.record.alive
    visible: !piece.woodland
    geometry: sculptures.geometry(piece.design,piece.shownKind,2,0)
    materials: PrincipledMaterial {
      baseColor: piece.design === 3 ? (piece.record.white ? "#5a2238" : "#2c1636") : piece.design === 0 ? "#10151c" : "#1b1a20"
      vertexColorsEnabled: true
      roughness: piece.design === 0 ? .1 : .25
      clearcoatAmount: piece.design === 0 ? .6 : 0
      cullMode: Material.NoCulling
    }
  }
  Model {
    property int boardSquare: piece.record.square
    pickable: piece.record.alive
    visible: !piece.woodland
    geometry: sculptures.geometry(piece.design,piece.shownKind,3,0)
    materials: PrincipledMaterial {
      baseColor: piece.secondaryColor
      vertexColorsEnabled: true
      roughness: piece.candy ? .24 : .2
      clearcoatAmount: piece.candy ? .35 : 0
      clearcoatRoughnessAmount: piece.candy ? .08 : .2
      // Orbital lights burn in their own colour whatever the room is doing.
      emissiveFactor: piece.secondGlow.times(piece.pulse)
      cullMode: Material.NoCulling
    }
  }
}

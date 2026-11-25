import QtQuick
import QtQuick3D
import Checkmate 1.0

Item {
  id: board
  property int design: backend.pieceSet
  property bool motion: !backend.reducedMotion && Window.window && Window.window.active
  property real manualAzimuth: 0
  property real azimuth: (backend.computer ? (backend.humanWhite ? 0 : 180) : 0) + manualAzimuth
  // The figures turn with the seat as the camera does, so their faces stay toward whoever is playing.
  property real seat: seatAngle()
  // Sculpted figures read best from a lower seat, the carved faces lowest; the home view follows the set until the player orbits or zooms.
  property real elevation: homeElevation()
  property real distance: homeDistance()
  property int cursorSquare: 12
  property bool keyboardMode: false
  property real checkGlow: .22
  property var lightSquares: ["#7a7c7e", "#e2caa1", "#c7c0a0", "#f6e2cb"]
  property var darkSquares: ["#252c33", "#54311e", "#65704c", "#a07a9b"]
  property var frames: ["#28343f", "#432b22", "#5b4934", "#f0dccb"]
  property var accents: ["#dcad62", "#cba265", "#9baa6b", "#dca6ab"]
  property bool sceneReady: false
  // The board keeps time for its figures, which hover, breathe, stir and watch one another while the window has the player's attention.
  property bool lively: motion
  // Midnight Atelier is lit by a flame, which is never quite steady.
  property real flicker: lively && design === 1 ? .04 * Math.sin(clock * 7.3) * Math.sin(clock * 2.1) + .018 * Math.sin(clock * 13.7) : 0
  property real clock: 0
  FrameAnimation { running: board.lively; onTriggered: board.clock += frameTime }
  Timer {
    interval: 1700; repeat: true; running: board.lively
    onTriggered: if (Math.random() < .75) figures.objectAt(Math.floor(Math.random() * 32)).fidget()
  }
  Component.onCompleted: Qt.callLater(function() { sceneReady = true })
  clip: true
  focus: true
  function seatAngle() { return backend.computer ? (backend.humanWhite ? 0 : 180) : 0 }
  function homeElevation() { return design === 2 ? -46 : -47 }
  function homeDistance() { return Math.max(design === 2 ? 12.9 : 17, fitDistance) }
  // The cast sets are seen through a longer lens from further back, so the near rank is not looked down on from overhead.
  property real lens: design === 2 ? 43 : 32
  property real farthest: Math.max(design === 2 ? 20 : 26, fitDistance * 1.25)
  // The lens is fixed vertically, so a narrow view would crop the board's sides; the camera backs off until the frame and back-rank pieces fit.
  // The board is square, so the fit ignores the seat and the camera holds still through a flip.
  property real fitDistance: {
    let aspect = width > 0 && height > 0 ? width / height : 1.6
    let tanV = Math.tan(lens * Math.PI / 360) * .94, tanH = tanV * aspect
    let e = elevation * Math.PI / 180
    let points = []
    for (let x of [-4.55, 4.55]) for (let z of [-4.55, 4.55]) points.push([x, -.5, z], [x, .1, z])
    for (let x of [-4, 4]) for (let z of [-3.5, 3.5]) points.push([x, 1.5, z])
    let needed = 0
    for (let [x, y, z] of points) {
      let y2 = y * Math.cos(e) + z * Math.sin(e), z2 = z * Math.cos(e) - y * Math.sin(e)
      needed = Math.max(needed, z2 + Math.abs(x) / tanH, z2 + Math.abs(y2) / tanV)
    }
    return needed
  }
  function resetCamera() {
    // Whole turns are dropped first, so the way home is never more than half a turn however often the board was flipped.
    rotationBehavior.enabled = false
    manualAzimuth -= 360 * Math.round(manualAzimuth / 360)
    rotationBehavior.enabled = Qt.binding(function() { return board.motion && !orbit.dragging })
    manualAzimuth = 0
    elevation = Qt.binding(function() { return board.homeElevation() })
    distance = Qt.binding(function() { return board.homeDistance() })
  }
  function keyboardSelect() { keyboardMode = true; backend.selectSquare(cursorSquare) }
  function navigate(dx, dy) {
    keyboardMode = true
    let angle = Math.round(azimuth / 90) * Math.PI / 2
    let fileStep = Math.round(dx * Math.cos(angle) - dy * Math.sin(angle))
    let rankStep = Math.round(dx * Math.sin(angle) + dy * Math.cos(angle))
    let x = Math.max(0, Math.min(7, cursorSquare % 8 + fileStep))
    let y = Math.max(0, Math.min(7, Math.floor(cursorSquare / 8) + rankStep))
    cursorSquare = y * 8 + x
  }
  Behavior on azimuth { id: rotationBehavior; enabled: board.motion && !orbit.dragging; NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
  Behavior on seat { id: seatBehavior; enabled: board.motion; NumberAnimation { duration: 650; easing.type: Easing.InOutCubic } }
  onMotionChanged: {
    if (!motion) {
      rotationBehavior.enabled = false
      seatBehavior.enabled = false
      seat = Qt.binding(function() { return board.seatAngle() })
      seatBehavior.enabled = Qt.binding(function() { return board.motion })
      checkPulse.stop(); checkGlow = .22
      azimuth = Qt.binding(function() {
        return (backend.computer ? (backend.humanWhite ? 0 : 180) : 0) + board.manualAzimuth
      })
      rotationBehavior.enabled = Qt.binding(function() { return board.motion && !orbit.dragging })
    }
  }
  Connections {
    target: backend
    function onMoved() { if (backend.checked && board.motion) checkPulse.restart() }
  }
  SequentialAnimation {
    id: checkPulse
    NumberAnimation { target: board; property: "checkGlow"; to: .7; duration: 220 }
    NumberAnimation { target: board; property: "checkGlow"; to: .22; duration: 500 }
  }
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0; color: ["#0b1726","#49392e","#353b27","#e8c8c5"][board.design] }
      GradientStop { position: 1; color: ["#080e19","#1c1716","#1f261a","#ad8b9e"][board.design] }
    }
  }
  Image {
    anchors.fill: parent
    source: ["qrc:/scenes/orbital.png", "qrc:/scenes/atelier.png", "qrc:/scenes/woodland.png", "qrc:/scenes/candy.png"][board.design]
    fillMode: Image.PreserveAspectCrop
    opacity: [ .85, .9, .7, .9 ][board.design]
    visible: source.toString().length > 0
  }
  View3D {
    id: scene
    objectName: "scene"
    anchors.fill: parent
    environment: SceneEnvironment {
      backgroundMode: SceneEnvironment.Transparent
      lightProbe: Texture { textureData: SurfaceTexture { style: 4 } }
      // Candy sits in a brighter, softer room than the other sets.
      probeExposure: board.design === 3 ? 1.15 : .75
      // Supersampling smooths both the silhouettes and the bright material edges.
      antialiasingMode: SceneEnvironment.SSAA
      antialiasingQuality: SceneEnvironment.VeryHigh
      specularAAEnabled: true
      tonemapMode: SceneEnvironment.TonemapModeAces
    }
    // Two surfaces dress the whole scene, shared by every square and piece: the set's own, and the pale wood of Atelier's light side.
    Texture { id: surfaceMap; textureData: SurfaceTexture { style: board.design } tilingModeHorizontal: Texture.Repeat; tilingModeVertical: Texture.Repeat }
    Texture { id: paleMap; textureData: SurfaceTexture { style: 5 } tilingModeHorizontal: Texture.Repeat; tilingModeVertical: Texture.Repeat }
    Node {
      eulerRotation: Qt.vector3d(board.elevation,board.azimuth,0)
      PerspectiveCamera { id: camera; z: board.distance; clipNear: .1; clipFar: 150; fieldOfView: board.lens }
    }
    camera: camera
    DirectionalLight {
      eulerRotation: Qt.vector3d(-45,-35,0)
      color: "#ffebd2"
      brightness: 1.05 * (1 + board.flicker)
      castsShadow: true
      shadowMapQuality: Light.ShadowMapQualityHigh
      shadowFactor: 80
      shadowBias: .015
      shadowMapFar: 40
    }
    DirectionalLight { eulerRotation: Qt.vector3d(-30,140,0); color: "#c2ddf4"; brightness: .35 }
    DirectionalLight { eulerRotation: Qt.vector3d(-70,0,0); color: "#ffffff"; brightness: .18 }
    Model {
      source: "#Cube"
      y: -.27
      scale: Qt.vector3d(.091,.005,.091)
      materials: PrincipledMaterial { baseColor: board.frames[board.design]; baseColorMap: surfaceMap; roughness: .38; metalness: board.design === 0 ? .4 : .05 }
    }
    Model {
      source: "#Cube"
      y: -.045
      scale: Qt.vector3d(.087,.0007,.087)
      materials: PrincipledMaterial { baseColor: board.accents[board.design]; roughness: .32; metalness: .5 }
    }
    Model {
      source: "#Cube"
      y: .001
      scale: Qt.vector3d(.084,.0005,.084)
      materials: PrincipledMaterial { baseColor: board.frames[board.design]; baseColorMap: surfaceMap; roughness: .4 }
    }
    Repeater3D {
      model: 64
      Model {
        id: tile
        required property int index
        property int boardSquare: index
        property bool target: backend.targets.indexOf(index) !== -1
        property bool marked: backend.selected === index || (board.keyboardMode && board.cursorSquare === index)
        source: "#Cube"
        objectName: "square-" + index
        pickable: true
        x: index % 8 - 3.5
        z: 3.5 - Math.floor(index / 8)
        y: .04
        scale: Qt.vector3d(.00996,.001,.00996)
        materials: PrincipledMaterial {
          baseColorMap: board.design === 1 && (Math.floor(tile.index / 8) + tile.index % 8) % 2 === 1 ? paleMap : surfaceMap
          baseColor: tile.marked ? board.accents[board.design] : (Math.floor(index / 8) + index % 8) % 2 === 1 ? board.lightSquares[board.design] : board.darkSquares[board.design]
          roughness: board.design === 3 ? .3 : .55
          metalness: board.design === 0 ? .15 : 0
        }
        Model {
          source: "#Cylinder"
          visible: tile.target
          y: 56
          // Markers swell and settle so the way forward is never static.
          property real swell: board.lively && visible ? .23 * (1 + .09 * Math.sin(board.clock * 3.1 + tile.index)) : .23
          scale: Qt.vector3d(swell,1.1,swell)
          materials: PrincipledMaterial { baseColor: board.accents[board.design]; opacity: .8; lighting: PrincipledMaterial.NoLighting }
        }
      }
    }
    Repeater3D {
      id: figures
      model: 32
      ChessPiece {
        required property int index
        pieceId: index
        record: backend.pieces[index]
        design: board.design
        seat: board.seat
        motion: board.motion
        grain: surfaceMap
        paleGrain: paleMap
        clock: board.clock
        attention: backend.selected
        selected: backend.selected === record.square && record.alive
      }
    }
    Repeater3D {
      model: [backend.lastFrom,backend.lastTo]
      Model {
        required property int modelData
        source: "#Cube"
        visible: modelData >= 0
        x: modelData % 8 - 3.5
        z: 3.5 - Math.floor(modelData / 8)
        y: .095
        scale: Qt.vector3d(.0095,.00005,.0095)
        materials: PrincipledMaterial { baseColor: board.accents[board.design]; opacity: .23; lighting: PrincipledMaterial.NoLighting }
      }
    }
    Model {
      source: "#Cylinder"
      visible: backend.checkSquare >= 0
      x: backend.checkSquare % 8 - 3.5
      z: 3.5 - Math.floor(backend.checkSquare / 8)
      y: .10
      scale: Qt.vector3d(.009,.00005,.009)
      materials: PrincipledMaterial { baseColor: "#ed7369"; opacity: board.checkGlow; lighting: PrincipledMaterial.NoLighting }
    }
  }
  Repeater {
    model: 16
    Text {
      required property int index
      property vector3d projected: {
        board.azimuth; board.elevation; board.distance; board.lens; board.width; board.height
        if (!board.sceneReady) return Qt.vector3d(-100,-100,0)
        return scene.mapFrom3DScene(index < 8 ? Qt.vector3d(index - 3.5,.14,4.25) : Qt.vector3d(-4.25,.14,3.5 - (index - 8)))
      }
      x: projected.x - width / 2
      y: projected.y - height / 2
      text: index < 8 ? "abcdefgh"[index] : index - 7
      color: board.design === 3 ? "#5d3c58" : "#f2e6c8"
      font.pixelSize: 11
      font.bold: true
      opacity: .8
    }
  }
  MouseArea {
    id: orbit
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    property real previousX: 0
    property real previousY: 0
    property bool dragging: false
    onPressed: mouse => {
      previousX = mouse.x; previousY = mouse.y
      dragging = mouse.button !== Qt.LeftButton
      board.forceActiveFocus()
    }
    onPositionChanged: mouse => {
      if (dragging) {
        board.manualAzimuth -= (mouse.x - previousX) * .4
        board.elevation = Math.max(-80, Math.min(-25, board.elevation - (mouse.y - previousY) * .25))
        previousX = mouse.x; previousY = mouse.y
      }
    }
    onReleased: dragging = false
    onCanceled: dragging = false
    onClicked: mouse => {
      if (mouse.button !== Qt.LeftButton) return
      board.keyboardMode = false
      let hit = scene.pick(mouse.x, mouse.y)
      if (hit.objectHit && hit.objectHit.boardSquare !== undefined) backend.selectSquare(hit.objectHit.boardSquare)
      else backend.cancelSelection()
    }
    onWheel: wheel => { board.distance = Math.max(10.5, Math.min(board.farthest, board.distance - wheel.angleDelta.y / 600)) }
  }
}

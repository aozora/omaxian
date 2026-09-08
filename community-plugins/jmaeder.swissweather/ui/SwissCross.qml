import QtQuick
import qs.Commons

// A Swiss cross, sized to sit on top of a bar icon.
//
// Drawn rather than borrowed from a font: no Nerd Font glyph is a Swiss cross,
// and the near misses (a plus sign, a medical cross) read as "add" or
// "pharmacy". Four rectangles cost nothing and give the real proportions.
//
// Two decisions do most of the work at this size.
//
// No square. A filled ground — red or themed — reads as a sticker pasted onto
// the weather symbol, and a ground painted in the bar's own background still
// shows as a faint box wherever that colour does not match the painted bar
// exactly. What separates the mark from the strokes underneath is a one-pixel
// halo in the background colour, drawn as a slightly larger cross behind the
// real one. It knocks out just enough of the glyph to keep the arms clean and
// disappears everywhere else.
//
// Arms proportioned by law, snapped to odd pixels. Swiss federal law fixes the
// cross at arms 6 units thick and 20 long on a 32-unit square. Odd sizes are
// what let a centred rectangle land on whole pixels; rounding to the *nearest*
// odd value matters as much as the snapping, because rounding down turns a
// 2.4-pixel arm into a 1-pixel hairline and the mark stops reading as a cross.
Item {
  id: root

  // Foreground for the cross, background for the halo behind it. Both default
  // to the theme so the mark never introduces a colour the theme did not pick.
  property color crossColor: Color.foreground
  property color haloColor: Color.background
  property bool halo: true

  // Filled square behind the cross — the flag proper, rather than the bare
  // mark used on the bar icon. Transparent by default: on top of a glyph a
  // ground reads as a sticker, but on a text line, where the flag stands on
  // its own, the square is what makes it a flag instead of a plus sign.
  property color groundColor: "transparent"
  readonly property bool hasGround: groundColor.a > 0

  // Hairline arms, matching the stroke weight of the line-art glyph the mark
  // is laid over. At badge size a "correct" arm is two or three pixels, which
  // next to a one-pixel cloud outline reads as a solid block rather than as a
  // cross drawn in the same hand.
  property bool fine: false

  /** Nearest odd integer, at least `minimum`. */
  function nearestOdd(value, minimum) {
    var n = Math.round(value)
    if (n % 2 === 0) n = (value >= n) ? n + 1 : n - 1
    if (n % 2 === 0) n += 1
    return Math.max(minimum, n)
  }

  // Rounded *down* to odd, unlike the arms: the mark must fit the box it was
  // given, and a nearest-odd here would overflow by half a pixel on each side
  // and undo the whole point of the snapping.
  readonly property int side: {
    var n = Math.floor(Math.min(width, height))
    if (n % 2 === 0) n -= 1
    return Math.max(5, n)
  }

  // 6/32 and 20/32 are the legal ratios, kept rather than stretched: the way
  // to make the mark read at badge size is to size the mark, not to distort
  // it. `fine` overrides the thickness only, so the arm *lengths* — and with
  // them the cross's silhouette — stay proportioned.
  readonly property int armThickness: fine ? 1 : Math.max(side >= 9 ? 3 : 1, nearestOdd(side * 0.1875, 1))
  readonly property int armLength: nearestOdd(side * 0.625, 3)
  readonly property int haloThickness: armThickness + 2
  readonly property int haloLength: armLength + 2

  implicitWidth: Style.space(11)
  implicitHeight: implicitWidth

  Rectangle {
    visible: root.hasGround
    anchors.centerIn: parent
    width: root.side
    height: root.side
    color: root.groundColor
    // Square, not rounded: at this size a corner radius eats the corners that
    // make it read as a flag.
    radius: 0
    antialiasing: false
  }

  // The halo only earns its place when there is no ground to separate the
  // cross from what is behind it.
  Rectangle {
    visible: root.halo && !root.hasGround
    anchors.centerIn: parent
    width: root.haloThickness
    height: root.haloLength
    color: root.haloColor
    antialiasing: false
  }

  Rectangle {
    visible: root.halo && !root.hasGround
    anchors.centerIn: parent
    width: root.haloLength
    height: root.haloThickness
    color: root.haloColor
    antialiasing: false
  }

  Rectangle {
    anchors.centerIn: parent
    width: root.armThickness
    height: root.armLength
    color: root.crossColor
    antialiasing: false
  }

  Rectangle {
    anchors.centerIn: parent
    width: root.armLength
    height: root.armThickness
    color: root.crossColor
    antialiasing: false
  }
}

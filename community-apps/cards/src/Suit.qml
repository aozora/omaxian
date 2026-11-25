import QtQuick
import QtQuick.Shapes

// One suit mark, drawn from a path rather than a font so every series and
// every machine shows the same shape. Filled, or just its outline.
Item {
  id: root
  property int suit: 0
  property color color: "white"
  property bool outline: false
  property real size: 24
  // The outline's weight, in the path's own 24-unit space.
  property real stroke: 1.1
  // A function rather than a property, so the path is there for the very first binding.
  function shape(which) {
    return [
      "M12 2C17 8 22 11 22 15A4.6 4.6 0 0 1 13.2 16.6C13.4 19 14.2 20.6 15.5 22H8.5C9.8 20.6 10.6 19 10.8 16.6A4.6 4.6 0 0 1 2 15C2 11 7 8 12 2Z",
      "M12 21C5 15 2 11.5 2 7.5A5 5 0 0 1 12 6A5 5 0 0 1 22 7.5C22 11.5 19 15 12 21Z",
      "M12 2L20 12L12 22L4 12Z",
      "M12 2a4.6 4.6 0 1 1 0 9.2a4.6 4.6 0 1 1 0-9.2ZM6.6 8.4a4.6 4.6 0 1 1 0 9.2a4.6 4.6 0 1 1 0-9.2ZM17.4 8.4a4.6 4.6 0 1 1 0 9.2a4.6 4.6 0 1 1 0-9.2ZM11 11h2c0 5 .8 8.6 2.5 11h-7c1.7-2.4 2.5-6 2.5-11Z"
    ][which]
  }
  width: size
  height: size
  Shape {
    width: 24
    height: 24
    scale: root.size / 24
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: root.outline ? "transparent" : root.color
      strokeColor: root.outline ? root.color : "transparent"
      strokeWidth: root.stroke
      // The club is three discs and a stem that overlap, so they fill as one.
      fillRule: ShapePath.WindingFill
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: root.shape(root.suit) }
    }
  }
}

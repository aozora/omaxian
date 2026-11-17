import QtQuick
import QtQuick.Shapes

// A 24-unit stroked icon, as the mockups draw them, in any color.
Item {
    id: icon
    property string name
    property color color: "white"
    property real size: 18
    readonly property var paths: ({
        play: "M7 4 L20 12 L7 20 Z",
        pause: "M7 4 L10 4 L10 20 L7 20 Z M14 4 L17 4 L17 20 L14 20 Z",
        back: "M11 6 L4 12 L11 18 Z M20 6 L13 12 L20 18 Z",
        fwd: "M13 6 L20 12 L13 18 Z M4 6 L11 12 L4 18 Z",
        prev: "M6 5 L6 19 M19 5 L9 12 L19 19 Z",
        next: "M18 5 L18 19 M5 5 L15 12 L5 19 Z",
        volume: "M4 9 L8 9 L13 5 L13 19 L8 15 L4 15 Z M16 9 C17.5 10.5 17.5 13.5 16 15 M18.5 6.5 C21.5 9.5 21.5 14.5 18.5 17.5",
        mute: "M4 9 L8 9 L13 5 L13 19 L8 15 L4 15 Z M17 9 L22 14 M22 9 L17 14",
        subs: "M3 5 L21 5 L21 19 L3 19 Z M6 12 L10 12 M12 12 L18 12 M6 15 L14 15 M16 15 L18 15",
        audio: "M9 18 A3 3 0 1 1 8.9 18 Z M12 18 L12 4 L19 6 L19 9 L12 7",
        full: "M4 9 L4 4 L9 4 M15 4 L20 4 L20 9 M20 15 L20 20 L15 20 M9 20 L4 20 L4 15",
        unfull: "M9 4 L9 9 L4 9 M20 9 L15 9 L15 4 M15 20 L15 15 L20 15 M4 15 L9 15 L9 20",
        copy: "M8 8 L20 8 L20 20 L8 20 Z M4 16 L4 4 L16 4",
        scissors: "M6 6 A2.5 2.5 0 1 1 5.9 6 Z M6 18 A2.5 2.5 0 1 1 5.9 18 Z M8 7.5 L20 17 M8 16.5 L20 7",
        picture: "M3 5 L21 5 L21 19 L3 19 Z M3 16 L9 11 L13 15 L16 12 L21 16 M15.5 8.5 L15.6 8.5",
        turn: "M20 11 A8 8 0 1 0 17.7 17.7 M20 4 L20 11 L13 11",
        zoomIn: "M10.5 3 A7.5 7.5 0 1 1 10.4 3 Z M16 16 L21 21 M7.5 10.5 L13.5 10.5 M10.5 7.5 L10.5 13.5",
        zoomOut: "M10.5 3 A7.5 7.5 0 1 1 10.4 3 Z M16 16 L21 21 M7.5 10.5 L13.5 10.5",
        trash: "M4 7 L20 7 M9 7 L9 4 L15 4 L15 7 M6 7 L7 20 L17 20 L18 7 M10 11 L10 16 M14 11 L14 16",
        edit: "M4 20 L4 16 L15 5 L19 9 L8 20 Z M13 7 L17 11",
        loop: "M4 11 L4 10 A3 3 0 0 1 7 7 L20 7 M16 3 L20 7 L16 11 M20 13 L20 14 A3 3 0 0 1 17 17 L4 17 M8 13 L4 17 L8 21",
        help: "M12 3 A9 9 0 1 1 11.9 3 Z M9.5 9.5 A2.5 2.5 0 1 1 13.2 11.7 C12.4 12.1 12 12.7 12 13.6 M12 16.8 L12 16.9",
        grid: "M4 4 L10 4 L10 10 L4 10 Z M14 4 L20 4 L20 10 L14 10 Z M4 14 L10 14 L10 20 L4 20 Z M14 14 L20 14 L20 20 L14 20 Z",
        music: "M9 18 A3 3 0 1 1 8.9 18 Z M21 16 A3 3 0 1 1 20.9 16 Z M12 18 L12 5 L24 3 L24 16"
    })
    readonly property bool filled: ["play", "pause", "back", "fwd"].indexOf(name) >= 0
    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        transform: Scale { xScale: icon.width / 24; yScale: icon.height / 24 }
        ShapePath {
            strokeColor: icon.color
            strokeWidth: 2
            fillColor: icon.filled ? icon.color : "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: icon.paths[icon.name] || "" }
        }
    }
}

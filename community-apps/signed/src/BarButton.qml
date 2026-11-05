import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// A top-bar button: optional stroked icon, a label, and the key that does the
// same thing, so the shortcuts teach themselves.
Rectangle {
    id: button

    property string text: ""
    property string icon: ""        // SVG path data on a 24×24 grid
    property string key: ""
    property bool primary: false
    property bool active: false
    property bool menu: false
    property color accent: "#FFD60A"
    property color accentForeground: "black"
    signal clicked()

    implicitWidth: row.implicitWidth + 28
    implicitHeight: 34
    radius: theme.radius
    color: primary ? accent : (hover.hovered && enabled ? "#3a3a3d" : "#2c2c2f")
    border.color: active ? accent : "transparent"
    border.width: active ? 2 : 0
    opacity: enabled ? 1 : 0.4

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: button.clicked() }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8

        Shape {
            visible: button.icon !== ""
            width: 16
            height: 16
            anchors.verticalCenter: parent.verticalCenter
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                scale: Qt.size(16 / 24, 16 / 24)
                strokeColor: button.primary ? button.accentForeground : "white"
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: button.icon }
            }
        }

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: button.text
            color: button.primary ? button.accentForeground : "white"
            font.pixelSize: 13
            font.weight: button.primary ? Font.DemiBold : Font.Normal
        }

        Shape {
            visible: button.menu
            width: 10
            height: 10
            anchors.verticalCenter: parent.verticalCenter
            ShapePath {
                strokeColor: "white"
                strokeWidth: 1.6
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: "M1 3 L5 7 L9 3" }
            }
        }

        Label {
            visible: button.key !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: button.key
            color: button.primary ? Qt.rgba(0, 0, 0, 0.45) : "#7a7a80"
            font.pixelSize: 11
            font.family: "monospace"
        }
    }
}

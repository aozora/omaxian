import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

// Nothing to make pictures with: no image model runs on this machine, or
// Omarchy's local models aren't installed. A canvas naps on its easel.
Item {
    id: root
    required property var models
    required property color muted

    readonly property bool engine: models.state !== "noEngine"
    readonly property color ink: theme.foreground
    // Opaque, so the easel's legs don't show through it.
    readonly property color paper: theme.light ? "#ffffff" : Qt.tint(theme.background, Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.08))

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 500)
        spacing: 16

        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 220
            Layout.preferredHeight: 230

            // The easel: two legs splayed, one behind, and a ledge.
            Rectangle { x: 62; y: 90; width: 7; height: 140; radius: 3; color: Qt.darker(theme.accent, 1.6); rotation: 12; transformOrigin: Item.Top }
            Rectangle { x: 150; y: 90; width: 7; height: 140; radius: 3; color: Qt.darker(theme.accent, 1.6); rotation: -12; transformOrigin: Item.Top }
            Rectangle { x: 106; y: 96; width: 6; height: 128; radius: 3; color: Qt.darker(theme.accent, 2.2) }
            Rectangle { x: 44; y: 150; width: 132; height: 8; radius: 3; color: Qt.darker(theme.accent, 1.4) }

            // The canvas, rocking a little in its sleep.
            Rectangle {
                id: canvas
                x: 40
                y: 34
                width: 140
                height: 112
                radius: Math.min(6, theme.radius + 2)
                color: root.paper
                border.width: 3
                border.color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.55)
                transformOrigin: Item.Bottom
                SequentialAnimation on rotation {
                    running: root.visible
                    loops: Animation.Infinite
                    NumberAnimation { from: -2.5; to: 2.5; duration: 2600; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 2.5; to: -2.5; duration: 2600; easing.type: Easing.InOutSine }
                }

                // Closed eyes and a small, sleepy mouth.
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: root.ink
                        strokeWidth: 3.5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: 38; startY: 50
                        PathArc { x: 58; y: 50; radiusX: 11; radiusY: 9 }
                    }
                    ShapePath {
                        strokeColor: root.ink
                        strokeWidth: 3.5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: 82; startY: 50
                        PathArc { x: 102; y: 50; radiusX: 11; radiusY: 9 }
                    }
                }
                Rectangle {
                    x: canvas.width / 2 - width / 2
                    y: 70
                    width: 12
                    height: 9
                    radius: 5
                    color: "transparent"
                    border.width: 3
                    border.color: root.ink
                }
                // Rosy cheeks.
                Rectangle { x: 28; y: 62; width: 14; height: 8; radius: 4; color: Qt.rgba(theme.colors.red.r, theme.colors.red.g, theme.colors.red.b, 0.35) }
                Rectangle { x: 98; y: 62; width: 14; height: 8; radius: 4; color: Qt.rgba(theme.colors.red.r, theme.colors.red.g, theme.colors.red.b, 0.35) }
            }

            // Zs drifting up from the nap, one after another.
            Repeater {
                model: 3
                delegate: Label {
                    id: zee
                    required property int index
                    text: "z"
                    color: root.muted
                    font.pixelSize: 16 + index * 6
                    font.weight: Font.DemiBold
                    x: 168
                    y: 40
                    opacity: 0
                    SequentialAnimation {
                        running: root.visible
                        loops: Animation.Infinite
                        PauseAnimation { duration: zee.index * 900 }
                        ParallelAnimation {
                            NumberAnimation { target: zee; property: "y"; from: 40; to: -12; duration: 2700; easing.type: Easing.OutSine }
                            NumberAnimation { target: zee; property: "x"; from: 168; to: 196; duration: 2700; easing.type: Easing.InOutSine }
                            SequentialAnimation {
                                NumberAnimation { target: zee; property: "opacity"; from: 0; to: 1; duration: 600 }
                                NumberAnimation { target: zee; property: "opacity"; from: 1; to: 0; duration: 2100 }
                            }
                        }
                        PauseAnimation { duration: (2 - zee.index) * 900 }
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 26
            font.weight: Font.DemiBold
            color: theme.foreground
            text: root.engine ? qsTr("Sorry, no model fits this machine yet") : qsTr("Fantasi needs Omarchy's local models")
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 15
            color: root.muted
            text: root.engine
                  ? qsTr("Fantasi looked everywhere, even under the sofa cushions, but none of Omarchy's image models runs on this hardware. New ones arrive with updates, so the canvas is taking a nap until then.")
                  : qsTr("Fantasi makes images with Omarchy's local models, which aren't installed.")
        }

        // The engine's own reason, for the curious.
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: 12
            color: Qt.rgba(root.muted.r, root.muted.g, root.muted.b, 0.7)
            visible: root.engine && root.models.reason !== ""
            text: root.models.reason
        }
    }
}

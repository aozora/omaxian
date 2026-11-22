import QtQuick

// Curtains of light in the theme's colours, shown while something is made.
// Transparent where there's no light, so it sits over any background; the
// shader is src/aurora.frag, compiled at build time.
ShaderEffect {
    id: aurora
    property color colorA   // the curtains' hem
    property color colorB   // their body
    property color colorC   // their top
    property real intensity: 1
    property real time: 0
    readonly property real aspect: width / Math.max(1, height)
    fragmentShader: "qrc:/aurora.frag.qsb"
    NumberAnimation on time { running: aurora.visible; from: 0; to: 3600; duration: 3600000; loops: Animation.Infinite }
}

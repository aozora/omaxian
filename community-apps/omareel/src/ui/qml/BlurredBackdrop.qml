import QtQuick
import QtQuick.Effects

// A heavily blurred, darkened copy of `source`, scaled to cover this item. It fills the canvas
// around footage that does not match it. The source is captured into a tiny texture first, which
// makes the blur both cheap and very soft. The software renderer cannot run effects, so it shows
// a dark fill instead.
Item {
    id: root
    required property Item source
    property real sourceAspect: 1
    property bool softwareRendering: false
    clip: true

    Rectangle { anchors.fill: parent; color: "#0b0b0e" }
    Loader {
        anchors.fill: parent
        active: !root.softwareRendering && root.source !== null
        sourceComponent: Item {
            ShaderEffectSource {
                id: capture
                sourceItem: root.source
                live: true
                hideSource: false
                visible: false
                smooth: true
                // Fixed and tiny: the item below restores the aspect, and the blur hides the rest.
                textureSize: Qt.size(24, 24)
            }
            MultiEffect {
                anchors.centerIn: parent
                // Cover the canvas with some overscan so the softened edges stay outside it.
                width: Math.max(root.width, root.height * root.sourceAspect) * 1.2
                height: width / Math.max(.01, root.sourceAspect)
                source: capture
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 1
                blurMax: 64
                saturation: .1
            }
        }
    }
    Rectangle { anchors.fill: parent; color: "black"; opacity: .22 }
}

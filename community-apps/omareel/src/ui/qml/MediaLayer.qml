import QtQuick
import Omareel

// An inserted video. "fit" shows all of it over a blurred copy, "fill" covers the canvas, and
// "framed" sits in the project's frame over its background, as the screen does.
Item {
    id: root
    required property var media
    required property var frameSettings
    property bool softwareRendering: false
    property bool nativePreview: false
    property real ref: height / 1080
    // Space kept around a framed video, as the screen keeps.
    property real padding: 0
    readonly property alias frameSource: frame.frameSource
    readonly property alias videoOutput: frame.videoOutput
    readonly property string fit: media.fit === "fill" || media.fit === "framed" ? media.fit : "fit"
    readonly property real aspect: Math.max(1, media.width) / Math.max(1, media.height)
    readonly property real canvasAspect: width / Math.max(1, height)
    readonly property real borderWidth: fit === "framed" && frameSettings.border.enabled
        ? frameSettings.border.width * ref : 0
    readonly property real areaWidth: fit === "framed" ? width - 2 * padding - 2 * borderWidth : width
    readonly property real areaHeight: fit === "framed" ? height - 2 * padding - 2 * borderWidth : height
    readonly property real containedWidth: Math.max(1, Math.min(areaWidth, areaHeight * aspect))

    // The part of the video that covers the canvas, centred.
    function coverCrop() {
        if (aspect > canvasAspect) {
            const visible = canvasAspect / aspect
            return {x: (1 - visible) / 2, y: 0, w: visible, h: 1}
        }
        const visible = aspect / canvasAspect
        return {x: 0, y: (1 - visible) / 2, w: 1, h: visible}
    }

    BlurredBackdrop {
        anchors.fill: parent
        visible: root.fit === "fit"
        source: frame.content
        sourceAspect: root.aspect
        softwareRendering: root.softwareRendering
    }
    RoundedFrame {
        id: frame
        frameSourceName: "mediaFrameSource"
        x: (root.width - width) / 2
        y: (root.height - height) / 2
        width: root.fit === "fill" ? root.width : root.containedWidth
        height: root.fit === "fill" ? root.height : root.containedWidth / root.aspect
        settings: root.frameSettings
        crop: root.fit === "fill" ? root.coverCrop() : ({x: 0, y: 0, w: 1, h: 1})
        softwareRendering: root.softwareRendering
        ref: root.ref
        unframed: root.fit !== "framed"
        nativePreview: root.nativePreview
    }
}

import QtQuick
import QtQuick.Window

// A picture: shrunk to fit the window but never enlarged, until a key, the
// wheel or a pinch zooms it about the point under the pointer, and dragged
// when it is larger than the window. Turning it is the view's alone; the file
// is never changed.
Item {
    id: view
    objectName: "pictureView"
    clip: true

    property url source
    property bool animated: false
    property bool vector: false
    property bool transparent: false
    // An SVG's own size, which decoding it at the size shown can't give.
    property size vectorSize
    property int turn: 0
    property bool paused: false
    signal failed()

    // 0 fits; otherwise the scale, 1 being the picture's own pixels.
    property real zoom: 0
    property real panX: 0
    property real panY: 0

    // The decoded picture's own size, upright by its EXIF orientation. While
    // the next one decodes, the last one stays, at its own size.
    readonly property Item image: loader.item
    readonly property real naturalWidth: vector ? vectorSize.width : (image ? image.implicitWidth : 0)
    readonly property real naturalHeight: vector ? vectorSize.height : (image ? image.implicitHeight : 0)
    readonly property bool ready: image !== null && image.status === Image.Ready && naturalWidth > 0 && naturalHeight > 0
    readonly property bool turned: turn % 180 !== 0
    readonly property real turnedWidth: turned ? naturalHeight : naturalWidth
    readonly property real turnedHeight: turned ? naturalWidth : naturalHeight
    readonly property real fitRatio: turnedWidth > 0 && turnedHeight > 0
                                     ? Math.min(1, width / turnedWidth, height / turnedHeight) : 1
    readonly property real ratio: zoom > 0 ? zoom : fitRatio
    readonly property bool fitted: zoom === 0
    readonly property real overflowX: Math.max(0, (turnedWidth * ratio - width) / 2)
    readonly property real overflowY: Math.max(0, (turnedHeight * ratio - height) / 2)
    readonly property bool pannable: overflowX > 0.5 || overflowY > 0.5
    readonly property real maximumRatio: 32

    function reset() {
        zoom = 0
        panX = 0
        panY = 0
    }
    function clampPan() {
        panX = Math.max(-overflowX, Math.min(overflowX, panX))
        panY = Math.max(-overflowY, Math.min(overflowY, panY))
    }
    onOverflowXChanged: clampPan()
    onOverflowYChanged: clampPan()

    // Zooms to a scale keeping the point (x, y) of the view, the middle when
    // none is given, over the same point of the picture. Out as far as fitting
    // it, which it then does as the window changes.
    function zoomTo(target, x, y) {
        if (!ready)
            return
        if (x === undefined) {
            x = width / 2
            y = height / 2
        }
        target = Math.min(maximumRatio, Math.max(fitRatio, target))
        const atX = (x - width / 2 - panX) / ratio, atY = (y - height / 2 - panY) / ratio
        zoom = Math.abs(target - fitRatio) < 0.001 ? 0 : target
        panX = x - width / 2 - atX * ratio
        panY = y - height / 2 - atY * ratio
        clampPan()
    }
    function zoomBy(factor, x, y) { zoomTo(ratio * factor, x, y) }
    function actualSize() { zoomTo(1) }
    function panBy(dx, dy) {
        panX += dx
        panY += dy
        clampPan()
    }

    Item {
        id: frame
        width: view.naturalWidth * view.ratio
        height: view.naturalHeight * view.ratio
        x: (view.width - width) / 2 + view.panX
        y: (view.height - height) / 2 + view.panY
        rotation: view.turn

        // What's see-through shows as a dark checkerboard, so a black logo
        // on a transparent background doesn't vanish into the letterbox.
        Image {
            anchors.fill: parent
            visible: view.transparent && view.ready
            source: "qrc:/checker.svg"
            fillMode: Image.Tile
            smooth: false
        }
        Loader {
            id: loader
            anchors.fill: parent
            sourceComponent: view.animated ? moving : still
        }
    }

    Component {
        id: still
        Image {
            source: view.source
            // Decoded off the GUI thread, and the last picture kept on screen
            // until the next is ready, so stepping through a folder never
            // flashes black.
            asynchronous: true
            retainWhileLoading: true
            autoTransform: true
            smooth: true
            // Smooth when a large photo is shrunk to fit.
            mipmap: !view.vector
            // A drawing is drawn again at the size it shows, so it stays sharp
            // as it is zoomed, up to a size any GPU takes. The size is in
            // logical pixels; Qt multiplies it by the screen's ratio itself.
            sourceSize: {
                if (!view.vector || view.naturalWidth <= 0 || view.naturalHeight <= 0)
                    return undefined
                const limit = Math.min(view.ratio,
                                       8192 / Screen.devicePixelRatio / Math.max(1, view.naturalWidth, view.naturalHeight))
                return Qt.size(Math.ceil(view.naturalWidth * limit), Math.ceil(view.naturalHeight * limit))
            }
            onStatusChanged: if (status === Image.Error) view.failed()
        }
    }
    Component {
        id: moving
        AnimatedImage {
            source: view.source
            autoTransform: true
            smooth: true
            // Paused where it is, not stopped and started over.
            paused: view.paused
            onStatusChanged: if (status === Image.Error) view.failed()
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            const steps = event.angleDelta.y / 120
            if (steps !== 0)
                view.zoomBy(Math.pow(1.25, steps), point.position.x, point.position.y)
        }
    }
    PinchHandler {
        target: null
        property real startRatio: 1
        onActiveChanged: if (active) startRatio = view.ratio
        onActiveScaleChanged: if (active) view.zoomTo(startRatio * activeScale, centroid.position.x, centroid.position.y)
    }
    DragHandler {
        target: null
        enabled: view.pannable
        cursorShape: Qt.ClosedHandCursor
        property real startX: 0
        property real startY: 0
        onActiveChanged: {
            if (active) {
                startX = view.panX
                startY = view.panY
            }
        }
        onActiveTranslationChanged: {
            if (!active)
                return
            view.panX = startX + activeTranslation.x
            view.panY = startY + activeTranslation.y
            view.clampPan()
        }
    }
}

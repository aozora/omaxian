import QtQuick

// One page: its render, and the items placed on it.
Item {
    id: page

    property int index: 0
    property real viewScale: 1
    property color accent: "#FFD60A"
    property int renderWidth: 0
    signal backgroundPressed()

    width: Math.round(backend.pageWidth(index) * viewScale)
    height: Math.round(backend.pageHeight(index) * viewScale)

    // Re-render only once a zoom settles, in steps, so dragging the zoom
    // doesn't queue a render per frame.
    function updateRenderWidth() {
        renderWidth = Math.ceil(width * Screen.devicePixelRatio / 64) * 64;
    }
    onWidthChanged: renderTimer.restart()
    Component.onCompleted: updateRenderWidth()
    Timer { id: renderTimer; interval: 150; onTriggered: page.updateRenderWidth() }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -1
        anchors.topMargin: 2
        anchors.bottomMargin: -6
        color: "#60000000"
        radius: Math.min(2, theme.radius)
    }
    Rectangle { anchors.fill: parent; color: "white" }

    // The last finished render stays up while a sharper one loads behind it.
    Image {
        id: shown
        anchors.fill: parent
        cache: true
        smooth: true
    }
    Image {
        id: loader
        visible: false
        asynchronous: true
        cache: true
        source: page.renderWidth > 0 ? "image://pages/" + backend.generation + "/" + page.index + "/" + page.renderWidth : ""
        onStatusChanged: if (status === Image.Ready) shown.source = source
    }

    MouseArea {
        anchors.fill: parent
        onPressed: page.backgroundPressed()
    }

    Repeater {
        model: backend.items
        delegate: PlacedItem {
            pageIndex: page.index
            viewScale: page.viewScale
            accent: page.accent
        }
    }
}

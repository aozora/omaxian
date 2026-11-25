import QtQuick
import QtQuick.Window

// Ctrl+M: every file in the folder as a tile, the one shown picked. The
// pick follows the pointer as it moves, and the arrows while they're used;
// Enter or a click opens it, Esc goes back. A picked video flips through ten
// frames from across it, as a silent preview of the whole thing.
FocusScope {
    id: grid
    objectName: "grid"
    property real tileSize: 240
    signal picked(int index)
    signal closed()


    // Takes every key but the window's Ctrl ones, fullscreen and quit, so
    // the player's keys don't act on the file behind.
    Keys.onShortcutOverride: event => {
        event.accepted = !(event.modifiers & Qt.ControlModifier) && event.key !== Qt.Key_F && event.key !== Qt.Key_Q
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }
    // Clicks between the tiles stop here, rather than playing the file behind.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    GridView {
        id: view
        objectName: "gridView"
        anchors.fill: parent
        anchors.margins: gap
        anchors.rightMargin: 0
        focus: true
        clip: true
        readonly property real gap: 8
        // Tiles stretch to fill a row, so the grid runs to the window's edge.
        readonly property int columns: Math.max(1, Math.floor(width / (grid.tileSize + gap)))
        readonly property real tileWidth: Math.floor(width / columns) - gap
        readonly property real tileHeight: Math.round(tileWidth * 3 / 4)
        // Decoded at sizes in steps, so a zoom doesn't decode every tile again;
        // logical pixels, which Qt multiplies by the screen's ratio itself.
        readonly property int decodeWidth: Math.ceil(tileWidth / 80) * 80
        // A pick made with the keys scrolls into view; one made with the
        // pointer is already there.
        property bool byKeys: false
        onCurrentIndexChanged: {
            if (byKeys)
                positionViewAtIndex(currentIndex, GridView.Contain)
            byKeys = false
        }
        // The pointer picks what it moves over; resting, it leaves the keys'
        // pick alone, even as the keys scroll the tiles under it, which Qt
        // reports as hovering too. Only a move on screen counts.
        HoverHandler {
            property point last: Qt.point(-1, -1)
            onPointChanged: {
                const at = point.scenePosition
                if (at.x === last.x && at.y === last.y)
                    return
                last = at
                const index = view.indexAt(point.position.x + view.contentX, point.position.y + view.contentY)
                if (index >= 0)
                    view.currentIndex = index
            }
        }
        cellWidth: tileWidth + gap
        cellHeight: tileHeight + gap
        model: backend.playlist
        currentIndex: backend.playlistIndex
        cacheBuffer: height
        boundsBehavior: Flickable.StopAtBounds
        keyNavigationEnabled: true
        highlightFollowsCurrentItem: false
        Component.onCompleted: positionViewAtIndex(currentIndex, GridView.Center)
        onColumnsChanged: Qt.callLater(() => positionViewAtIndex(currentIndex, GridView.Contain))

        Keys.onReturnPressed: grid.picked(currentIndex)
        Keys.onEnterPressed: grid.picked(currentIndex)
        Keys.onEscapePressed: grid.closed()
        Keys.onPressed: event => {
            byKeys = true
            if (event.key === Qt.Key_Home)
                currentIndex = 0
            else if (event.key === Qt.Key_End)
                currentIndex = count - 1
            else
                return
            event.accepted = true
        }

        delegate: Item {
            id: tile
            required property string modelData
            required property int index
            readonly property string kind: backend.kindOf(modelData)
            // The file as it is now: a tile for a file edited since is a new
            // one, not Qt's cached copy of the old.
            readonly property string address: backend.fileStamp(modelData) + "/" + encodeURIComponent(modelData)
            readonly property bool wanted: kind === "video" && view.currentIndex === index
            readonly property bool previewing: wanted && dwell.done
            onWantedChanged: dwell.done = false
            width: view.cellWidth
            height: view.cellHeight

            Rectangle {
                id: frame
                width: view.tileWidth
                height: view.tileHeight
                // Shows at once, before its picture, so the grid is there
                // from the first frame and fills in as the tiles decode.
                color: Qt.rgba(1, 1, 1, 0.08)
                radius: Math.min(4, theme.radius)
                clip: true

                Image {
                    anchors.fill: parent
                    visible: tile.kind !== "audio"
                    source: tile.kind === "audio" ? "" : "image://thumbnail/" + tile.address
                    sourceSize: Qt.size(view.decodeWidth, Math.round(view.decodeWidth * 3 / 4))
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                // A song has no picture of its own here: its name.
                Column {
                    visible: tile.kind === "audio"
                    anchors.centerIn: parent
                    width: parent.width - 24
                    spacing: 10
                    Icon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: "music"
                        size: Math.min(48, frame.height / 3)
                        color: "#6a6a70"
                    }
                    Text {
                        width: parent.width
                        text: tile.modelData.split("/").pop()
                        color: "#c8c8cc"
                        font.pixelSize: 13
                        elide: Text.ElideMiddle
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
                Loader {
                    anchors.fill: parent
                    active: tile.previewing
                    sourceComponent: Image {
                        id: strip
                        objectName: "gridPreview"
                        property int frame: 0
                        // Over the poster once the first frame is in, and the
                        // last one kept while the next loads.
                        property bool started: false
                        visible: started
                        onStatusChanged: if (status === Image.Ready) started = true
                        source: "image://thumbnail/frame/" + frame + "/" + tile.address
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        retainWhileLoading: true
                        Timer {
                            interval: 400
                            repeat: true
                            running: strip.status === Image.Ready
                            onTriggered: strip.frame = (strip.frame + 1) % 10
                        }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: frame.radius
                    border.width: view.currentIndex === tile.index ? 3 : 0
                    border.color: theme.accent
                }
            }
            // A pointer passing over doesn't start every video it crosses.
            Timer {
                id: dwell
                property bool done: false
                interval: 300
                running: tile.wanted && !done
                onTriggered: done = true
            }
            TapHandler {
                onTapped: grid.picked(tile.index)
            }
        }
    }
}

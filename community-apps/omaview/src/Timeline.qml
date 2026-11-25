import QtQuick
import "Format.js" as Format

// The timeline along the bottom: a thin line when bare, a scrubber when
// expanded, with a preview frame over the pointer. Time runs left to right in
// every language, so it is never mirrored.
Item {
    id: timeline
    property bool expanded: false
    readonly property bool usable: backend.seekable && backend.duration > 0
    readonly property real fraction: backend.duration > 0 ? Math.min(1, backend.position / backend.duration) : 0
    property real dragFraction: -1
    readonly property real shownFraction: dragFraction >= 0 ? dragFraction : fraction
    readonly property real hoverFraction: hover.hovered && width > 0 ? Math.max(0, Math.min(1, hover.point.position.x / width)) : -1
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true
    height: expanded ? 28 : 3

    Rectangle {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: timeline.expanded ? 10 : 0
        height: timeline.expanded ? 5 : 3
        color: Qt.rgba(1, 1, 1, timeline.expanded ? 0.22 : 0.14)
        visible: timeline.usable

        Rectangle {
            height: parent.height
            width: parent.width * timeline.shownFraction
            color: theme.accent
        }
        Repeater {
            model: timeline.expanded ? backend.chapters : []
            delegate: Rectangle {
                required property var modelData
                visible: modelData.start > 0 && backend.duration > 0
                x: backend.duration > 0 ? track.width * modelData.start / backend.duration - 1 : 0
                width: 2
                height: track.height
                color: Qt.rgba(0, 0, 0, 0.7)
            }
        }
        Rectangle {
            visible: timeline.expanded
            width: 14
            height: 14
            radius: 7
            color: theme.accent
            x: track.width * timeline.shownFraction - 7
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // The preview: a tile from the atlas, the time, and the chapter there.
    Column {
        id: preview
        readonly property bool pointing: timeline.hoverFraction >= 0 || timeline.dragFraction >= 0
        visible: timeline.usable && timeline.expanded && pointing
        // Where the pointer is, or nothing: it never follows the playhead, so
        // a hidden preview costs nothing as the video plays.
        readonly property real at: timeline.dragFraction >= 0 ? timeline.dragFraction
                                   : timeline.hoverFraction >= 0 ? timeline.hoverFraction : 0
        readonly property int tile: backend.previewCount > 0
                                    ? Math.min(backend.previewCount - 1, Math.floor(at * backend.duration / 1000 / backend.previewInterval))
                                    : -1
        spacing: 6
        x: Math.max(0, Math.min(timeline.width - width, timeline.width * at - width / 2))
        anchors.bottom: track.top
        anchors.bottomMargin: 14

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            // The picture itself shows where a key seek landed.
            visible: preview.tile >= 0 && preview.pointing
            width: backend.previewTileSize.width
            height: backend.previewTileSize.height
            clip: true
            Image {
                source: backend.previewSource
                asynchronous: true
                cache: true
                x: -(preview.tile % backend.previewColumns) * backend.previewTileSize.width
                y: -Math.floor(preview.tile / backend.previewColumns) * backend.previewTileSize.height
            }
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: theme.accent
                border.width: 2
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: label.implicitWidth + 16
            height: label.implicitHeight + 6
            color: Qt.rgba(0, 0, 0, 0.8)
            radius: Math.min(4, theme.radius)
            Text {
                id: label
                anchors.centerIn: parent
                readonly property string chapter: backend.chapterAt(preview.at * backend.duration)
                text: Format.clock(preview.at * backend.duration) + (chapter !== "" ? "  ·  " + chapter : "")
                color: "white"
                font.family: "monospace"
                font.pixelSize: 13
            }
        }
    }

    HoverHandler {
        id: hover
        enabled: timeline.usable
        cursorShape: Qt.PointingHandCursor
    }
    MouseArea {
        anchors.fill: parent
        anchors.topMargin: -8
        enabled: timeline.usable && timeline.expanded
        preventStealing: true
        function at(x) { return width > 0 ? Math.max(0, Math.min(1, x / width)) : 0 }
        onPressed: mouse => timeline.dragFraction = at(mouse.x)
        onPositionChanged: mouse => { if (pressed) timeline.dragFraction = at(mouse.x) }
        onReleased: mouse => {
            backend.seekFraction(at(mouse.x))
            timeline.dragFraction = -1
        }
        onCanceled: timeline.dragFraction = -1
    }
}

import QtQuick

// Compact color swatch that opens a picker; checkerboard-free, hairline edged.
Rectangle {
    id: root
    signal clicked()
    implicitWidth: 44
    implicitHeight: 26
    radius: theme.controlRadius
    color: "transparent"
    border.width: 1
    border.color: mouse.containsMouse ? theme.strokeStrong : theme.stroke
    property color swatch: "black"
    scale: mouse.pressed ? .95 : 1
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: Math.max(0, theme.controlRadius - 2)
        color: root.swatch
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

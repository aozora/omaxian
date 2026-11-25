import QtQuick
import QtQuick.Controls

// A small line icon in the footer that does something when clicked, with a
// tooltip naming it and its shortcut.
Item {
    id: control

    property string iconName
    property color iconColor: "#666666"
    property string tooltip

    signal clicked()

    width: 16
    height: 16

    Tip {
        visible: hitArea.containsMouse && control.tooltip.length > 0
        text: control.tooltip
    }

    LineIcon {
        anchors.fill: parent
        name: control.iconName
        color: control.iconColor
    }

    MouseArea {
        id: hitArea
        anchors.centerIn: parent
        width: 28
        height: 28
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.clicked()
    }
}

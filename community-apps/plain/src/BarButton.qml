import QtQuick
import QtQuick.Controls

// A small text button for the find bar, at the desktop's text size: a label
// with a faint hover, and a fill while checked (match case).
Item {
    id: button

    property string text
    property string tooltip
    property bool checkable: false
    property bool checked: false

    signal clicked()

    implicitWidth: Math.max(implicitHeight, label.implicitWidth + 16)
    implicitHeight: label.implicitHeight + 10
    opacity: enabled ? 1 : 0.4

    ToolTip.visible: area.containsMouse && tooltip.length > 0
    ToolTip.text: tooltip

    Rectangle {
        anchors.fill: parent
        radius: Math.min(4, theme.radius)
        color: button.checked ? win.tint(theme.accent, 0.25)
             : area.pressed ? win.tint(theme.foreground, 0.14)
             : area.containsMouse ? win.tint(theme.foreground, 0.08) : "transparent"
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        font.pixelSize: theme.textSize
        color: button.checked ? theme.brightForeground : theme.foreground
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (button.checkable)
                button.checked = !button.checked
            button.clicked()
        }
    }
}

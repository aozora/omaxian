import QtQuick
import QtQuick.Controls

TextField {
    id: control
    implicitHeight: theme.space.controlHeight + 2
    leftPadding: theme.space.controlPaddingX; rightPadding: theme.space.controlPaddingX
    topPadding: 0; bottomPadding: 0
    verticalAlignment: TextInput.AlignVCenter
    color: theme.textStrong; placeholderTextColor: theme.textFaint
    selectionColor: Qt.alpha(theme.accent, .35); selectedTextColor: theme.textStrong
    font.family: theme.fontFamily; font.pixelSize: theme.type.body
    background: Rectangle {
        radius: theme.controlRadius
        color: control.activeFocus ? theme.canvas : control.hovered ? theme.fillHover : theme.fill
        border.width: 1
        border.color: control.activeFocus ? theme.accent : theme.stroke
        Behavior on color { ColorAnimation { duration: 140 } }
        Behavior on border.color { ColorAnimation { duration: 140 } }
    }
}

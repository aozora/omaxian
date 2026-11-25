import QtQuick
import QtQuick.Controls

Slider {
    id: control
    property int tickCount: 0
    readonly property bool engaged: pressed || hovered
    implicitHeight: 22
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    leftPadding: 7
    rightPadding: 7
    background: Item {
        x: control.leftPadding
        y: control.topPadding + (control.availableHeight - height) / 2
        width: control.availableWidth
        height: control.engaged ? 5 : 4
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Rectangle {
            anchors.fill: parent
            radius: theme.rounded ? height / 2 : 0
            color: Qt.alpha(theme.foreground, .12)
        }
        Rectangle {
            width: control.visualPosition * parent.width
            height: parent.height
            radius: theme.rounded ? height / 2 : 0
            color: control.enabled ? theme.accent : theme.textFaint
        }
        Repeater {
            model: control.tickCount > 1 ? control.tickCount : 0
            Rectangle {
                required property int index
                width: 2; height: 2; radius: 1
                color: theme.textFaint
                x: index * (parent.width - width) / Math.max(1, control.tickCount - 1)
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + (control.availableHeight - height) / 2
        width: 14; height: 14
        radius: width / 2
        color: control.enabled ? theme.textStrong : theme.textFaint
        border.width: 3
        border.color: control.enabled ? theme.accent : theme.textFaint
        scale: control.pressed ? 1.2 : control.hovered ? 1.1 : 1
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2 } }
        Rectangle {
            anchors.centerIn: parent
            width: parent.width + 12; height: width
            radius: width / 2
            color: Qt.alpha(theme.accent, .22)
            opacity: control.pressed ? 1 : control.visualFocus ? .8 : 0
            scale: control.pressed ? 1 : .6
            z: -1
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
    }
}

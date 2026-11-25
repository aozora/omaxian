import QtQuick

OmButton {
    id: control
    implicitWidth: theme.space.controlHeight
    implicitHeight: theme.space.controlHeight
    width: theme.space.controlHeight
    height: theme.space.controlHeight
    leftPadding: 0
    rightPadding: 0
    topPadding: 0
    bottomPadding: 0
    bordered: false
    icon.width: 16
    icon.height: 16
    icon.color: !enabled ? theme.textFaint
        : selected || active || hovered ? theme.textStrong : theme.textMuted
}

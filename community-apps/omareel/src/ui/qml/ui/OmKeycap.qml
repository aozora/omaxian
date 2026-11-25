import QtQuick

// Keyboard key in the Omarchy monospace, with a slightly deeper bottom edge.
Rectangle {
    id: root
    property alias text: label.text
    property bool subtle: false
    implicitWidth: Math.max(implicitHeight, label.implicitWidth + 10)
    implicitHeight: 20
    radius: Math.min(4, theme.smallRadius)
    color: subtle ? theme.fill : theme.raised
    border.width: 1
    border.color: theme.strokeStrong
    Rectangle {
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        anchors.leftMargin: 1; anchors.rightMargin: 1
        height: 1
        color: Qt.alpha("black", theme.dark ? .35 : .08)
    }
    Text {
        id: label
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -0.5
        color: root.subtle ? theme.textMuted : theme.textStrong
        font.family: theme.monoFamily
        font.pixelSize: theme.type.caption
        font.weight: Font.Medium
    }
}

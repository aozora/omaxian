import QtQuick
import QtQuick.Controls

// A control on the overlay: an icon, an optional label, no border; its keys
// are in the ? overlay.
Rectangle {
    id: control
    property string icon
    property string text
    property bool primary: false
    // Named for assistive tech, and in a tooltip with its key, when it shows
    // only an icon.
    property string label
    property string shortcut
    // An icon alone, quieter than the transport's, as the top row's are.
    property bool subtle: false
    // On, as a loop is: the icon takes the accent.
    property bool checked: false
    readonly property bool labelled: text !== ""
    signal clicked()
    implicitHeight: primary ? 46 : (labelled ? 30 : 36)
    implicitWidth: labelled ? row.implicitWidth + 20 : implicitHeight
    radius: Math.min(4, theme.radius)
    color: primary ? theme.accent : mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
    Accessible.role: Accessible.Button
    Accessible.name: label !== "" ? label : text
    ToolTip.visible: label !== "" && mouse.containsMouse
    ToolTip.delay: 500
    ToolTip.text: shortcut !== "" ? label + "   " + shortcut : label

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Icon {
            visible: control.icon !== ""
            name: control.icon
            size: control.primary ? 20 : (control.labelled ? 14 : 18)
            color: control.primary ? theme.accentForeground : control.checked ? theme.accent
                   : control.subtle && !mouse.containsMouse ? "#9a9aa0" : "#e6e6ea"
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: control.text !== ""
            text: control.text
            color: "#e6e6ea"
            font.pixelSize: 13
            width: Math.min(implicitWidth, 160)
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.clicked()
    }
}

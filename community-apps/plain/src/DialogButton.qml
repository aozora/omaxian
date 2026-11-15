import QtQuick
import QtQuick.Controls

// A dialog button in the theme: Omawrite's square buttons, with the theme's
// colors and Hyprland's corner rounding instead of fixed grays.
// From Omawrite's SquareDialogButton (MIT, David Heinemeier Hansson).
Button {
    id: control

    property bool primary: false
    // "<u>S</u>ave": the letter Alt+ presses it.
    property string formattedText: ""

    leftPadding: 16
    rightPadding: 16
    topPadding: 7
    bottomPadding: 7

    Keys.onReturnPressed: clicked()
    Keys.onEnterPressed: clicked()

    contentItem: Label {
        text: control.formattedText.length > 0 ? control.formattedText : control.text
        textFormat: control.formattedText.length > 0 ? Text.StyledText : Text.PlainText
        color: control.primary ? theme.accentForeground : theme.foreground
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        implicitWidth: 88
        implicitHeight: 34
        radius: Math.min(4, theme.radius)
        color: control.primary
            ? Qt.darker(theme.accent, control.down ? 1.2 : control.hovered ? 1.08 : 1)
            : win.tint(theme.foreground, control.down ? 0.12 : control.hovered ? 0.08 : 0.04)
        border.color: control.activeFocus ? theme.brightForeground
            : control.primary ? Qt.darker(theme.accent, 1.15)
            : win.tint(theme.foreground, 0.2)
    }
}

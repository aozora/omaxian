import QtQuick

Text {
    textFormat: Text.PlainText
    color: enabled ? theme.foreground : theme.textFaint
    font.family: theme.fontFamily
    font.pixelSize: theme.type.body
    elide: Text.ElideRight
}

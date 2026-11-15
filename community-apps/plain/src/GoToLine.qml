import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Ctrl+G: a line number, Enter, there.
Popup {
    id: popup

    signal accepted(int line)

    modal: true
    focus: true
    padding: 16
    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }
    // Focused as it starts to show rather than once its animation ends, so a
    // quick Ctrl+G 1 2 Enter lands every key in the field.
    onAboutToShow: {
        field.text = ""
        field.placeholder = qsTr("1 to %1").arg(editing.lineCount())
        field.forceActiveFocus()
    }

    background: DialogBackground {}

    contentItem: ColumnLayout {
        spacing: 8
        Label { text: qsTr("Go to line"); color: theme.brightForeground }
        FindField {
            id: field
            Layout.preferredWidth: 220
            inputMethodHints: Qt.ImhDigitsOnly
            validator: IntValidator { bottom: 1 }
            Keys.onReturnPressed: popup.go()
            Keys.onEnterPressed: popup.go()
        }
    }

    function go() {
        const line = parseInt(field.text)
        if (line > 0) {
            close()
            accepted(line)
        }
    }
}

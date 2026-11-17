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
    // There and gone at once: Plain animates nothing.
    enter: Transition {}
    exit: Transition {}
    // Focused as it starts to show, so a quick Ctrl+G 1 2 Enter lands every
    // key in the field.
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

    // Read as the validator reads it: in the language's own digits and
    // grouping, so 1,000 is line 1000, not 1.
    function go() {
        let line = NaN
        try {
            line = Number.fromLocaleString(Qt.locale(), field.text)
        } catch (error) {
            return
        }
        if (Number.isInteger(line) && line > 0) {
            close()
            accepted(line)
        }
    }
}

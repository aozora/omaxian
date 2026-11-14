import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// Find, and with Ctrl+H replace. Literal text, with a match-case toggle.
Rectangle {
    id: bar

    property var editor
    property bool replacing: false
    property bool caseSensitive: false
    // "Replaced 3", until the search changes.
    property string replaced: ""
    property int matches: 0

    // Counted when the search changes, and a moment after the text stops
    // changing rather than on every keystroke, since it searches the whole file.
    function recount() { matches = visible ? editing.matchCount(findField.text, caseSensitive) : 0 }
    onVisibleChanged: recount()
    onCaseSensitiveChanged: recount()
    Timer { id: recountLater; interval: 150; onTriggered: bar.recount() }
    Connections {
        target: bar.editor.area
        function onTextChanged() { if (bar.visible) recountLater.restart() }
    }

    visible: false
    implicitHeight: column.implicitHeight + 12
    color: theme.darkBackground

    function show(replace) {
        replacing = replace
        visible = true
        const area = editor.area
        if (area.selectionStart !== area.selectionEnd && area.selectedText.indexOf("\u2029") < 0)
            findField.text = area.selectedText
        findField.forceActiveFocus()
        findField.selectAll()
        recount()
    }

    function hide() {
        visible = false
        editor.focusText()
    }

    function next(backward) {
        if (findField.text.length === 0) {
            show(replacing)
            return
        }
        const area = editor.area
        const from = backward ? area.selectionStart : area.selectionEnd
        const found = editing.find(findField.text, from, backward, caseSensitive)
        if (found.length === 2)
            editor.select(found[0], found[1])
    }

    function selectionMatches() {
        const selected = editor.area.selectedText
        return caseSensitive ? selected === findField.text : selected.toLowerCase() === findField.text.toLowerCase()
    }

    // Backward leaves the cursor before the replacement, so the search back
    // doesn't find the match inside what was just put in.
    function replaceOne(backward) {
        const area = editor.area
        if (findField.text.length > 0 && selectionMatches()) {
            const start = area.selectionStart
            const end = editing.replace(start, area.selectionEnd, replaceField.text)
            area.cursorPosition = backward ? start : end
        }
        next(backward)
    }

    // Ctrl+Enter reaches here from the find field too, so it checks what the
    // Replace all button's enabled state does.
    function replaceAll() {
        if (!doc.editable || findField.text.length === 0)
            return
        const count = editing.replaceAll(findField.text, replaceField.text, caseSensitive)
        replaced = qsTr("Replaced %n", "", count)
    }

    // Enter steps forward through matches in the find field and replaces one
    // and steps on in the replace field, with Shift backward in both;
    // Ctrl+Enter replaces all from either.
    function submit(event, replace) {
        const backward = event.modifiers & Qt.ShiftModifier
        if (replacing && (event.modifiers & Qt.ControlModifier))
            replaceAll()
        else if (replace)
            replaceOne(backward)
        else
            next(backward)
    }

    // Two columns, so both fields share a width, and each row's buttons sit at
    // their natural size against the right edge: ✕ lines up with Replace all.
    GridLayout {
        id: column
        anchors.fill: parent
        anchors.margins: 6
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        columns: 2
        rowSpacing: 6
        columnSpacing: 8

        FindField {
            id: findField
            Layout.fillWidth: true
            placeholder: qsTr("Find")
            hint: bar.replaced.length > 0 ? bar.replaced
                : text.length === 0 ? ""
                : bar.matches === 0 ? qsTr("No matches") : qsTr("%n matches", "", bar.matches)
            hintColor: bar.replaced.length === 0 && bar.matches === 0 ? theme.red : theme.secondaryForeground
            onTextEdited: {
                bar.replaced = ""
                bar.recount()
                // Find as you type, from where the current match starts.
                const found = editing.find(text, editor.area.selectionStart, false, bar.caseSensitive)
                if (found.length === 2)
                    editor.select(found[0], found[1])
            }
            Keys.onReturnPressed: function(event) { bar.submit(event, false) }
            Keys.onEnterPressed: function(event) { bar.submit(event, false) }
            Keys.onEscapePressed: bar.hide()
            Keys.onTabPressed: if (bar.replacing) replaceField.forceActiveFocus()
            Keys.onBacktabPressed: if (bar.replacing) replaceField.forceActiveFocus()
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 4
            BarButton {
                text: "Aa"
                checkable: true
                checked: bar.caseSensitive
                onClicked: bar.caseSensitive = checked
                tooltip: qsTr("Match case")
            }
            BarButton { text: "↑"; onClicked: bar.next(true); tooltip: qsTr("Previous (Shift + Enter)") }
            BarButton { text: "↓"; onClicked: bar.next(false); tooltip: qsTr("Next (Enter)") }
            BarButton { text: "✕"; onClicked: bar.hide(); tooltip: qsTr("Close (Escape)") }
        }

        FindField {
            id: replaceField
            visible: bar.replacing
            Layout.fillWidth: true
            placeholder: qsTr("Replace with")
            enabled: doc.editable
            Keys.onReturnPressed: function(event) { bar.submit(event, true) }
            Keys.onEnterPressed: function(event) { bar.submit(event, true) }
            Keys.onEscapePressed: bar.hide()
            Keys.onTabPressed: findField.forceActiveFocus()
            Keys.onBacktabPressed: findField.forceActiveFocus()
        }

        RowLayout {
            visible: bar.replacing
            Layout.alignment: Qt.AlignRight
            spacing: 4
            BarButton {
                text: qsTr("Replace")
                enabled: doc.editable && findField.text.length > 0
                onClicked: bar.replaceOne(false)
            }
            BarButton {
                text: qsTr("Replace all")
                enabled: doc.editable && findField.text.length > 0
                onClicked: bar.replaceAll()
            }
        }
    }
}

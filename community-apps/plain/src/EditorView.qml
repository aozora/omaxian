import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// The text, its line numbers and its scrollbars. The TextArea's document is
// the one Document and Editing work on; nothing here ever sets its text.
Item {
    id: view

    property int fontSize: 12
    property bool wrap: false
    readonly property alias area: area
    readonly property int currentLine: editing.lineOf(area.cursorPosition)

    // The first and last line numbers on screen, so the gutter draws only
    // those however long the file is.
    property int firstLine: 1
    property int lastLine: 1

    function focusText() { area.forceActiveFocus() }

    function goToLine(line) {
        area.cursorPosition = editing.positionOfLine(line)
        focusText()
    }

    function toggleComment() { editing.toggleComment(area.selectionStart, area.selectionEnd) }

    function select(start, end) { area.select(start, end) }

    function updateVisibleLines() {
        firstLine = editing.lineOf(area.positionAt(0, flick.contentY))
        lastLine = editing.lineOf(area.positionAt(0, flick.contentY + flick.height))
    }

    FontMetrics {
        id: metrics
        font: area.font
    }

    Connections {
        target: doc
        // A reload from disk keeps the cursor on the same line.
        property int line: 1
        function onAboutToReload() { line = editing.lineOf(area.cursorPosition) }
        function onReloaded() { area.cursorPosition = editing.positionOfLine(line) }
        function onFileChanged() { view.updateVisibleLines() }
    }

    Rectangle {
        id: gutter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        // Reading area.length re-evaluates this as the text changes, so the
        // width follows the number of digits in the line count.
        width: { area.length; return Math.max(3, String(editing.lineCount()).length) * metrics.averageCharacterWidth + 28 }
        color: theme.background
        clip: true

        Repeater {
            model: Math.max(0, view.lastLine - view.firstLine + 1)
            delegate: Text {
                required property int index
                readonly property int line: view.firstLine + index
                // Re-read when anything moves the lines.
                y: { flick.contentY; area.contentHeight; area.width; return area.positionToRectangle(editing.positionOfLine(line)).y - flick.contentY }
                anchors.right: parent.right
                anchors.rightMargin: 14
                text: line
                font: area.font
                color: line === view.currentLine ? theme.foreground : theme.secondaryForeground
                opacity: line === view.currentLine ? 1 : 0.6
            }
        }
    }

    Flickable {
        id: flick
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: gutter.right
        anchors.right: parent.right
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Wrapping text is as wide as the view. Following the text's own
        // width instead would keep it at the longest unwrapped line after
        // wrap was turned off and on again, so it never wrapped again.
        contentWidth: view.wrap ? width : area.implicitWidth
        contentHeight: area.implicitHeight
        onContentYChanged: view.updateVisibleLines()
        onHeightChanged: view.updateVisibleLines()

        // Shown whenever there's more to scroll to, not only while scrolling.
        ScrollBar.vertical: ScrollBar { policy: flick.visibleArea.heightRatio < 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }
        ScrollBar.horizontal: ScrollBar { policy: flick.visibleArea.widthRatio < 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff }

        TextArea.flickable: TextArea {
            id: area
            textFormat: TextEdit.PlainText
            wrapMode: view.wrap ? TextEdit.Wrap : TextEdit.NoWrap
            readOnly: !doc.editable
            persistentSelection: true
            selectByMouse: true
            font.family: "monospace"
            font.pixelSize: view.fontSize
            color: theme.foreground
            selectionColor: win.tint(theme.accent, 0.35)
            selectedTextColor: theme.brightForeground
            tabStopDistance: metrics.averageCharacterWidth * 4
            leftPadding: 4
            rightPadding: 24
            topPadding: 16
            bottomPadding: 8
            background: Rectangle { color: theme.background }

            // The current line, faintly. A child of the text (beneath it)
            // rather than of the background, which TextArea.flickable places
            // outside the text's coordinates, so it would sit off by the padding.
            Rectangle {
                z: -1
                x: 0
                width: Math.max(area.width, flick.width) - 16
                y: area.cursorRectangle.y
                height: area.cursorRectangle.height
                color: win.tint(theme.foreground, 0.05)
                visible: area.selectionStart === area.selectionEnd
            }
            onContentHeightChanged: view.updateVisibleLines()
            onWidthChanged: view.updateVisibleLines()

            // Keys the editor handles itself. Left alone while an input
            // method is composing, so it can use Enter, Tab and Escape.
            Keys.onPressed: function(event) {
                if (area.inputMethodComposing || area.readOnly)
                    return
                const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && plain) {
                    // Shift+Enter too: a TextEdit would insert U+2028 there,
                    // which isn't a line break in a file.
                    area.cursorPosition = editing.newline(area.selectionStart, area.selectionEnd)
                    event.accepted = true
                } else if (event.key === Qt.Key_Tab && plain) {
                    // Across lines Tab indents them; within one it types the
                    // indentation over any selection, like any other key.
                    if (editing.lineOf(area.selectionStart) !== editing.lineOf(area.selectionEnd))
                        editing.indent(area.selectionStart, area.selectionEnd)
                    else
                        area.cursorPosition = editing.replace(area.selectionStart, area.selectionEnd, doc.indentUnit)
                    event.accepted = true
                } else if (event.key === Qt.Key_Backtab) {
                    editing.outdent(area.selectionStart, area.selectionEnd)
                    event.accepted = true
                }
            }
            Keys.onEscapePressed: function(event) {
                if (findBar.visible)
                    findBar.hide()
                else if (doc.problem !== "None")
                    doc.dismissProblem()
                else
                    event.accepted = false
            }
        }
    }
}

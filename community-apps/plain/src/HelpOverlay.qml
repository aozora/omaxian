import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Every shortcut, one keypress away (F1).
Rectangle {
    id: overlay

    signal dismissed()

    color: Qt.rgba(0, 0, 0, 0.55)

    // While it shows, the keys scroll it and type nothing behind it; the
    // window's shortcuts, like F1 and Escape to close it, still work.
    Keys.onPressed: function(event) {
        const step = Math.round(theme.textSize * 2)
        const page = Math.max(step, list.height - step)
        const by = event.key === Qt.Key_Down ? step : event.key === Qt.Key_Up ? -step
                 : event.key === Qt.Key_PageDown ? page : event.key === Qt.Key_PageUp ? -page
                 : event.key === Qt.Key_End ? list.contentHeight : event.key === Qt.Key_Home ? -list.contentHeight : 0
        list.contentY = Math.max(0, Math.min(list.contentHeight - list.height, list.contentY + by))
        event.accepted = true
    }

    property var shortcuts: [
        ["Ctrl + S", qsTr("Save")],
        ["Ctrl + Shift + S", qsTr("Save as")],
        ["Ctrl + O", qsTr("Open")],
        ["Ctrl + N", qsTr("New file, or new window")],
        ["Ctrl + Shift + N", qsTr("New folder")],
        ["Ctrl + B", qsTr("Show or hide files")],
        ["Ctrl + Tab", qsTr("Between files and text")],
        ["F2", qsTr("Rename in files")],
        ["Delete", qsTr("Delete from files")],
        ["Alt + Enter", qsTr("Rename, duplicate or delete in files")],
        ["Ctrl + Z / Ctrl + Shift + Z", qsTr("Undo / redo")],
        ["Ctrl + F", qsTr("Find")],
        ["Ctrl + H", qsTr("Find and replace")],
        ["Ctrl + H " + qsTr("in files"), qsTr("Show or hide hidden files")],
        ["Enter / Shift + Enter", qsTr("Next / previous match")],
        ["Ctrl + Enter", qsTr("Replace all")],
        ["Page Up / Page Down", qsTr("A screenful up or down")],
        ["Ctrl + G", qsTr("Go to line")],
        ["Ctrl + /", qsTr("Comment or uncomment")],
        ["Tab / Shift + Tab", qsTr("Indent / outdent")],
        ["Alt + Z", qsTr("Word wrap")],
        ["Ctrl + Plus / Ctrl + Minus", qsTr("Text size")],
        ["Ctrl + W", qsTr("Close")],
        ["F1", qsTr("Show these shortcuts")]
    ]

    MouseArea { anchors.fill: parent; onClicked: overlay.dismissed() }

    DialogBackground {
        anchors.centerIn: parent
        width: Math.min(parent.width - 64, 560)
        // As tall as the list, or as the window allows, with the rest a
        // scroll away.
        height: Math.min(parent.height - 48, title.implicitHeight + content.spacing + grid.implicitHeight + 56)

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 28
            spacing: 14

            Label { id: title; text: qsTr("Keyboard shortcuts"); color: theme.brightForeground; font.pixelSize: Math.round(theme.textSize * 1.333); font.weight: Font.DemiBold }

            Flickable {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: grid.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ThinScrollBar { ratio: list.visibleArea.heightRatio }

            GridLayout {
                id: grid
                width: list.width
                columns: 2
                rowSpacing: 10
                columnSpacing: 28
                Repeater {
                    model: overlay.shortcuts
                    delegate: Label {
                        required property var modelData
                        required property int index
                        Layout.row: index
                        Layout.column: 0
                        text: modelData[0]
                        color: theme.accent
                    }
                }
                Repeater {
                    model: overlay.shortcuts
                    delegate: Label {
                        required property var modelData
                        required property int index
                        Layout.row: index
                        Layout.column: 1
                        Layout.fillWidth: true
                        // Wrapped, rather than run past the panel's edge.
                        wrapMode: Text.Wrap
                        text: modelData[1]
                        color: theme.foreground
                    }
                }
            }
            }
        }
    }
}

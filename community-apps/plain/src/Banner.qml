import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

// What's wrong with the file, and the way forward. Document names the
// situation; the words and the buttons are here.
Rectangle {
    id: banner

    signal saveAsRequested()
    signal done()

    readonly property string problem: doc.problem
    readonly property string detail: doc.problemDetail
    readonly property bool warning: ["MixedEndings", "ChangedOnDisk"].indexOf(problem) < 0

    visible: problem !== "None"
    implicitHeight: row.implicitHeight + 16
    color: win.tint(warning ? theme.red : theme.accent, 0.14)

    readonly property string message: {
        switch (problem) {
        case "NotFound": return qsTr("The folder for %1 doesn't exist.").arg(detail)
        case "NotRegular": return qsTr("%1 isn't a file Text Editor can open.").arg(detail)
        case "NotReadable": return qsTr("You don't have permission to read %1. To edit it as administrator, run sudoedit in a terminal.").arg(detail)
        case "NotText": return qsTr("%1 isn't a UTF-8 text file, so Text Editor didn't open it.").arg(detail)
        case "TooLarge": return qsTr("%1 is large or has very long lines. Text Editor is made for config files and may be slow with it.").arg(detail)
        case "MixedEndings": return qsTr("This file mixes Windows and Unix line endings. Saving will use %1 throughout.").arg(doc.lineEnding)
        case "ChangedOnDisk": return qsTr("%1 changed on disk.").arg(detail)
        case "DeletedOnDisk": return qsTr("%1 was deleted on disk.").arg(detail)
        case "Conflict": return qsTr("%1 changed on disk since you opened it. Saving would overwrite those changes.").arg(detail)
        case "Retargeted": return qsTr("This link now points to %1.").arg(detail)
        case "NotWritable": return qsTr("You don't have permission to change %1. To edit it as administrator, run sudoedit in a terminal.").arg(detail)
        case "NeedsInPlace": return qsTr("Text Editor can't replace this file safely because %1. Overwriting it in place is safe unless the save is interrupted.").arg(detail)
        case "SaveFailed": return qsTr("Couldn't save: %1").arg(detail)
        case "ModeLost": return qsTr("Saved %1, but couldn't restore its special permission bits.").arg(detail)
        }
        return ""
    }

    readonly property bool canSudoedit: problem === "NotReadable" || problem === "NotWritable"

    // QtQuick has no clipboard API; a hidden TextEdit's copy() is the way.
    TextEdit {
        id: clipboard
        visible: false
        function copyText(text) { clipboard.text = text; clipboard.selectAll(); clipboard.copy() }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: 8
        anchors.leftMargin: 14
        spacing: 8

        Label {
            Layout.fillWidth: true
            text: banner.message
            color: theme.foreground
            wrapMode: Text.Wrap
        }
        DialogButton {
            visible: banner.canSudoedit
            text: qsTr("Copy command")
            onClicked: clipboard.copyText("sudoedit '" + doc.path.replace(/'/g, "'\\''") + "'")
        }
        DialogButton {
            visible: banner.problem === "TooLarge"
            text: qsTr("Open anyway")
            onClicked: { doc.openAnyway(); banner.done() }
        }
        DialogButton {
            visible: banner.problem === "ChangedOnDisk" || banner.problem === "Conflict"
            text: qsTr("Reload")
            onClicked: { doc.reload(); banner.done() }
        }
        DialogButton {
            visible: banner.problem === "ChangedOnDisk"
            text: qsTr("Keep mine")
            onClicked: { doc.keepMine(); banner.done() }
        }
        DialogButton {
            visible: banner.problem === "Conflict" || banner.problem === "DeletedOnDisk"
            text: banner.problem === "DeletedOnDisk" ? qsTr("Save again") : qsTr("Overwrite")
            onClicked: { doc.overwrite(); banner.done() }
        }
        DialogButton {
            visible: banner.problem === "Retargeted"
            text: qsTr("Save there")
            onClicked: { doc.overwrite(); banner.done() }
        }
        DialogButton {
            visible: banner.problem === "NeedsInPlace"
            text: qsTr("Overwrite in place")
            onClicked: { doc.overwriteInPlace(); banner.done() }
        }
        DialogButton {
            visible: ["NotWritable", "NeedsInPlace", "Retargeted", "SaveFailed"].indexOf(banner.problem) >= 0
            text: qsTr("Save as…")
            onClicked: banner.saveAsRequested()
        }
        ToolButton {
            text: "✕"
            flat: true
            onClicked: {
                if (banner.problem === "DeletedOnDisk")
                    doc.keepMine()
                else
                    doc.dismissProblem()
                banner.done()
            }
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Dismiss (Escape)")
        }
    }
}

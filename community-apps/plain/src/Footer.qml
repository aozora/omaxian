import QtQuick
import QtQuick.Controls

// The quiet strip under the text, laid out like Omawrite's: the file's path
// on the left, with a lock when saving it needs sudo, and Save, Open and the
// shortcuts on the right. No background of its own, and faded until needed.
// While the files are hidden, the icon that shows them leads the path; while
// they show, the sidebar has its own at its foot.
Item {
    id: footer

    property bool sidebarButton: true

    signal sidebarRequested()
    signal saveRequested()
    signal openRequested()
    signal helpRequested()

    implicitHeight: 32

    readonly property color muted: theme.secondaryForeground

    Row {
        anchors.left: parent.left
        anchors.right: actions.left
        anchors.leftMargin: 14
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        FooterIconButton {
            id: sidebarButton
            objectName: "sidebarButton"
            visible: footer.sidebarButton
            iconName: "sidebar"
            iconColor: footer.muted
            opacity: 0.55
            tooltip: qsTr("Files (Ctrl+B)")
            onClicked: footer.sidebarRequested()
        }

        Label {
            id: path
            opacity: 0.55
            width: Math.min(implicitWidth, parent.width
                - (lock.visible ? lock.width + parent.spacing : 0)
                - (sidebarButton.visible ? sidebarButton.width + parent.spacing : 0))
            height: 16
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideMiddle
            textFormat: Text.PlainText
            text: doc.displayPath.length > 0 ? doc.displayPath : qsTr("Untitled")
            color: footer.muted
        }

        FooterIconButton {
            id: lock
            visible: doc.locked
            opacity: 0.55
            iconName: "lock"
            iconColor: footer.muted
            tooltip: qsTr("Saving this file needs administrator rights: use sudoedit")
        }
    }

    Row {
        id: actions
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        // Brighter while there are unsaved changes, the way the title's dot is.
        FooterIconButton {
            objectName: "saveButton"
            iconName: "save"
            iconColor: doc.modified ? theme.foreground : footer.muted
            opacity: doc.modified ? 0.9 : 0.55
            tooltip: qsTr("Save (Ctrl+S)")
            onClicked: footer.saveRequested()
        }

        FooterIconButton {
            objectName: "openButton"
            iconName: "open"
            iconColor: footer.muted
            opacity: 0.55
            tooltip: qsTr("Open (Ctrl+O)")
            onClicked: footer.openRequested()
        }

        FooterIconButton {
            objectName: "helpButton"
            iconName: "help"
            iconColor: footer.muted
            opacity: 0.55
            tooltip: qsTr("Keyboard shortcuts (F1)")
            onClicked: footer.helpRequested()
        }
    }
}

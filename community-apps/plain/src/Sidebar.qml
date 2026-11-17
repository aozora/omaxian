import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The files of a folder, beside the text: the folder Plain was opened on, or
// the open file's. Folders fold open in place; a file opens in the editor,
// asking first about unsaved changes as Open does. Files and folders drag
// into other folders, and new ones (Ctrl+N, Ctrl+Shift+N) go where the keys
// are. The full height of the window, with the icon that hides it
// at its foot, where the footer is.
Rectangle {
    id: sidebar

    signal openRequested(string path)
    // Why something asked of the files didn't happen, for Main to show.
    signal problem(string message)
    // Delete and Rename: Main asks first, and names.
    signal deleteRequested(string path)
    signal renameRequested(string path)
    signal hideRequested()
    // Escape: back to the text.
    signal done()

    // How far a row's color and ring stay in from each side.
    readonly property int rowInset: 6

    // Dragged wider or narrower by its edge, for as long as Plain is open.
    property real preferredWidth: 232
    // The row the keys are on, kept by path across a refresh from disk.
    property string currentPath: ""
    readonly property bool treeFocused: list.activeFocus
    // Letters typed in the tree, to jump to the name they start; forgotten
    // after a pause.
    property string typed: ""

    color: theme.darkBackground

    function focusTree() {
        if (list.currentIndex < 0 && list.count > 0)
            list.currentIndex = 0
        list.forceActiveFocus()
    }

    // Opens the folders down to a path and puts the keys on it.
    function reveal(path) {
        const row = files.reveal(path)
        if (row >= 0) {
            list.currentIndex = row
            list.positionViewAtIndex(row, ListView.Contain)
            // Again once laid out: just shown, the list has no height yet
            // to scroll a row near the end into.
            Qt.callLater(() => { if (list.currentIndex >= 0) list.positionViewAtIndex(list.currentIndex, ListView.Contain) })
        }
    }

    // Where a new file or folder goes: into the folder the keys are on, or
    // beside the file they're on.
    function newItemFolder() { return files.folderAt(list.currentIndex) }

    // Moves a file or folder into a folder; the open file follows, edits
    // and all. By path: the rows can be rebuilt from disk mid-drag.
    function moveInto(from, folder) {
        const moved = files.move(from, folder)
        if (moved.error) {
            sidebar.problem(moved.error)
            return
        }
        if (moved.path !== from)
            doc.relocate(from, moved.path)
        reveal(moved.path)
    }

    function duplicate(path) {
        const made = files.duplicate(path)
        if (made.error)
            sidebar.problem(made.error)
        else
            reveal(made.path)
    }

    // Rename, Duplicate and Delete for a row: right-click, or Alt+Return
    // (or the menu key) in the files, which puts it below the row with
    // Rename picked, ready for Enter.
    function openMenu(row, item, x, y, fromKeys) {
        if (row < 0)
            return
        list.currentIndex = row
        rowMenu.path = files.pathAt(row)
        rowMenu.popup(item, x, y)
        if (fromKeys)
            rowMenu.currentIndex = 0
    }

    // A folder folds open or closed; a file opens.
    function activate(row) {
        if (row < 0)
            return
        list.currentIndex = row
        if (files.isFolder(row)) {
            files.toggle(row)
            focusTree()
        } else {
            sidebar.openRequested(files.pathAt(row))
        }
    }

    function jumpTo(text) {
        const letter = text.toLowerCase()
        // The same letter again steps to the next name it starts, rather
        // than looking for a name starting with it twice.
        typed = typed === letter ? letter : typed + letter
        typingPause.restart()
        // A first letter looks past the row the keys are on.
        const start = typed.length === 1 ? list.currentIndex + 1 : list.currentIndex
        const row = files.find(typed, start)
        if (row >= 0) {
            list.currentIndex = row
            list.positionViewAtIndex(row, ListView.Contain)
        }
    }

    Timer { id: typingPause; interval: 800; onTriggered: sidebar.typed = "" }

    Connections {
        target: doc
        // Only when it's another file: a reload from disk mustn't reopen
        // folders or move the keys.
        property string shown: ""
        function onFileChanged() {
            if (doc.path !== shown && sidebar.visible)
                sidebar.reveal(doc.path)
            shown = doc.path
        }
    }

    Connections {
        target: files
        function onRefreshed() {
            // A drag whose file has gone has nothing left to drop.
            if (dragProxy.Drag.active && files.indexOf(dragProxy.path) < 0)
                dragProxy.Drag.active = false
            const row = files.indexOf(sidebar.currentPath)
            list.currentIndex = row >= 0 ? row : Math.min(list.currentIndex, list.count - 1)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ListView {
            id: list
            objectName: "fileList"
            Layout.fillWidth: true
            Layout.fillHeight: true
            topMargin: 13
            bottomMargin: 8
            clip: true
            model: files
            currentIndex: -1
            keyNavigationEnabled: true
            boundsBehavior: Flickable.StopAtBounds
            // The keys' row is brought into view at once, not scrolled to.
            highlightFollowsCurrentItem: false
            highlightMoveDuration: 0
            highlightResizeDuration: 0
            onCurrentIndexChanged: {
                sidebar.currentPath = files.pathAt(currentIndex)
                if (currentIndex >= 0)
                    positionViewAtIndex(currentIndex, ListView.Contain)
            }

            ScrollBar.vertical: ThinScrollBar { id: listBar; ratio: list.visibleArea.heightRatio }

            // Dropped below the rows: into the top folder.
            DropArea {
                parent: list
                anchors.fill: parent
                z: -1
                keys: ["plain-file"]
                onDropped: function(drop) { Qt.callLater(sidebar.moveInto, drop.source.path, files.root) }
            }

            Keys.onPressed: function(event) {
                const row = list.currentIndex
                if (event.key === Qt.Key_Right) {
                    // Opens a folder, then steps into it.
                    if (files.isFolder(row) && !files.isExpanded(row))
                        files.expand(row)
                    else if (files.isExpanded(row) && row + 1 < list.count)
                        list.currentIndex = row + 1
                } else if (event.key === Qt.Key_Left) {
                    // Folds a folder, then steps out to the one it's in.
                    if (files.isExpanded(row))
                        files.collapse(row)
                    else if (files.parentOf(row) >= 0)
                        list.currentIndex = files.parentOf(row)
                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.AltModifier)
                           || event.key === Qt.Key_Menu) {
                    if (list.currentItem)
                        sidebar.openMenu(row, list.currentItem, 24, list.currentItem.height, true)
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    sidebar.activate(row)
                } else if (event.key === Qt.Key_F2) {
                    if (row >= 0)
                        sidebar.renameRequested(files.pathAt(row))
                } else if (event.key === Qt.Key_Home) {
                    list.currentIndex = 0
                } else if (event.key === Qt.Key_End) {
                    list.currentIndex = list.count - 1
                } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                    const page = Math.max(1, Math.floor(list.height / Math.round(theme.textSize * 2)) - 1)
                    list.currentIndex = Math.max(0, Math.min(list.count - 1, row + (event.key === Qt.Key_PageUp ? -page : page)))
                } else if (event.key === Qt.Key_Delete) {
                    if (row >= 0)
                        sidebar.deleteRequested(files.pathAt(row))
                } else if (/^[^\x00-\x20\x7f]+$/.test(event.text)
                           && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                    // Printable letters only: Delete and Backspace carry
                    // control characters as their text.
                    sidebar.jumpTo(event.text)
                } else if (event.key === Qt.Key_Escape) {
                    sidebar.done()
                } else {
                    return
                }
                event.accepted = true
            }

            delegate: Item {
                id: row

                required property int index
                required property string name
                required property string path
                required property int depth
                required property bool folder
                required property bool expanded
                required property bool hidden

                // Where a row dropped here goes: into a folder, or beside a file.
                readonly property string dropFolder: folder ? path : (path.substring(0, path.lastIndexOf("/")) || "/")

                readonly property bool open: !folder && path === doc.path
                readonly property color ink: open ? theme.brightForeground : theme.foreground

                // Short of the scrollbar's thumb, not its padded track, so the
                // inset to it matches the inset from the sidebar's edge.
                width: ListView.view.width - (listBar.visible ? listBar.width - listBar.leftPadding : 0)
                height: Math.round(theme.textSize * 2)

                // Every row's color and ring sit inset by the same margin on
                // both sides, clear of the window's edge and the scrollbar.
                Rectangle {
                    id: rowColor
                    anchors.fill: parent
                    anchors.leftMargin: sidebar.rowInset
                    anchors.rightMargin: sidebar.rowInset
                    radius: Math.min(3, theme.radius)
                    // Where the keys are, while they're in the tree.
                    border.width: row.ListView.isCurrentItem && list.activeFocus ? 1 : 0
                    border.color: theme.accent
                    color: drop.containsDrag ? win.tint(theme.accent, 0.3)
                         : row.open ? win.tint(theme.accent, 0.22)
                         : row.ListView.isCurrentItem && list.activeFocus ? win.tint(theme.foreground, 0.08)
                         : hover.containsMouse ? win.tint(theme.foreground, 0.04)
                         : "transparent"
                }

                // The open file's edge, in the accent, inside its color.
                Rectangle {
                    visible: row.open
                    anchors.left: rowColor.left
                    width: 2
                    height: parent.height
                    color: theme.accent
                }

                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: sidebar.rowInset + 6 + row.depth * 16
                    anchors.rightMargin: sidebar.rowInset + 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Item {
                        width: 16
                        height: 16
                        LineIcon {
                            visible: row.folder
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            name: "chevron"
                            color: theme.secondaryForeground
                            rotation: row.expanded ? 90 : (sidebar.LayoutMirroring.enabled ? 180 : 0)
                        }
                    }

                    Item { width: 2; height: 1 }

                    LineIcon {
                        width: 15
                        height: 15
                        anchors.verticalCenter: parent.verticalCenter
                        name: row.folder ? "folder" : "file"
                        color: row.open ? theme.accent : theme.secondaryForeground
                        opacity: row.open ? 1 : row.hidden ? 0.5 : 0.8
                    }

                    Item { width: 7; height: 1 }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 40
                        text: row.name
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        color: row.ink
                        // Hidden ones fainter, as they're shown only on asking.
                        opacity: row.open ? 1 : row.hidden ? 0.55 : 0.85
                    }
                }

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton)
                            sidebar.openMenu(row.index, row, mouse.x, mouse.y, false)
                        else
                            sidebar.activate(row.index)
                    }

                    // Dragged onto a folder (or a file in one) to move there.
                    drag.target: pressedButtons & Qt.LeftButton ? dragProxy : null
                    drag.threshold: 6
                    onPressed: function(mouse) {
                        const at = row.mapToItem(sidebar, 0, 0)
                        dragProxy.x = at.x
                        dragProxy.y = at.y
                        dragProxy.path = row.path
                        dragProxy.name = row.name
                        dragProxy.folder = row.folder
                        dragProxy.Drag.hotSpot.x = mouse.x
                        dragProxy.Drag.hotSpot.y = mouse.y
                    }
                    drag.onActiveChanged: if (drag.active) dragProxy.Drag.active = true
                    onReleased: {
                        if (dragProxy.Drag.active) {
                            dragProxy.Drag.drop()
                            dragProxy.Drag.active = false
                        }
                    }
                }

                DropArea {
                    id: drop
                    anchors.fill: parent
                    keys: ["plain-file"]
                    // After the drop finishes: moving rebuilds the rows,
                    // this one and the dragged one included.
                    onDropped: function(event) {
                        event.accept()
                        Qt.callLater(sidebar.moveInto, event.source.path, row.dropFolder)
                    }
                }
            }
        }

        // The sidebar's foot, level with the footer: the icon that hides it.
        Item {
            Layout.fillWidth: true
            implicitHeight: 32

            FooterIconButton {
                objectName: "hideSidebarButton"
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                iconName: "sidebarOpen"
                iconColor: theme.secondaryForeground
                opacity: 0.7
                tooltip: qsTr("Hide files (Ctrl+B)")
                onClicked: sidebar.hideRequested()
            }
        }
    }

    // A menu item the size of a row in the files, rather than Material's
    // touch-sized one.
    component RowMenuItem: MenuItem {
        id: menuItem
        property string shortcut
        implicitHeight: Math.round(theme.textSize * 2.2)
        leftPadding: 12
        rightPadding: 12
        topPadding: 0
        bottomPadding: 0
        verticalPadding: 0
        contentItem: RowLayout {
            Label {
                Layout.fillWidth: true
                text: menuItem.text
                color: menuItem.highlighted ? theme.brightForeground : theme.foreground
            }
            Label {
                text: menuItem.shortcut
                color: theme.secondaryForeground
            }
        }
        background: Rectangle {
            color: menuItem.highlighted ? win.tint(theme.accent, 0.22) : "transparent"
        }
    }

    Menu {
        id: rowMenu
        objectName: "rowMenu"
        property string path: ""
        width: 200
        topPadding: 4
        bottomPadding: 4
        // There and gone at once: Plain animates nothing.
        enter: Transition {}
        exit: Transition {}
        background: DialogBackground {}
        // After the menu is gone, so a dialog it opens keeps the keys.
        onClosed: sidebar.focusTree()
        RowMenuItem {
            text: qsTr("Rename")
            shortcut: "F2"
            onTriggered: Qt.callLater(sidebar.renameRequested, rowMenu.path)
        }
        RowMenuItem {
            text: qsTr("Duplicate")
            onTriggered: Qt.callLater(sidebar.duplicate, rowMenu.path)
        }
        RowMenuItem {
            text: qsTr("Delete")
            shortcut: qsTr("Delete")
            onTriggered: Qt.callLater(sidebar.deleteRequested, rowMenu.path)
        }
    }

    // What's being dragged, following the pointer.
    Rectangle {
        id: dragProxy
        property string path: ""
        property string name: ""
        property bool folder: false
        visible: Drag.active
        z: 10
        width: proxyRow.implicitWidth + 20
        height: Math.round(theme.textSize * 2)
        radius: 3
        color: win.tint(theme.accent, 0.3)
        Drag.keys: ["plain-file"]
        Drag.source: dragProxy

        Row {
            id: proxyRow
            anchors.centerIn: parent
            spacing: 7
            LineIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 15
                height: 15
                name: dragProxy.folder ? "folder" : "file"
                color: theme.accent
            }
            Label {
                text: dragProxy.name
                textFormat: Text.PlainText
                color: theme.brightForeground
            }
        }
    }

    // The line between it and the text, and the edge that resizes it.
    Rectangle {
        anchors.right: parent.right
        width: 1
        height: parent.height
        color: win.tint(theme.foreground, 0.08)
    }

    MouseArea {
        anchors.right: parent.right
        anchors.rightMargin: -3
        width: 7
        height: parent.height
        cursorShape: Qt.SplitHCursor
        property real startX: 0
        property real startWidth: 0
        onPressed: function(mouse) {
            startX = mapToItem(null, mouse.x, 0).x
            startWidth = sidebar.preferredWidth
        }
        onPositionChanged: function(mouse) {
            const moved = mapToItem(null, mouse.x, 0).x - startX
            const width = startWidth + (sidebar.LayoutMirroring.enabled ? -moved : moved)
            sidebar.preferredWidth = Math.max(140, Math.min(width, win.width - 280))
        }
    }
}

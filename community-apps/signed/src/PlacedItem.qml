import QtQuick
import Signed

// A placed signature or text: drag it to move, drag the corner to scale,
// double-click text to edit it.
Item {
    id: view

    required property int index
    required property var model
    property int pageIndex: 0
    property real viewScale: 1
    property color accent: "#FFD60A"

    // Every page repeats every item and shows only its own, so only the copy
    // on the item's page may be selected or edited.
    readonly property bool onPage: model.page === pageIndex
    readonly property bool isText: model.kind === "text"
    readonly property bool selected: onPage && win.selected === index
    readonly property bool editing: onPage && win.editingRow === index
    readonly property var items: backend.items

    visible: onPage
    x: model.itemX * viewScale
    y: model.itemY * viewScale
    width: model.itemWidth * viewScale
    height: model.itemHeight * viewScale
    z: selected ? 2 : 1

    Image {
        visible: !view.isText
        anchors.fill: parent
        source: view.model.imageSource
        smooth: true
        mipmap: true
    }

    TextItem {
        visible: view.isText && !view.editing
        anchors.fill: parent
        text: view.model.text
        fontSize: view.model.fontSize
        zoom: view.viewScale
    }

    // Edits in place at the font's layout size, scaled to the page, so the
    // text doesn't jump when editing starts or stops.
    TextEdit {
        id: editor
        visible: view.editing
        enabled: view.editing
        x: 0
        y: 0
        transformOrigin: Item.TopLeft
        scale: view.model.fontSize * view.viewScale / 100
        font.family: "Noto Sans"
        font.pixelSize: 100
        font.hintingPreference: Font.PreferNoHinting
        color: "black"
        selectByMouse: true
        selectionColor: Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.4)
        selectedTextColor: "black"
        cursorDelegate: Rectangle { width: Math.max(2, 1.5 / editor.scale); color: view.accent }

        onTextChanged: if (view.editing) view.items.setText(view.index, text)
        onActiveFocusChanged: if (!activeFocus && view.editing) win.finishEditing()
        Keys.onPressed: (event) => {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                win.finishEditing();
                event.accepted = true;
            } else if (event.key === Qt.Key_Escape) {
                win.finishEditing();
                event.accepted = true;
            }
        }
    }

    onEditingChanged: {
        if (editing) {
            editor.text = view.model.text ?? "";
            editor.cursorPosition = editor.length;
            editor.forceActiveFocus();
        }
    }

    HoverHandler { id: hover }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        color: "transparent"
        radius: Math.min(2, theme.radius)
        border.width: 1.5
        border.color: view.selected || view.editing ? view.accent : Qt.rgba(view.accent.r, view.accent.g, view.accent.b, 0.5)
        visible: view.selected || view.editing || hover.hovered
    }

    MouseArea {
        id: mover
        anchors.fill: parent
        enabled: !view.editing
        // Otherwise the page list takes over the drag and scrolls instead.
        preventStealing: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point grab

        onPressed: (mouse) => {
            win.select(view.index);
            grab = Qt.point(mouse.x, mouse.y);
            view.items.beginChange();
        }
        onPositionChanged: (mouse) => {
            const p = mapToItem(view.parent, mouse.x, mouse.y);
            view.items.move(view.index, (p.x - grab.x) / view.viewScale, (p.y - grab.y) / view.viewScale);
        }
        onReleased: view.items.endChange()
        onCanceled: view.items.endChange()
        onDoubleClicked: if (view.isText) win.startEditing(view.index)
    }

    Rectangle {
        id: handle
        visible: view.selected && !view.editing
        width: 12
        height: 12
        radius: 6
        x: parent.width + 3 - width / 2
        y: parent.height + 3 - height / 2
        color: view.accent
        border.color: "white"
        border.width: 2

        MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            preventStealing: true
            cursorShape: Qt.SizeFDiagCursor
            property point start
            property real startWidth

            // Scales by how far the corner has moved since it was grabbed, so
            // grabbing slightly off the corner doesn't make the item jump.
            onPressed: (mouse) => {
                view.items.beginChange();
                start = mapToItem(view.parent, mouse.x, mouse.y);
                startWidth = view.model.itemWidth;
            }
            onPositionChanged: (mouse) => {
                const p = mapToItem(view.parent, mouse.x, mouse.y);
                const aspect = view.model.itemWidth / view.model.itemHeight;
                const dx = (p.x - start.x) / view.viewScale;
                const dy = (p.y - start.y) / view.viewScale * aspect;
                view.items.resize(view.index, startWidth + (Math.abs(dx) > Math.abs(dy) ? dx : dy));
            }
            onReleased: {
                view.items.endChange();
                backend.rememberSize(view.index);
            }
            onCanceled: view.items.endChange()
        }
    }
}

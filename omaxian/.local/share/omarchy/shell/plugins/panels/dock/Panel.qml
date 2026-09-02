// Panel.qml — omaxian.dock
// This is a stripped down port of https://github.com/rosakodu/omarchy-dock
// -------------------------------------------------------------------------------

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services
import "Model.js" as Model

// Dock MVP: a persistent bottom strip, not a bar-icon-plus-popup. One
// PanelWindow per screen, same shape as plugins/bar/Bar.qml's BarPanel —
// `exclusionMode: ExclusionMode.Auto` reserves real strut space (i3 tiles
// windows above it), and deliberately no `aboveWindows` override, so a
// fullscreen window covers the dock instead of the dock floating over it
// (the opposite of upstream omarchy-dock's WlrLayershell "always on top"
// behavior — not wanted here).
//
// Auto-loaded: kinds:["panel"] + keepLoaded:true (manifest.json) means the
// shell.qml panel Loader mounts this unconditionally, first-party-enabled by
// default — no shell.json entry.
Item {
    id: root

    // Injected by the host shell's panel Loader (shell.qml onLoaded block).
    property string omarchyPath: ""
    property var shell: null
    property var manifest: null

    readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
    readonly property int dockSize: Style.space(56)
    readonly property int iconSize: Style.space(36)

    // Flat array of desktop ids (Model.js — no stacks/folders in this MVP).
    property var pinned: []

    // Edit mode: entered by a 450ms press-hold on any icon, matching
    // upstream's trigger — but no wiggle animation (deliberately dropped, see
    // TODO.md). Only pinned icons are draggable while in it; a tap on the
    // dock's empty background exits it.
    property bool editMode: false

    // User-facing appearance settings — hand-edit ~/.config/omarchy/dock-settings.json:
    //   fullWidth       bool  dock spans the whole screen edge, or shrinks to a
    //                         centered pill sized to its icons (default true)
    //   roundedCorners  bool  rounded corners on the pill, only visible when
    //                         fullWidth is false (default false)
    //   hoverAnimation  bool  macOS-style scale-up-on-hover per icon (default true)
    property bool fullWidth: true
    property bool roundedCorners: false
    property bool hoverAnimation: true

    readonly property var dockItems: Model.buildDockItems(root.pinned, I3Windows.windows, root.appLibrary ? root.appLibrary.sortedEntries("") : [])

    function persistPinned() {
        pinnedFile.setText(Model.serializePinned(root.pinned));
    }

    function togglePinned(appId) {
        root.pinned = Model.togglePinned(root.pinned, appId);
        root.persistPinned();
    }

    function launchOrFocus(item) {
        if (item.running && item.windows.length > 0) {
            var target = item.windows[0];
            for (var i = 0; i < item.windows.length; i++) {
                if (item.windows[i].focused) {
                    target = item.windows[i];
                    break;
                }
            }
            I3Windows.focusWindow(target.conId);
            return;
        }
        if (root.appLibrary && item.entry)
            root.appLibrary.launch(item.entry);
    }

    // watchChanges is deliberately off: pinnedFile.setText() (persistPinned())
    // writes this same path, and a live watch on our own write races the read
    // back against the write — observed losing an in-app pin/unpin a moment
    // after it landed (togglePinned's own reload catching a stale/empty
    // read). In-app pin/unpin updates root.pinned directly and doesn't need
    // the watch; an external hand-edit of the file takes effect on the next
    // shell restart via onLoaded, which is an acceptable trade-off here.
    FileView {
        id: pinnedFile
        path: Quickshell.env("HOME") + "/.config/omarchy/dock-pinned.json"
        printErrors: false
        onLoaded: root.pinned = Model.parsePinned(text())
        onLoadFailed: root.pinned = []
    }

    // Read-only from this plugin's own perspective — no in-app UI writes these
    // (yet), so there's no self-write race to worry about; watching is safe
    // and lets an edit to the file take effect without a shell restart.
    FileView {
        id: settingsFile
        path: Quickshell.env("HOME") + "/.config/omarchy/dock-settings.json"
        watchChanges: true
        printErrors: false

        function apply(parsed) {
            root.fullWidth = parsed.fullWidth;
            root.roundedCorners = parsed.roundedCorners;
            root.hoverAnimation = parsed.hoverAnimation;
        }

        onLoaded: apply(Model.parseSettings(text()))
        onFileChanged: apply(Model.parseSettings(text()))
        onLoadFailed: apply(Model.parseSettings(""))
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            DockPanel {
                required property var modelData
                screen: modelData
            }
        }
    }

    component DockPanel: PanelWindow {
        id: dockWindow

        anchors {
            bottom: true
            left: true
            right: true
        }
        implicitHeight: root.dockSize
        exclusionMode: ExclusionMode.Auto
        color: "transparent"
        surfaceFormat.opaque: false
        // Full window width always (strut/exclusion reservation stays simple and
        // matches Bar.qml's already-proven behavior regardless of the fullWidth
        // setting); when fullWidth is off, only the pill area below actually
        // paints and accepts input — the mask below makes the rest click-through
        // so the wide-but-empty margin doesn't swallow input meant for whatever
        // tiles above this reserved strip.
        mask: root.fullWidth ? null : pillMask

        Region {
            id: pillMask
            item: pillBackground
        }

        Rectangle {
            id: pillBackground
            color: Color.background
            radius: (!root.fullWidth && root.roundedCorners) ? Style.radiusPopup : 0
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            width: root.fullWidth ? parent.width : Math.max(root.dockSize, iconRow.width + Style.space(24))
            Behavior on width {
                enabled: !root.fullWidth
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Tap the empty strip (nothing under the icons) to leave edit mode.
        MouseArea {
            anchors.fill: parent
            enabled: root.editMode
            onClicked: root.editMode = false
        }

        Item {
            id: iconRow
            readonly property int cellStep: root.iconSize + Style.space(10)
            anchors.centerIn: parent
            width: root.dockItems.length > 0 ? root.dockItems.length * cellStep - Style.space(10) : 0
            height: root.iconSize

            Repeater {
                model: root.dockItems

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index

                    width: root.iconSize
                    height: root.iconSize
                    z: dragArea.dragging ? 10 : (dragArea.containsMouse ? 5 : 0)

                    // macOS-style scale-up-on-hover, toggled by the hoverAnimation
                    // setting. Grows from the bottom edge (where the dock sits) rather
                    // than the center, matching the way the real thing reads.
                    transformOrigin: Item.Bottom
                    scale: (root.hoverAnimation && dragArea.containsMouse && !dragArea.dragging && !root.editMode) ? 1.3 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutBack
                        }
                    }

                    Binding {
                        target: cell
                        property: "x"
                        value: cell.index * iconRow.cellStep
                        when: !dragArea.dragging
                    }
                    Behavior on x {
                        enabled: !dragArea.dragging
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                    }

                    Rectangle {
                        // Edit-mode affordance, in place of upstream's wiggle animation:
                        // a border on draggable (pinned) icons, dimming on the rest.
                        anchors.fill: parent
                        anchors.margins: -Style.space(4)
                        radius: Style.cornerRadius
                        color: "transparent"
                        visible: root.editMode && cell.modelData.pinned
                        border.width: Math.max(1, Style.space(2))
                        border.color: Color.accent
                    }

                    Image {
                        anchors.fill: parent
                        // No matched desktop entry (unusual WM_CLASS, Flatpak id, …): fall
                        // back to the raw appId as an icon-theme name before iconSource()
                        // lands on the generic executable glyph.
                        source: root.appLibrary ? root.appLibrary.iconSource(cell.modelData.entry ? cell.modelData.entry.icon : String(cell.modelData.id || "")) : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                        asynchronous: true
                        // Decode at the largest painted size (hover scale 1.3) in
                        // physical pixels — a logical-size decode upscales blurry
                        // (same fix as Menu.qml / Tray.qml).
                        sourceSize.width: Math.ceil(root.iconSize * (root.hoverAnimation ? 1.3 : 1.0) * Screen.devicePixelRatio)
                        sourceSize.height: Math.ceil(root.iconSize * (root.hoverAnimation ? 1.3 : 1.0) * Screen.devicePixelRatio)
                        opacity: root.editMode && !cell.modelData.pinned ? 0.5 : 1
                    }

                    Rectangle {
                        visible: cell.modelData.running
                        width: Style.space(6)
                        height: Style.space(6)
                        radius: width / 2
                        color: cell.modelData.urgent ? Color.urgent : Color.accent
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -Style.space(6)
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        hoverEnabled: true

                        // Not MouseArea.drag: that arms drag.target only at press time, and
                        // this cell only becomes draggable *mid*-press (once the long-press
                        // timer below flips editMode) — a later drag.target change doesn't
                        // retroactively arm it. Tracked manually instead: grabOffsetX is
                        // the press point's offset from the cell's own x (in iconRow's
                        // stable frame, since cell.x itself moves during the drag), and
                        // every move recomputes cell.x from the current pointer position
                        // minus that fixed offset.
                        property bool longPressFired: false
                        property bool dragging: false
                        property real grabOffsetX: 0

                        onPressed: function (mouse) {
                            longPressFired = false;
                            dragging = false;
                            if (mouse.button === Qt.LeftButton) {
                                if (!root.editMode)
                                    longPressTimer.restart();
                                if (cell.modelData.pinned)
                                    grabOffsetX = mapToItem(iconRow, mouse.x, mouse.y).x - cell.x;
                            }
                        }

                        onPositionChanged: function (mouse) {
                            if (!root.editMode || !cell.modelData.pinned)
                                return;
                            if (!(mouse.buttons & Qt.LeftButton))
                                return;
                            dragging = true;
                            var posInRow = mapToItem(iconRow, mouse.x, mouse.y).x;
                            cell.x = Math.max(0, Math.min(iconRow.width - cell.width, posInRow - grabOffsetX));
                        }

                        onReleased: function (mouse) {
                            // Captured up front, as a plain JS reference rather than a bare
                            // `root` identifier: reassigning root.pinned (below) changes
                            // dockItems, which changes this Repeater's model, which
                            // destroys/recreates *this* delegate mid-callback — after that,
                            // any further `root.foo` *id lookup* throws "root is not
                            // defined" (its QQmlContext is gone), even deferred via
                            // Qt.callLater. A plain captured object reference keeps working
                            // because it's a direct pointer, not a context-relative lookup.
                            var app = root;

                            longPressTimer.stop();

                            if (dragging) {
                                // Read cell.x before clearing `dragging` — that flip re-arms
                                // the Binding above, which snaps cell.x back to its
                                // index-formula value synchronously, before the next line
                                // would otherwise run.
                                var targetIndex = Math.max(0, Math.min(app.pinned.length - 1, Math.round(cell.x / iconRow.cellStep)));
                                dragging = false;
                                var curIndex = app.pinned.indexOf(cell.modelData.id);
                                var draggedId = cell.modelData.id;
                                if (curIndex !== -1 && targetIndex !== curIndex) {
                                    Qt.callLater(function () {
                                        var arr = app.pinned.slice();
                                        var i = arr.indexOf(draggedId);
                                        if (i === -1)
                                            return;
                                        arr.splice(i, 1);
                                        arr.splice(Math.min(targetIndex, arr.length), 0, draggedId);
                                        app.pinned = arr;
                                        app.persistPinned();
                                    });
                                }
                                return;
                            }

                            if (longPressFired || app.editMode)
                                return;
                            if (mouse.button === Qt.RightButton) {
                                app.togglePinned(cell.modelData.id);
                            } else {
                                app.launchOrFocus(cell.modelData);
                            }
                        }

                        onCanceled: function () {
                            longPressTimer.stop();
                            dragging = false;
                        }

                        Timer {
                            id: longPressTimer
                            interval: 450
                            onTriggered: {
                                dragArea.longPressFired = true;
                                root.editMode = true;
                            }
                        }
                    }
                }
            }
        }
    }
}

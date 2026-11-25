import QtQuick
import QtQuick.Controls

// Popover with the shared card surface and a quick fade/scale entrance from its anchor edge.
Popup {
    id: root
    property bool fromBelow: true
    padding: theme.space.popupPadding
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    transformOrigin: fromBelow ? Popup.Top : Popup.Bottom
    background: OmPopupCard { padding: 0 }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: .96; to: 1; duration: 200; easing.type: Easing.OutQuint }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: 100; easing.type: Easing.InCubic }
        NumberAnimation { property: "scale"; to: .98; duration: 100; easing.type: Easing.InCubic }
    }
}

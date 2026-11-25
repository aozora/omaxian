import QtQuick
import QtQuick.Controls

Menu {
    id: root
    padding: 4
    margins: 8
    transformOrigin: Popup.Top
    background: OmPopupCard { padding: 0; implicitWidth: 180 }
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: .96; to: 1; duration: 200; easing.type: Easing.OutQuint }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; to: 0; duration: 100; easing.type: Easing.InCubic }
    }
    delegate: OmMenuItem { }
}

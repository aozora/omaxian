import QtQuick
import QtQuick.Effects

// Raised surface for popovers, menus, and dialogs: hairline edge and a soft drop shadow.
Item {
    id: root
    default property alias content: holder.children
    property int padding: theme.space.popupPadding
    property int radius: theme.cardRadius
    property color color: theme.raised
    property bool elevated: true
    implicitWidth: holder.childrenRect.width + padding * 2 + 2
    implicitHeight: holder.childrenRect.height + padding * 2 + 2

    Rectangle {
        id: shadowShape
        anchors.fill: parent
        radius: root.radius
        color: "black"
        visible: false
        layer.enabled: root.elevated
    }
    MultiEffect {
        visible: root.elevated
        anchors.fill: shadowShape
        source: shadowShape
        shadowEnabled: true
        shadowColor: theme.shadow
        shadowOpacity: 1
        shadowBlur: .9
        blurMax: 28
        shadowVerticalOffset: 8
        shadowScale: .98
        autoPaddingEnabled: true
        opacity: .9
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.color
        border.width: 1
        border.color: theme.strokeStrong
    }
    Item { id: holder; anchors.fill: parent; anchors.margins: root.padding + 1 }
}

import QtQuick
import QtQuick.Controls

// A slim scrollbar in the theme's text color, shown whenever there's more to
// scroll to: Material's is a wide gray slab that fades in and out.
ScrollBar {
    id: bar

    // Set to the view's visibleArea ratio for this direction.
    property real ratio: 1

    policy: ratio < 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
    padding: 2
    minimumSize: 0.05

    contentItem: Rectangle {
        implicitWidth: 6
        implicitHeight: 6
        radius: 3
        color: win.tint(theme.foreground, bar.pressed ? 0.4 : bar.hovered ? 0.3 : 0.18)
    }
    background: Item {}
}

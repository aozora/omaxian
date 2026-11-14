import QtQuick

// Every dialog's panel: the theme's background, a quiet border, and the
// corners Hyprland gives windows (sharp on Omarchy's default).
Rectangle {
    color: theme.background
    border.width: 1
    border.color: win.tint(theme.foreground, 0.16)
    radius: theme.radius
}

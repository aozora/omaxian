#pragma once

#include <QSize>

namespace hyprland {

// Asks Hyprland to resize this process's window and center it again. A
// floating window there keeps the size it opened at when the app resizes
// itself, showing what's drawn at the new size clipped to the old one; the
// compositor has to do it. False when this isn't Hyprland.
bool reshape(QSize size);

}  // namespace hyprland

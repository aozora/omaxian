import QtQuick
import QtQuick.Controls

// A tooltip that appears and goes at once: Material's fades in and out, and
// Plain animates nothing.
ToolTip {
    enter: Transition {}
    exit: Transition {}
}

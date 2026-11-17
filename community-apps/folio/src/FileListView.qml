import QtQuick
import QtQuick.Controls

// A folder's items one per row, as the list and each of the columns show
// them: clipped to its edges, scrolled by the wheel but not dragged, with
// Folio's scroll bar.
ListView {
    clip: true
    // Omaxian: Flickable.acceptedButtons is Qt 6.9+. Set it where it exists;
    // on Excalibur's Qt 6.8 a mouse drag flicks the view, as 6.8 always did.
    Component.onCompleted: if (acceptedButtons !== undefined) acceptedButtons = Qt.NoButton
    boundsBehavior: Flickable.StopAtBounds
    // No cache buffer, here or in the grid: Qt's 16 ms pause before filling
    // one can leave an idle window drawing every refresh.
    cacheBuffer: 0
    ScrollBar.vertical: FolioScrollBar { }
}

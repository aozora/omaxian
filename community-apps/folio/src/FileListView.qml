import QtQuick
import QtQuick.Controls

// A folder's items one per row, as the list and each of the columns show
// them: clipped to its edges, scrolled by the wheel but not dragged, with
// Folio's scroll bar.
ListView {
    id: view
    clip: true
    // Omaxian: Flickable.acceptedButtons is Qt 6.9+. Set it where it exists
    // (through the id: a bare name 6.8 lacks throws). On 6.8 the rubber band
    // keeps a drag on empty space from flicking (Band.qml, preventStealing).
    Component.onCompleted: if (view.acceptedButtons !== undefined) view.acceptedButtons = Qt.NoButton
    boundsBehavior: Flickable.StopAtBounds
    // No cache buffer, here or in the grid: Qt's 16 ms pause before filling
    // one can leave an idle window drawing every refresh.
    cacheBuffer: 0
    ScrollBar.vertical: FolioScrollBar { }
}

import QtQuick
import QtQuick.Dialogs

// Picks a video to insert at the playhead.
FileDialog {
    title: "Insert a video at the playhead"
    nameFilters: ["Videos (*.mp4 *.mov *.mkv *.webm *.m4v *.avi)", "All files (*)"]
    onAccepted: editor.insertMedia(selectedFile)
}

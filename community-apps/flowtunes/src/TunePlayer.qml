import QtQuick
import QtMultimedia

// Plays the tune it's given, and says when it has ended. Loaded only once
// there's a first tune, since Qt Multimedia takes a moment to start.
Item {
    id: root
    property url source
    property bool paused: false
    readonly property int position: player.position
    readonly property int duration: player.duration
    signal ended()
    signal failed(string why)
    // Moved in the tune by a seek, to here.
    signal sought(int position)

    function seek(fraction) {
        if (!player.seekable)
            return
        player.position = player.duration * fraction
        root.sought(player.duration * fraction)
    }
    function finish() {
        if (player.mediaStatus === MediaPlayer.EndOfMedia)
            root.ended()
    }
    // The player is given its tune here rather than by a binding, which
    // would hand it over only after this had told the old one to play.
    function sync() {
        if (player.source !== source)
            player.source = source
        if (source.toString() === "")
            player.stop()
        else if (paused)
            player.pause()
        else
            player.play()
    }
    onSourceChanged: sync()
    onPausedChanged: sync()
    Component.onCompleted: sync()

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {}
        // Said once the player is done ending: a next tune handed to it while
        // it's still stopping the last one is stopped along with it.
        onMediaStatusChanged: if (mediaStatus === MediaPlayer.EndOfMedia) Qt.callLater(root.finish)
        onErrorOccurred: (error, errorString) => root.failed(errorString)
    }
}

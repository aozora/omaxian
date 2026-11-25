import QtQuick
import QtMultimedia

// A clip playing in the frame with its sound, round and round; a click
// pauses and plays it. Loaded only once a clip is shown, since Qt Multimedia
// takes a moment to start.
Item {
    id: root
    property url source

    MediaPlayer {
        id: player
        source: root.source
        loops: MediaPlayer.Infinite
        audioOutput: AudioOutput {}
        videoOutput: output
        onSourceChanged: if (source.toString() !== "") play()
    }
    VideoOutput {
        id: output
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }
    TapHandler {
        onTapped: player.playbackState === MediaPlayer.PlayingState ? player.pause() : player.play()
    }
    Component.onCompleted: if (source.toString() !== "") player.play()
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Omareel.Ui

ColumnLayout {
    spacing: theme.space.panelGap
    OmEmptyState {
        visible: !editor.hasAudio
        iconSource: "qrc:/omareel/assets/icons/lucide/volume-x.svg"
        title: "No audio in this recording"
        hint: "Turn on System audio or Microphone in the launcher to record sound."
    }
    EditorSwitch { visible: editor.hasDesktopAudio; text: "System audio"; description: "Sound from apps on your desktop"; checked: editor.hasDesktopAudio && editor.project.audio.desktop; onToggled: editor.setProjectValue("audio.desktop", checked) }
    EditorSwitch { visible: editor.hasMicrophoneAudio; text: "Microphone"; description: "Your voice"; checked: editor.hasMicrophoneAudio && editor.project.audio.mic; onToggled: editor.setProjectValue("audio.mic", checked) }
    PanelSlider { visible: editor.hasAudio; Layout.fillWidth: true; label: "Volume"; path: "audio.volume"; from: 0; to: 2; value: editor.project.audio.volume; stepSize: 0.01; displayScale: 100; suffix: "%" }
}

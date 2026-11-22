import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts

ApplicationWindow {
    id: win
    width: 960
    height: 680
    minimumWidth: 660
    minimumHeight: 560
    visible: true
    title: "Flowtunes"
    color: theme.background

    Material.theme: theme.light ? Material.Light : Material.Dark
    Material.accent: theme.accent
    Material.background: theme.background
    Material.foreground: theme.foreground

    readonly property bool rightToLeft: Qt.application.layoutDirection === Qt.RightToLeft
    readonly property var flow: backend.flow
    readonly property var models: backend.models
    readonly property color muted: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.68)
    readonly property color line: theme.colors.selection

    // The genres by what they're called. Flow knows what each sounds like.
    readonly property var genreNames: ({
        "lofi": qsTr("Lo-fi"),
        "ambient": qsTr("Ambient"),
        "synthwave": qsTr("Synthwave"),
        "deephouse": qsTr("Deep House"),
        "techno": qsTr("Techno"),
        "dnb": qsTr("Drum & Bass"),
        "jazz": qsTr("Jazz"),
        "classical": qsTr("Classical"),
        "downtempo": qsTr("Downtempo"),
        "postrock": qsTr("Post-Rock"),
        "acoustic": qsTr("Acoustic"),
        "cinematic": qsTr("Cinematic")
    })

    // A music model is there to play with: running, starting, or set up and
    // started with the first genre picked.
    readonly property bool usable: ["ready", "starting", "installed", "blocked"].includes(models.state)
    // The model can't start while text models hold the memory it needs.
    readonly property bool blocked: waiting && models.state === "blocked" && !models.working
    // What stands in the way of the next tune.
    readonly property string problem: flow.error !== "" ? flow.error : waiting ? models.error : ""
    function again() {
        if (blocked)
            models.makeRoom()
        else
            flow.retry()
    }
    // The genres are on show: nothing plays yet, or another genre is being picked.
    property bool picking: true
    readonly property bool choosing: picking || flow.genre === ""
    // The genre the keyboard is on.
    property int chosen: Math.max(0, flow.genres.indexOf(flow.lastGenre))
    property bool paused: false
    readonly property TunePlayer player: playerLoader.item as TunePlayer
    // No tune to play yet: the first one, or the next after a skip, is on its way.
    readonly property bool waiting: flow.genre !== "" && flow.track.toString() === "" && flow.error === ""

    function pick(index) {
        chosen = index
        paused = false
        picking = false
        flow.play(flow.genres[index])
    }
    function move(by) {
        chosen = (chosen + by + flow.genres.length) % flow.genres.length
    }
    // Written as the language writes numbers, which is why it's handed over.
    function gigabytes(bytes, language) {
        return (bytes / 1e9).toLocaleString(Qt.locale(language), "f", 1)
    }
    function clock(ms) {
        const seconds = Math.floor(ms / 1000)
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
    }
    // The genre `flowtunes <genre>` asked for, played once there's a model to
    // play it with, which may be after it has been set up.
    property string wanted: backend.initialGenre
    function begin() {
        if (!usable || !flow.genres.includes(wanted))
            return
        const index = flow.genres.indexOf(wanted)
        wanted = ""
        pick(index)
    }
    Component.onCompleted: begin()
    onUsableChanged: begin()

    // The media keys, playerctl and the bar play along over MPRIS. Play does
    // as Space does: with nothing playing it plays the genre the keyboard is
    // on, and after trouble it tries again.
    Binding { target: backend.mpris; property: "paused"; value: win.paused }
    Binding { target: backend.mpris; property: "position"; value: win.player ? win.player.position : 0 }
    Binding { target: backend.mpris; property: "duration"; value: win.player ? win.player.duration : 0 }
    Connections {
        target: backend.mpris
        function onPauseAsked(paused) {
            if (!paused && win.flow.genre !== "" && (win.blocked || win.flow.error !== ""))
                win.again()
            else if (win.flow.genre !== "")
                win.paused = paused
            else if (!paused && win.usable)
                win.pick(win.chosen)
        }
        function onSeekAsked(position) {
            if (win.player && win.player.duration > 0)
                win.player.seek(position / win.player.duration)
        }
        function onRaiseAsked() {
            win.raise()
            win.requestActivate()
        }
        function onQuitAsked() { win.close() }
    }

    // The model is told to drop a tune it's still making before the app goes.
    onClosing: flow.stop()

    Shortcut { sequence: "?"; onActivated: help.opened ? help.close() : help.open() }
    Shortcut { sequence: "Q"; onActivated: win.close() }
    Shortcut {
        sequence: "Space"
        enabled: win.usable
        onActivated: {
            if (win.choosing)
                win.pick(win.chosen)
            else if (win.blocked || win.flow.error !== "")
                win.again()
            else
                win.paused = !win.paused
        }
    }
    Shortcut { sequences: ["Return", "Enter"]; enabled: win.usable && win.choosing; onActivated: win.pick(win.chosen) }
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: win.models.state === "installable" && !win.models.working
        onActivated: win.models.install()
    }
    Shortcut { sequence: "Left"; enabled: win.choosing; onActivated: win.move(win.rightToLeft ? 1 : -1) }
    Shortcut { sequence: "Right"; enabled: win.choosing; onActivated: win.move(win.rightToLeft ? -1 : 1) }
    Shortcut { sequence: "Up"; enabled: win.choosing; onActivated: win.move(-tiles.columns) }
    Shortcut { sequence: "Down"; enabled: win.choosing; onActivated: win.move(tiles.columns) }
    Shortcut { sequence: "N"; enabled: !win.choosing; onActivated: win.flow.next() }
    Shortcut { sequence: "G"; enabled: !win.choosing; onActivated: win.picking = true }
    Shortcut { sequence: "L"; enabled: !win.choosing; onActivated: win.flow.lyrics = !win.flow.lyrics }
    // The lyrics are sung in the language the desktop speaks.
    Binding { target: win.flow; property: "language"; value: translator.language }
    Shortcut {
        sequence: "Escape"
        enabled: win.flow.genre !== "" && !help.opened
        onActivated: win.picking = !win.picking
    }

    // Qt Multimedia takes a moment to start, so the player arrives with the
    // first tune and stays.
    Loader {
        id: playerLoader
        active: false
        sourceComponent: TunePlayer {
            source: win.flow.track
            paused: win.paused
            onEnded: win.flow.next()
            onSought: position => backend.mpris.moved(position)
            onFailed: why => win.flow.playbackFailed(why)
        }
    }
    Connections {
        target: win.flow
        function onChanged() {
            if (win.flow.track.toString() !== "")
                playerLoader.active = true
        }
    }

    component FlowButton: Button {
        id: flowButton
        flat: !highlighted
        focusPolicy: Qt.NoFocus
        // Material.roundedScale isn't inherited, and takes a binding, not a
        // literal number.
        Material.roundedScale: theme.radius
        // A highlighted button colors its caption by Material's own rule, not
        // Material.foreground, so it can't read on every accent.
        contentItem: Label {
            text: flowButton.text
            font: flowButton.font
            color: flowButton.highlighted ? theme.accentForeground : theme.foreground
            opacity: flowButton.enabled ? 1 : 0.4
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // A control drawn as its icon alone, named by its tooltip with its key.
    // The main one sits on a disc of the accent.
    component IconButton: ToolButton {
        id: iconButton
        property string glyph
        property string key
        property bool main: false
        readonly property color ink: main ? theme.accentForeground : hovered ? theme.accent : theme.foreground
        implicitWidth: main ? 56 : 44
        implicitHeight: implicitWidth
        padding: 0
        focusPolicy: Qt.NoFocus
        display: AbstractButton.IconOnly
        icon.source: "qrc:/icons/" + glyph + ".svg"
        icon.width: main ? 26 : 22
        icon.height: main ? 26 : 22
        icon.color: ink
        opacity: enabled ? 1 : 0.35
        background: Rectangle {
            radius: width / 2
            color: iconButton.main ? theme.accent : "transparent"
            opacity: iconButton.main && iconButton.hovered ? 0.88 : 1
        }
        Accessible.name: text
        ToolTip.visible: hovered
        ToolTip.text: text + "  " + key
        ToolTip.delay: 300
    }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        anchors.fill: parent
        LayoutMirroring.enabled: win.rightToLeft
        LayoutMirroring.childrenInherit: true

        // An aurora plays over the whole window, under everything else: at
        // full strength while the music plays, softer the rest of the time.
        Aurora {
            objectName: "aurora"
            anchors.fill: parent
            colorA: theme.colors.cyan || theme.accent
            colorB: theme.accent
            colorC: theme.colors.magenta || theme.accent
            intensity: !win.usable || win.choosing ? 0.5 : win.paused ? 0.3 : 1
            // Still while the music is: it redraws the whole window on the
            // GPU the model makes the music with.
            moving: !win.paused || win.choosing
            Behavior on intensity { NumberAnimation { duration: 600; easing.type: Easing.InOutSine } }
        }

        // No music model to play with: what's missing, and the way to get it.
        ColumnLayout {
            objectName: "setup"
            visible: !win.usable
            anchors.centerIn: parent
            width: Math.min(parent.width - 80, 520)
            spacing: 16

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 26
                font.weight: Font.DemiBold
                text: win.models.state === "noEngine" ? qsTr("Flowtunes needs Omarchy's local models")
                    : win.models.state === "installable" ? qsTr("Flowtunes plays with %1").arg(win.models.name)
                    : win.models.state === "installing" ? qsTr("Setting up %1…").arg(win.models.name)
                    : qsTr("No music model fits this machine yet")
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 15
                color: win.muted
                text: win.models.state === "noEngine" ? qsTr("Flowtunes makes its music with Omarchy's local AI models, which aren't installed.")
                    : win.models.state === "installable" ? qsTr("The model makes every tune on this machine. It's a download of a few gigabytes, once.")
                    : win.models.state === "installing" ? qsTr("The music starts as soon as the model is here.")
                    : qsTr("None of Omarchy's music models runs on this hardware. New ones arrive with updates.")
            }
            ProgressBar {
                Layout.fillWidth: true
                visible: win.models.state === "installing"
                indeterminate: win.models.totalBytes <= 0
                value: win.models.totalBytes > 0 ? win.models.doneBytes / win.models.totalBytes : 0
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 12
                color: win.muted
                visible: win.models.state === "installing" && win.models.totalBytes > 0
                text: qsTr("%1 of %2 GB").arg(win.gigabytes(win.models.doneBytes, translator.language))
                                         .arg(win.gigabytes(win.models.totalBytes, translator.language))
            }
            FlowButton {
                objectName: "setUp"
                Layout.alignment: Qt.AlignHCenter
                visible: win.models.state === "installable"
                enabled: !win.models.working
                highlighted: true
                text: qsTr("Set it up")
                onClicked: win.models.install()
            }
            // The engine's own words, for what went wrong or why nothing fits.
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: win.models.error !== "" ? theme.colors.red : win.muted
                visible: text !== ""
                text: win.models.error !== "" ? win.models.error : win.models.reason
            }
        }

        // The genres to pick from.
        ColumnLayout {
            objectName: "picker"
            visible: win.usable && win.choosing
            anchors.centerIn: parent
            spacing: 10

            Label {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: 30
                font.weight: Font.DemiBold
                text: qsTr("What do you want to flow to?")
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 22
                font.pixelSize: 15
                color: win.muted
                text: qsTr("Pick a genre, and the music never stops.")
            }
            GridLayout {
                id: tiles
                Layout.alignment: Qt.AlignHCenter
                columns: win.width < 900 ? 3 : 4
                columnSpacing: 12
                rowSpacing: 12

                Repeater {
                    model: win.flow.genres
                    delegate: Rectangle {
                        id: tile
                        required property int index
                        required property string modelData
                        readonly property bool current: win.chosen === index
                        readonly property bool flowing: win.flow.genre === modelData
                        objectName: "genre-" + modelData
                        Layout.preferredWidth: 196
                        Layout.preferredHeight: 84
                        radius: theme.radius
                        // Dark enough to read on, clear enough for the aurora to show through.
                        color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, current ? 0.9 : 0.66)
                        border.width: current ? 2 : 1
                        border.color: current ? theme.accent : win.line

                        Label {
                            anchors.centerIn: parent
                            width: parent.width - 24
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font.pixelSize: 18
                            font.weight: tile.current ? Font.DemiBold : Font.Normal
                            color: tile.current || tile.flowing ? theme.accent : theme.foreground
                            text: win.genreNames[tile.modelData] || tile.modelData
                        }
                        // The genre that's playing, while another is picked.
                        Rectangle {
                            visible: tile.flowing
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 14
                            width: 6
                            height: 6
                            radius: 3
                            color: theme.accent
                        }
                        HoverHandler { onHoveredChanged: if (hovered) win.chosen = tile.index }
                        TapHandler { onTapped: win.pick(tile.index) }
                    }
                }
            }
        }

        // The flow: the genre, the tune playing in its own shape, and the few
        // things to do with it.
        ColumnLayout {
            objectName: "playing"
            visible: win.usable && !win.choosing
            anchors.fill: parent
            anchors.margins: 48
            spacing: 6

            Label {
                objectName: "genre"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.pixelSize: 44
                font.weight: Font.Bold
                text: win.genreNames[win.flow.genre] || ""
            }
            // Sung, or only played: what the tunes made from here on are.
            Item {
                id: lyricsSwitch
                objectName: "lyrics"
                readonly property bool checked: win.flow.lyrics
                readonly property color ink: checked ? theme.accent : win.muted
                Layout.alignment: Qt.AlignHCenter
                // Tucked up under the name, inside the room its tall letters leave.
                Layout.topMargin: -12
                Layout.bottomMargin: 8
                implicitWidth: lyricsRow.implicitWidth + 16
                implicitHeight: 24
                opacity: lyricsHover.hovered || checked ? 1 : 0.75

                Row {
                    id: lyricsRow
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 12
                        radius: 6
                        color: "transparent"
                        border.width: 1
                        border.color: lyricsSwitch.ink
                        Rectangle {
                            x: lyricsSwitch.checked !== win.rightToLeft ? parent.width - width - 3 : 3
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: lyricsSwitch.ink
                            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: 13
                        color: lyricsSwitch.ink
                        text: qsTr("Lyrics")
                    }
                }
                HoverHandler { id: lyricsHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: win.flow.lyrics = !win.flow.lyrics }
                Accessible.role: Accessible.CheckBox
                Accessible.name: qsTr("Lyrics")
                Accessible.checked: checked
                ToolTip.visible: lyricsHover.hovered
                ToolTip.text: qsTr("Lyrics") + "  L"
                ToolTip.delay: 300
            }
            Label {
                objectName: "detail"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                // A name from a file is shown as it's written, and as much of it as fits.
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                font.pixelSize: 15
                color: win.muted
                // What's known of the tune: its name, its tempo and its key.
                text: {
                    if (win.flow.track.toString() === "")
                        return " "
                    const parts = [win.flow.title]
                    if (win.flow.bpm > 0)
                        parts.push(qsTr("%L1 BPM").arg(win.flow.bpm))
                    if (win.flow.key !== "")
                        parts.push(win.flow.key)
                    return parts.join("  ·  ")
                }
            }

            Wave {
                id: wave
                objectName: "wave"
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.maximumHeight: 300
                Layout.alignment: Qt.AlignVCenter
                Layout.topMargin: 12
                Layout.bottomMargin: 12
                wave: win.flow.wave
                forming: win.waiting && !win.choosing
                progress: win.player && win.player.duration > 0 ? win.player.position / win.player.duration : 0
                played: theme.accent
                unplayed: Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, 0.4)
                onSeek: fraction => { if (win.player) win.player.seek(fraction) }
            }

            Label {
                objectName: "status"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 15
                color: win.problem !== "" ? theme.colors.red : win.muted
                text: win.problem !== "" ? win.problem
                    : win.blocked ? qsTr("%1 needs the memory %2 is using").arg(win.models.name).arg(win.models.blockers.join(", "))
                    : !win.waiting ? win.clock(win.player ? win.player.position : 0) + " / " + win.clock(win.player ? win.player.duration : 0)
                    : win.models.working || win.models.state === "starting" ? qsTr("Starting %1…").arg(win.models.name)
                    : !win.flow.composing ? " "
                    : win.flow.number === 0 ? qsTr("Composing your first tune…")
                    : qsTr("Composing the next tune…")
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 14
                spacing: 20
                // Play, then next: a tune runs left to right in every language.
                LayoutMirroring.enabled: false

                IconButton {
                    objectName: "genres"
                    glyph: "genres"
                    key: "G"
                    text: qsTr("Genres")
                    onClicked: win.picking = true
                }
                IconButton {
                    objectName: "playPause"
                    main: true
                    glyph: win.paused ? "play" : "pause"
                    key: "Space"
                    visible: win.flow.error === "" && !win.blocked
                    enabled: !win.waiting
                    text: win.paused ? qsTr("Play") : qsTr("Pause")
                    onClicked: win.paused = !win.paused
                }
                FlowButton {
                    objectName: "retry"
                    highlighted: true
                    visible: win.flow.error !== "" || win.blocked
                    text: win.blocked ? qsTr("Stop %1 and start %2").arg(win.models.blockers.join(", ")).arg(win.models.name) : qsTr("Try again")
                    onClicked: win.again()
                }
                IconButton {
                    objectName: "next"
                    glyph: "next"
                    key: "N"
                    enabled: !win.waiting && win.flow.error === ""
                    text: qsTr("Next")
                    onClicked: win.flow.next()
                }
            }
        }
    }

    Popup {
        id: help
        objectName: "help"
        anchors.centerIn: Overlay.overlay
        modal: true
        focus: true
        padding: 24
        background: Rectangle {
            color: theme.background
            border.color: theme.colors.selection
            radius: theme.radius
        }

        ColumnLayout {
            spacing: 8
            // A popup is not an Item and doesn't inherit the window's
            // mirroring, so its content opts in.
            LayoutMirroring.enabled: win.rightToLeft
            LayoutMirroring.childrenInherit: true

            Repeater {
                model: [
                    { keys: "← ↑ ↓ →", action: qsTr("Move between the genres") },
                    { keys: "Enter", action: qsTr("Play the genre") },
                    { keys: "Space", action: qsTr("Pause or play") },
                    { keys: "N", action: qsTr("Skip to the next tune") },
                    { keys: "G", action: qsTr("Pick another genre") },
                    { keys: "L", action: qsTr("Turn the lyrics on or off") },
                    { keys: "?", action: qsTr("Show or hide the shortcuts") },
                    { keys: "Q", action: qsTr("Quit") }
                ]
                delegate: RowLayout {
                    required property var modelData
                    spacing: 24

                    Label {
                        Layout.preferredWidth: 80
                        text: modelData.keys
                        color: theme.accent
                        font.bold: true
                    }
                    Label { text: modelData.action }
                }
            }
        }
    }
}

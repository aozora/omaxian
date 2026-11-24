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
    // Stops what's in a blocked model's way; with nothing to stop that would
    // be enough, looks again at what's free, and it starts once it fits.
    function again() {
        if (blocked && models.blockers.length > 0)
            models.makeRoom()
        else if (blocked)
            models.checkMemory()
        else
            flow.retry()
    }
    // Memory changes hands with nothing to say so: looked at again whenever
    // the window is.
    onActiveChanged: if (active) models.checkMemory()
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
        models.checkMemory()
        flow.play(flow.genres[index])
    }
    function move(by) {
        chosen = (chosen + by + flow.genres.length) % flow.genres.length
    }
    // Written as the language writes numbers, which is why it's handed over.
    function gigabytes(bytes, language) {
        return (bytes / 1e9).toLocaleString(Qt.locale(language), "f", 1)
    }
    // Memory and disk as the engine counts them: whole, but to a tenth under ten.
    function gb(gib, language) {
        const tenths = Math.round(gib * 10)
        return gib.toLocaleString(Qt.locale(language), "f", tenths < 100 && tenths % 10 !== 0 ? 1 : 0)
    }
    // The other models running here, each with what it holds.
    function holding(language) {
        return models.holders.map(held => qsTr("%1 (%2 GB)").arg(held.name).arg(gb(held.gib, language))).join(", ")
    }
    // What's left of a model's start, from how long the last one took: steady
    // to 90% in that time, then creeping on, so a slow one reads as slow, not stuck.
    function loaded(now) {
        const expected = models.loadSeconds * 1000
        const elapsed = now - models.sinceMs
        if (!(expected > 0) || models.sinceMs <= 0)
            return 0
        if (elapsed <= expected)
            return 0.9 * Math.max(0, elapsed) / expected
        return 0.9 + 0.08 * (1 - Math.exp(-(elapsed - expected) / expected))
    }
    // The clock a start's progress is drawn by, ticking only while one is shown.
    property real now: Date.now()
    Timer {
        interval: 100
        repeat: true
        running: win.models.state === "starting" && win.models.loadSeconds > 0
        onTriggered: win.now = Date.now()
        onRunningChanged: win.now = Date.now()
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
    onUsableChanged: Qt.callLater(begin)

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
    Shortcut {
        sequence: "M"
        enabled: !["noEngine", "none"].includes(win.models.state) && !sheet.opened
        onActivated: sheet.open()
    }
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
    Shortcut { sequence: "L"; enabled: !win.choosing && win.models.vocals; onActivated: win.flow.lyrics = !win.flow.lyrics }
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
            readonly property bool choosingModel: win.models.state === "installable" && win.models.offers.length > 1
            readonly property string vendorLogo: win.models.logo(win.models.vendor, theme.light)
            anchors.centerIn: parent
            width: choosingModel ? Math.min(parent.width - 64, 680) : Math.min(parent.width - 80, 520)
            spacing: 16

            Image {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectFit
                visible: !parent.choosingModel && parent.vendorLogo !== ""
                         && ["installable", "installing", "removing"].includes(win.models.state)
                source: parent.vendorLogo
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 26
                font.weight: Font.DemiBold
                text: win.models.state === "noEngine" ? qsTr("Flowtunes needs Omarchy's local models")
                    : parent.choosingModel ? qsTr("Choose a music model")
                    : win.models.state === "installable" ? qsTr("Flowtunes plays with %1").arg(win.models.name)
                    : win.models.state === "installing" ? qsTr("Setting up %1…").arg(win.models.name)
                    : win.models.state === "removing" ? qsTr("Removing %1…").arg(win.models.name)
                    : qsTr("No music model fits this machine yet")
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 15
                color: win.muted
                text: win.models.state === "noEngine" ? qsTr("Flowtunes makes its music with Omarchy's local AI models, which aren't installed.")
                    : parent.choosingModel ? qsTr("Each runs right here on this machine. You can switch later.")
                    : win.models.state === "installable" && win.models.diskGib > 0 && win.models.needGib > 0
                        ? qsTr("The model makes every tune on this machine. It's a %1 GB download, once, and it needs %2 GB of memory while it plays.")
                            .arg(win.gb(win.models.diskGib, translator.language)).arg(win.gb(win.models.needGib, translator.language))
                    : win.models.state === "installable" ? qsTr("The model makes every tune on this machine. It's a download of a few gigabytes, once.")
                    : win.models.state === "installing" ? qsTr("The music starts as soon as the model is here.")
                    : win.models.state === "removing" ? qsTr("Your tunes stay in your music folder.")
                    : qsTr("None of Omarchy's music models runs on this hardware. New ones arrive with updates.")
            }
            GridLayout {
                id: offerCards
                visible: parent.choosingModel
                Layout.fillWidth: true
                Layout.topMargin: 8
                columns: win.width < 700 ? 1 : Math.min(win.models.offers.length, 2)
                columnSpacing: 16
                rowSpacing: 14

                Repeater {
                    model: win.models.offers
                    delegate: Rectangle {
                        id: offerCard
                        required property var modelData
                        readonly property string logo: win.models.logo(modelData.vendor || "", theme.light)
                        objectName: "offer-" + modelData.id
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        implicitHeight: offerContent.implicitHeight + 36
                        radius: theme.radius
                        color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.82)
                        border.width: 1
                        border.color: modelData.best ? theme.accent : win.line

                        ColumnLayout {
                            id: offerContent
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                Image {
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                    sourceSize: Qt.size(44, 44)
                                    fillMode: Image.PreserveAspectFit
                                    visible: offerCard.logo !== ""
                                    source: offerCard.logo
                                }
                                Label {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignLeft
                                    elide: Text.ElideRight
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
                                    text: offerCard.modelData.name
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                font.pixelSize: 13
                                color: win.muted
                                text: offerCard.modelData.vocals ? qsTr("Songs with vocals or instrumental") : qsTr("Instrumental music")
                            }
                            Item { Layout.fillHeight: true; Layout.minimumHeight: 8 }
                            Label {
                                Layout.fillWidth: true
                                font.pixelSize: 12
                                color: win.muted
                                visible: text !== ""
                                text: {
                                    const parts = []
                                    if (offerCard.modelData.downloadGib > 0)
                                        parts.push(qsTr("%1 GB download").arg(win.gb(offerCard.modelData.downloadGib, translator.language)))
                                    if (offerCard.modelData.memoryGib > 0)
                                        parts.push(qsTr("%1 GB memory").arg(win.gb(offerCard.modelData.memoryGib, translator.language)))
                                    return parts.join("  ·  ")
                                }
                            }
                            FlowButton {
                                objectName: "setUp-" + offerCard.modelData.id
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                enabled: !win.models.working
                                highlighted: offerCard.modelData.best || win.models.id === offerCard.modelData.id
                                text: qsTr("Set it up")
                                onClicked: win.models.install(offerCard.modelData.id)
                            }
                        }
                    }
                }
            }
            ProgressBar {
                Layout.fillWidth: true
                visible: win.models.state === "installing" || win.models.state === "removing"
                         || (win.models.state === "installable" && win.models.working)
                indeterminate: win.models.totalBytes <= 0 || win.models.phase !== "downloading"
                value: win.models.totalBytes > 0 ? win.models.doneBytes / win.models.totalBytes : 0
            }
            Label {
                objectName: "setupProgress"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 12
                color: win.muted
                visible: text !== ""
                text: win.models.state === "installable" && win.models.working ? qsTr("Getting ready…")
                    : win.models.state !== "installing" ? ""
                    : win.models.phase === "waiting" ? qsTr("Waiting for another model to finish setting up…")
                    : win.models.totalBytes <= 0 ? ""
                    : win.models.rateBytes > 0 ? qsTr("%1 of %2 GB").arg(win.gigabytes(win.models.doneBytes, translator.language))
                                                     .arg(win.gigabytes(win.models.totalBytes, translator.language))
                                               + "  ·  " + qsTr("%1 MB/s").arg(Math.round(win.models.rateBytes / 1e6).toLocaleString(Qt.locale(translator.language), "f", 0))
                    : qsTr("%1 of %2 GB").arg(win.gigabytes(win.models.doneBytes, translator.language))
                                         .arg(win.gigabytes(win.models.totalBytes, translator.language))
            }
            FlowButton {
                objectName: "setUp"
                Layout.alignment: Qt.AlignHCenter
                visible: win.models.state === "installable" && !parent.choosingModel
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
                visible: win.models.vocals
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
                    : win.blocked && win.models.needGib > 0 && win.models.freeGib >= 0
                        ? qsTr("%1 needs %2 GB of memory to play, and %3 GB is free.").arg(win.models.name)
                            .arg(win.gb(win.models.needGib, translator.language)).arg(win.gb(win.models.freeGib, translator.language))
                    : win.blocked ? qsTr("%1 needs the memory %2 is using").arg(win.models.name).arg(win.models.blockers.join(", "))
                    : !win.waiting ? win.clock(win.player ? win.player.position : 0) + " / " + win.clock(win.player ? win.player.duration : 0)
                    : win.models.state === "starting" ? qsTr("Loading %1…").arg(win.models.name)
                    : win.models.working ? qsTr("Starting %1…").arg(win.models.name)
                    : !win.flow.composing ? " "
                    : win.flow.number === 0 ? qsTr("Composing your first tune…")
                    : qsTr("Composing the next tune…")
            }
            // What's holding the memory a blocked model needs, and what to do about it.
            Label {
                objectName: "holders"
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                color: win.muted
                visible: win.blocked && text !== ""
                text: {
                    const lines = []
                    if (win.models.holders.length > 0)
                        lines.push(qsTr("Running now: %1").arg(win.holding(translator.language)))
                    if (win.models.blockers.length === 0 && win.models.needGib > win.models.freeGib && win.models.freeGib >= 0)
                        lines.push(qsTr("Close some apps to free %1 GB more, then try again.")
                                   .arg(win.gb(win.models.needGib - win.models.freeGib, translator.language)))
                    return lines.join("\n")
                }
            }
            // How far the model's start is.
            ProgressBar {
                objectName: "loading"
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 240
                visible: win.waiting && win.models.state === "starting" && win.models.loadSeconds > 0
                value: win.loaded(win.now)
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
                    text: !win.blocked || win.models.blockers.length === 0 ? qsTr("Try again")
                        : qsTr("Stop %1 and play").arg(win.models.blockers.join(", "))
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

        // The music model, and what it's doing: opens its sheet.
        Row {
            id: modelChip
            objectName: "modelChip"
            readonly property string logo: win.models.logo(win.models.vendor, theme.light)
            readonly property alias text: modelChipLabel.text
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            visible: win.usable
            spacing: 6

            Image {
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                sourceSize: Qt.size(28, 28)
                fillMode: Image.PreserveAspectFit
                visible: modelChip.logo !== ""
                source: modelChip.logo
            }
            Label {
                id: modelChipLabel
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 12
                color: chipHover.hovered ? theme.foreground : win.muted
                text: {
                    const parts = [win.models.name]
                    const state = win.models.state
                    if (state === "ready" && win.models.heldGib > 0)
                        parts.push(qsTr("using %1 GB").arg(win.gb(win.models.heldGib, translator.language)))
                    else if (state === "starting")
                        parts.push(qsTr("loading…"))
                    else if (state === "installed" || state === "blocked")
                        parts.push(qsTr("stopped"))
                    if (win.models.updatable)
                        parts.push(qsTr("update ready"))
                    return parts.join("  ·  ")
                }
            }
            HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: sheet.open() }
            ToolTip.visible: chipHover.hovered
            ToolTip.text: qsTr("Show the music model") + "  M"
            ToolTip.delay: 300
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
                    { keys: "← ↑ ↓ →", action: qsTr("Move between the genres"), shown: true },
                    { keys: "Enter", action: qsTr("Play the genre"), shown: true },
                    { keys: "Space", action: qsTr("Pause or play"), shown: true },
                    { keys: "N", action: qsTr("Skip to the next tune"), shown: true },
                    { keys: "G", action: qsTr("Pick another genre"), shown: true },
                    { keys: "L", action: qsTr("Turn the lyrics on or off"), shown: win.models.vocals },
                    { keys: "M", action: qsTr("Show the music model"), shown: true },
                    { keys: "?", action: qsTr("Show or hide the shortcuts"), shown: true },
                    { keys: "Q", action: qsTr("Quit"), shown: true }
                ].filter(row => row.shown)
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

    // The music model: what it is and does, and what to do with it.
    Popup {
        id: sheet
        objectName: "sheet"
        anchors.centerIn: Overlay.overlay
        width: Math.min(win.width - 64, 480)
        modal: true
        focus: true
        padding: 28
        // Removing asks first, and asks again each time, and for whichever
        // model the sheet shows by then.
        property bool removing: false
        readonly property string model: win.models.id
        onModelChanged: removing = false
        readonly property bool local: win.models.host === ""
        readonly property bool running: ["ready", "starting"].includes(win.models.state)
        readonly property bool setUp: ["ready", "starting", "installed", "blocked"].includes(win.models.state)
        onAboutToShow: {
            removing = false
            win.models.checkMemory()
        }
        background: Rectangle {
            color: theme.background
            border.color: theme.colors.selection
            radius: theme.radius
        }

        function stop() {
            win.flow.stop()
            win.models.stop()
        }
        function remove() {
            if (!removing) {
                removing = true
                return
            }
            removing = false
            win.flow.stop()
            win.models.remove()
        }
        function use(id) {
            win.flow.stop()
            win.models.use(id)
        }

        // An open modal popup keeps the window's shortcuts from firing, so
        // the sheet has its own.
        Shortcut { sequence: "M"; enabled: sheet.opened; onActivated: sheet.close() }
        Shortcut { sequence: "S"; enabled: sheet.opened && sheet.local && sheet.running && !win.models.working; onActivated: sheet.stop() }
        Shortcut { sequence: "U"; enabled: sheet.opened && win.models.updatable && !win.models.updating && !win.models.working; onActivated: win.models.update() }
        Shortcut { sequence: "Delete"; enabled: sheet.opened && sheet.local && sheet.setUp && !win.models.working; onActivated: sheet.remove() }
        Shortcut { sequences: ["Return", "Enter"]; enabled: sheet.opened && sheet.removing; onActivated: sheet.remove() }

        ColumnLayout {
            width: parent.width
            spacing: 10
            LayoutMirroring.enabled: win.rightToLeft
            LayoutMirroring.childrenInherit: true

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                readonly property string logo: win.models.logo(win.models.vendor, theme.light)

                Image {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    sourceSize: Qt.size(48, 48)
                    fillMode: Image.PreserveAspectFit
                    visible: parent.logo !== ""
                    source: parent.logo
                }
                Label {
                    Layout.fillWidth: true
                    // A Latin name keeps to the reading side in a right-to-left language too.
                    horizontalAlignment: Text.AlignLeft
                    wrapMode: Text.WordWrap
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    text: win.models.name
                }
            }
            Label {
                objectName: "sheetState"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: win.muted
                text: {
                    const language = translator.language
                    switch (win.models.state) {
                    case "ready":
                        return !sheet.local ? qsTr("Running on %1, shared over your tailnet.").arg(win.models.host)
                            : win.models.heldGib > 0 ? qsTr("Running, using %1 GB of memory.").arg(win.gb(win.models.heldGib, language))
                            : qsTr("Running.")
                    case "starting":
                        return qsTr("Loading…")
                    case "installed":
                    case "blocked":
                        return win.models.needGib > 0 ? qsTr("Stopped. It starts when you play, and needs %1 GB of memory.").arg(win.gb(win.models.needGib, language))
                            : qsTr("Stopped. It starts when you play.")
                    case "installing":
                        return qsTr("Setting up…")
                    case "removing":
                        return qsTr("Removing…")
                    case "installable":
                        return win.models.diskGib > 0 ? qsTr("Not set up yet. It's a %1 GB download.").arg(win.gb(win.models.diskGib, language))
                            : qsTr("Not set up yet.")
                    }
                    return ""
                }
            }
            // The machine's memory, and who else holds some of it.
            Label {
                objectName: "sheetMemory"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: win.muted
                visible: text !== ""
                text: {
                    const language = translator.language
                    const lines = []
                    if (win.models.totalGib > 0 && win.models.freeGib >= 0)
                        lines.push(qsTr("This machine has %1 GB of memory, and %2 GB is free.")
                                   .arg(win.gb(win.models.totalGib, language)).arg(win.gb(win.models.freeGib, language)))
                    if (win.models.holders.length > 0)
                        lines.push(qsTr("Running now: %1").arg(win.holding(language)))
                    return lines.join("\n")
                }
            }
            ProgressBar {
                Layout.fillWidth: true
                visible: win.models.updating || win.models.state === "installing"
                indeterminate: win.models.totalBytes <= 0 || win.models.phase !== "downloading"
                value: win.models.totalBytes > 0 ? win.models.doneBytes / win.models.totalBytes : 0
            }
            Label {
                objectName: "sheetUpdate"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: win.models.updatable && sheet.local
                color: theme.accent
                text: win.models.updating ? qsTr("Updating…")
                    : win.models.updateBytes > 0 ? qsTr("An update is ready, a %1 GB download. The model restarts with it.").arg(win.gigabytes(win.models.updateBytes, translator.language))
                    : qsTr("An update is ready. The model restarts with it.")
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: text !== ""
                color: theme.colors.red
                text: win.models.error
            }
            Label {
                objectName: "sheetRemoving"
                Layout.fillWidth: true
                Layout.topMargin: 6
                wrapMode: Text.WordWrap
                visible: sheet.removing
                text: win.models.diskGib > 0
                    ? qsTr("Remove %1? That frees about %2 GB of disk. Your tunes stay in your music folder.").arg(win.models.name).arg(win.gb(win.models.diskGib, translator.language))
                    : qsTr("Remove %1? Your tunes stay in your music folder.").arg(win.models.name)
            }
            RowLayout {
                Layout.topMargin: 6
                spacing: 8
                visible: sheet.local
                FlowButton {
                    objectName: "sheetUpdateButton"
                    visible: win.models.updatable && !win.models.updating && !sheet.removing
                    enabled: !win.models.working
                    highlighted: true
                    text: qsTr("Update")
                    ToolTip.visible: hovered
                    ToolTip.text: "U"
                    onClicked: win.models.update()
                }
                FlowButton {
                    objectName: "sheetStop"
                    visible: sheet.running && !sheet.removing
                    enabled: !win.models.working
                    text: qsTr("Stop")
                    ToolTip.visible: hovered
                    ToolTip.text: "S"
                    onClicked: sheet.stop()
                }
                FlowButton {
                    objectName: "sheetSetUp"
                    visible: win.models.state === "installable"
                    enabled: !win.models.working
                    highlighted: true
                    text: qsTr("Set it up")
                    onClicked: win.models.install()
                }
                FlowButton {
                    objectName: "sheetRemove"
                    visible: sheet.setUp
                    enabled: !win.models.working
                    highlighted: sheet.removing
                    text: qsTr("Remove")
                    ToolTip.visible: hovered
                    ToolTip.text: "Delete"
                    onClicked: sheet.remove()
                }
                FlowButton {
                    visible: sheet.removing
                    text: qsTr("Keep it")
                    onClicked: sheet.removing = false
                }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: 12
                color: win.muted
                visible: sheet.local && sheet.running && !sheet.removing
                text: qsTr("Stopping it frees its memory, and it starts again when you play.")
            }

            // Another music model to play with, where there's one.
            Label {
                Layout.topMargin: 12
                visible: win.models.others.length > 0
                font.weight: Font.DemiBold
                text: qsTr("Other music models")
            }
            Repeater {
                model: win.models.others
                delegate: RowLayout {
                    required property var modelData
                    readonly property string logo: win.models.logo(modelData.vendor || "", theme.light)
                    Layout.fillWidth: true
                    spacing: 10
                    Image {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        sourceSize: Qt.size(36, 36)
                        fillMode: Image.PreserveAspectFit
                        visible: parent.logo !== ""
                        source: parent.logo
                    }
                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignLeft
                        elide: Text.ElideRight
                        text: modelData.name
                    }
                    Label {
                        color: win.muted
                        font.pixelSize: 12
                        text: {
                            const parts = []
                            if (!modelData.vocals)
                                parts.push(qsTr("Instrumental"))
                            if (modelData.installed)
                                parts.push(qsTr("Set up"))
                            else if (modelData.downloadGib > 0)
                                parts.push(qsTr("%1 GB download").arg(win.gb(modelData.downloadGib, translator.language)))
                            return parts.join("  ·  ")
                        }
                    }
                    FlowButton {
                        enabled: !win.models.working
                        text: qsTr("Use")
                        onClicked: sheet.use(modelData.id)
                    }
                }
            }
        }
    }
}

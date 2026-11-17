import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import QtQuick.Window
import QtMultimedia
import "Format.js" as Format

ApplicationWindow {
    id: win
    width: 960
    height: 540
    minimumWidth: 320
    minimumHeight: 200
    // Started with a picture, the window stays hidden until the picture is
    // ready, then opens once at its size, rather than drawing empty, then
    // the picture, then resizing.
    property bool holding: false
    // Started with files: the empty screen's play button never flashes
    // before the first one arrives.
    property bool opening: false
    visible: !holding
    // A picture slow to decode doesn't keep the window away for long.
    Timer { running: win.holding; interval: 1500; onTriggered: win.holding = false }
    title: backend.hasMedia ? backend.title : qsTr("Media Viewer")
    // The picture's surround is black whatever the theme, as every player's
    // is; ApplicationWindow would otherwise paint Material's background.
    color: "black"
    background: Rectangle { color: "black" }

    Material.theme: theme.light ? Material.Light : Material.Dark
    Material.accent: theme.accent
    Material.background: theme.background
    Material.foreground: theme.foreground

    readonly property bool rightToLeft: Qt.application.layoutDirection === Qt.RightToLeft
    readonly property bool fullscreen: visibility === Window.FullScreen
    // The controls show from the start; Tab hides them and brings them back,
    // and they stay as they were from one file to the next.
    property bool overlayShown: true
    property bool gridShown: false
    // The grid's tiles keep their size from one showing to the next.
    property real gridTileSize: 240
    property bool sized: false

    // The keys mean what fits what's shown: ← → step through pictures and
    // seek in a video. The ? overlay lists what's shown first.
    readonly property var pictureShortcuts: [
        { keys: "← →", action: qsTr("Previous or next file") },
        { keys: "Home  End", action: qsTr("First or last file") },
        { keys: "+  −", action: qsTr("Zoom in or out") },
        { keys: "0", action: qsTr("Fit to the window") },
        { keys: "1", action: qsTr("Actual size") },
        { keys: "← → ↑ ↓", action: qsTr("Move around, zoomed in") },
        { keys: "R  Shift+R", action: qsTr("Turn right or left") },
        { keys: "Space", action: qsTr("Pause or play an animation") },
        { keys: "Ctrl+P", action: qsTr("Print") },
        { keys: "E", action: qsTr("Edit in Omasnap") }
    ]
    readonly property var videoShortcuts: [
        { keys: "Space", action: qsTr("Play or pause") },
        { keys: "← →", action: qsTr("Back or forward 5 seconds") },
        { keys: "Shift+← →", action: qsTr("Back or forward 1 second") },
        { keys: "0 – 9", action: qsTr("Jump to that tenth of the way") },
        { keys: "Home", action: qsTr("Back to the start") },
        { keys: ",  .", action: qsTr("Step one frame back or forward") },
        { keys: "PgUp  PgDn", action: qsTr("Previous or next chapter") },
        { keys: "[  ]", action: qsTr("Slower or faster") },
        { keys: "Backspace", action: qsTr("Normal speed") },
        { keys: "↑ ↓", action: qsTr("Louder or quieter") },
        { keys: "M", action: qsTr("Mute") },
        { keys: "R", action: qsTr("Loop, or stop looping") },
        { keys: "C", action: qsTr("Next subtitles, or off") },
        { keys: "A", action: qsTr("Next audio track") },
        { keys: "Ctrl+S", action: qsTr("Save the frame") },
        { keys: "E", action: qsTr("Trim in Omacut") }
    ]
    readonly property var commonShortcuts: [
        { keys: "N  P", action: qsTr("Next or previous file") },
        { keys: "Ctrl+M", action: qsTr("Every file in the folder") },
        { keys: "Ctrl++  Ctrl+−", action: qsTr("Bigger or smaller tiles") },
        { keys: "Tab", action: qsTr("Show or hide the controls") },
        { keys: "F", action: qsTr("Fullscreen") },
        { keys: "I", action: qsTr("What's in the file") },
        { keys: "Ctrl+C", action: qsTr("Copy the picture or the frame") },
        { keys: "Delete", action: qsTr("Move to the Trash") },
        { keys: "Ctrl+Z", action: qsTr("Bring back from the Trash") },
        { keys: "Ctrl+O", action: qsTr("Open files") },
        { keys: "?", action: qsTr("Show or hide the shortcuts") },
        { keys: "Q", action: qsTr("Quit") }
    ]
    readonly property var shortcutList: {
        const section = (title, rows) => [{ keys: "", action: title, header: true }].concat(rows)
        const pictures = section(qsTr("Pictures"), pictureShortcuts)
        const videos = section(qsTr("Videos and music"), videoShortcuts)
        return (backend.isPicture ? pictures.concat(videos) : videos.concat(pictures))
            .concat(section(qsTr("Any file"), commonShortcuts))
    }

    function toggleFullscreen() {
        if (fullscreen)
            showNormal()
        else
            showFullScreen()
    }

    // The corner shows for a moment whenever something changes.
    function poke() {
        cornerTimer.restart()
        cornerOsd.shown = true
    }
    // Where a picture is in its folder, and how far it is zoomed.
    function pictureStatus() {
        const parts = []
        if (backend.playlistCount > 1)
            parts.push(qsTr("%1 of %2").arg((backend.playlistIndex + 1).toLocaleString(Qt.locale(), 'f', 0))
                                       .arg(backend.playlistCount.toLocaleString(Qt.locale(), 'f', 0)))
        if (!pictureView.fitted)
            parts.push(Math.round(pictureView.ratio * 100).toLocaleString(Qt.locale(), 'f', 0) + "%")
        return parts.join("  ·  ")
    }
    function showLevel(speed) {
        levelOsd.message = ""
        levelOsd.speed = speed
        levelOsd.shown = true
        levelTimer.restart()
    }
    // What came of something asked for: saved, copied, or why it failed.
    function showMessage(text) {
        levelOsd.message = text
        levelOsd.shown = true
        levelTimer.restart()
    }

    // The window opens at the picture's or the video's shape, as large as
    // fits in 80% of the screen, and never larger than the picture itself; a
    // song gets a small square for its cover. Each file that comes after
    // reshapes it the same way, so a tall picture doesn't leave a wide one
    // boxed in its shape. A window given a size other than the one asked for,
    // by a tiling compositor or by a hand resizing it, keeps that: asked to
    // change, a tiled one would shrink and then snap back.
    property size asked: Qt.size(960, 540)
    readonly property bool managed: visible && !reshaping
                                    && (Math.abs(width - asked.width) > 2 || Math.abs(height - asked.height) > 2)
    // A window on screen is reshaped by the compositor, which Hyprland has to
    // do itself. Until the new size comes, the last picture stays, and a
    // video draws nothing, rather than the next file in the last one's shape.
    property bool reshaping: false
    readonly property bool reshaped: Math.abs(width - asked.width) <= 2 && Math.abs(height - asked.height) <= 2
    onReshapedChanged: if (reshaped) reshaping = false
    Timer {
        id: reshapeTimer
        interval: 400
        onTriggered: win.reshaping = false
    }
    function ask(w, h) {
        if (Math.abs(width - w) <= 2 && Math.abs(height - h) <= 2)
            return
        asked = Qt.size(w, h)
        if (visible && backend.reshapeWindow(asked)) {
            reshaping = true
            reshapeTimer.restart()
            return
        }
        width = w
        height = h
    }
    function sizeTo(naturalWidth, naturalHeight) {
        sized = true
        if (managed)
            return
        const maxWidth = Screen.desktopAvailableWidth * 0.8, maxHeight = Screen.desktopAvailableHeight * 0.8
        const scale = Math.min(1, maxWidth / naturalWidth, maxHeight / naturalHeight)
        ask(Math.max(minimumWidth, Math.round(naturalWidth * scale)),
            Math.max(minimumHeight, Math.round(naturalHeight * scale)))
    }
    function sizeToMedia() {
        // A folder's first file, behind its grid, waits until it is picked. A
        // picture's shape is known only once it's decoded, and changes as
        // it turns, so a picture fits each time it does.
        if ((sized && !backend.isPicture) || fullscreen || gridShown || !backend.hasMedia || backend.error !== "")
            return
        if (backend.isPicture) {
            // Once it's decoded, out of sight, so the picture shows in the
            // same frame as the window takes its shape; its header says what
            // that shape is.
            if (!nextPictureDecoded())
                return
            const size = backend.pictureSize, turned = backend.rotation % 180 !== 0
            if (size.width > 0 && size.height > 0)
                sizeTo(turned ? size.height : size.width, turned ? size.width : size.height)
            else if (pictureView.ready)
                sizeTo(pictureView.turnedWidth, pictureView.turnedHeight)
        } else if (backend.hasVideo && backend.videoSize.width > 0) {
            sizeTo(backend.videoSize.width, backend.videoSize.height)
        } else if (!backend.hasVideo && !backend.loading && backend.duration > 0) {
            sizeSquare()
        }
    }
    function nextPictureDecoded() {
        return backend.vector || backend.animated
            || (backend.pictureSource.toString() !== ""
                && nextPicture.source.toString() === backend.pictureSource.toString()
                && (nextPicture.status === Image.Ready || nextPicture.status === Image.Error))
    }
    function sizeSquare() {
        sized = true
        if (managed)
            return
        const side = Math.max(minimumHeight, Math.min(520, Screen.desktopAvailableHeight * 0.6))
        ask(side, side)
    }
    // A folder's grid opens as wide as its tiles, up to as many as fit across
    // 80% of the screen, and as tall as its rows, in whole rows, up to 80% of
    // its height, so a small folder's is just its tiles. The tiles are laid
    // out as MediaGrid lays them: 4:3, with a gap around each.
    function sizeGrid() {
        if (fullscreen || managed)
            return
        const gap = 8, tile = gridTileSize
        const maxWidth = Screen.desktopAvailableWidth * 0.8, maxHeight = Screen.desktopAvailableHeight * 0.8
        const fit = Math.max(1, Math.floor((maxWidth - gap) / (tile + gap)))
        const columns = Math.min(fit, Math.max(1, backend.playlistCount))
        const wide = Math.max(minimumWidth, gap + columns * (tile + gap))
        // A window held wider than its tiles stretches them, as MediaGrid
        // does, so the rows are measured at the width they'll have.
        const across = wide - gap, laid = Math.max(1, Math.floor(across / (tile + gap)))
        const row = Math.round((Math.floor(across / laid) - gap) * 3 / 4) + gap
        const rows = Math.min(Math.max(1, Math.floor((maxHeight - 2 * gap) / row)),
                              Math.max(1, Math.ceil(backend.playlistCount / laid)))
        ask(wide, Math.max(minimumHeight, 2 * gap + rows * row))
    }

    // Started with a video or a song, measured before the window shows.
    function openAt(naturalWidth, naturalHeight, song) {
        if (naturalWidth > 0 && naturalHeight > 0)
            sizeTo(naturalWidth, naturalHeight)
        else if (song)
            sizeSquare()
        holding = false
    }

    // The screen stays on while a video plays, and only then.
    Binding {
        target: idle
        property: "active"
        value: backend.playing && backend.hasVideo
    }

    Connections {
        target: backend
        function onVideoSizeChanged() { win.sizeToMedia() }
        function onDurationChanged() { win.sizeToMedia() }
        function onStatusChanged() { win.sizeToMedia() }
        // Omaxian: clearOutput() is Qt 6.9+; on 6.8 the backend's empty frame clears it.
        function onPictureCleared() {
            if (videoLoader.item && videoLoader.item.clearOutput !== undefined) videoLoader.item.clearOutput()
        }
        function onFolderOpened() {
            win.gridShown = true
            win.sizeGrid()
            win.holding = false
        }
        function onNotice(text) { win.showMessage(text) }
        function onNothingToOpen() {
            win.opening = false
            win.holding = false
        }
        function onErrorChanged() {
            if (backend.error !== "")
                win.holding = false
        }
        function onMediaChanged() {
            win.opening = false
            // Each file takes the window to its own shape.
            win.sized = false
            // A file opened from elsewhere, Ctrl+O or a drop, shows rather than
            // playing behind the grid; a folder opens its grid again after.
            win.gridShown = false
            // Every picture opens fitted and moving.
            pictureView.reset()
            pictureView.paused = false
            win.poke()
        }
        function onSeeked() { win.poke() }
        function onPlayingChanged() { win.poke() }
        function onVolumeChanged() { win.poke() }
        function onRateChanged() { win.poke() }
        function onRotationChanged() { win.poke() }
    }

    onClosing: backend.close()

    readonly property bool picture: backend.hasMedia && backend.isPicture
    readonly property bool playable: backend.hasMedia && !backend.isPicture

    function step(forward) {
        if (forward)
            backend.next()
        else
            backend.previous()
    }
    // A picture larger than the window moves under the arrows; one that fits
    // steps to the next file.
    function arrow(dx, dy) {
        const distance = Math.max(40, Math.min(width, height) * 0.15)
        if (pictureView.pannable)
            pictureView.panBy(-dx * distance, -dy * distance)
        else if (dx !== 0)
            step(dx > 0)
    }

    Shortcut {
        sequence: "Space"
        enabled: backend.hasMedia
        onActivated: {
            if (!win.picture)
                backend.togglePlay()
            else if (backend.animated)
                pictureView.paused = !pictureView.paused
        }
    }
    Shortcut { sequence: "Left"; onActivated: win.picture ? win.arrow(-1, 0) : (backend.seekBy(-5000)) }
    Shortcut { sequence: "Right"; onActivated: win.picture ? win.arrow(1, 0) : (backend.seekBy(5000)) }
    Shortcut { sequence: "Shift+Left"; enabled: win.playable; onActivated: { backend.seekBy(-1000) } }
    Shortcut { sequence: "Shift+Right"; enabled: win.playable; onActivated: { backend.seekBy(1000) } }
    Shortcut {
        sequence: "Home"
        onActivated: win.picture ? backend.go(0) : backend.startOver()
    }
    Shortcut { sequence: "End"; enabled: win.picture; onActivated: backend.go(backend.playlistCount - 1) }
    function jumpTenth(n) {
        if (picture) {
            if (n === 0)
                pictureView.reset()
            else if (n === 1)
                pictureView.actualSize()
            return
        }
        backend.seekFraction(n / 10)
    }
    Shortcut { sequence: "0"; onActivated: win.jumpTenth(0) }
    Shortcut { sequence: "1"; onActivated: win.jumpTenth(1) }
    Shortcut { sequence: "2"; onActivated: win.jumpTenth(2) }
    Shortcut { sequence: "3"; onActivated: win.jumpTenth(3) }
    Shortcut { sequence: "4"; onActivated: win.jumpTenth(4) }
    Shortcut { sequence: "5"; onActivated: win.jumpTenth(5) }
    Shortcut { sequence: "6"; onActivated: win.jumpTenth(6) }
    Shortcut { sequence: "7"; onActivated: win.jumpTenth(7) }
    Shortcut { sequence: "8"; onActivated: win.jumpTenth(8) }
    Shortcut { sequence: "9"; onActivated: win.jumpTenth(9) }
    Shortcut { sequences: ["+", "="]; enabled: win.picture; onActivated: pictureView.zoomBy(1.25) }
    Shortcut { sequences: ["-", "_"]; enabled: win.picture; onActivated: pictureView.zoomBy(0.8) }
    // R turns a picture, and loops a video or a song.
    Shortcut { sequence: "R"; enabled: backend.hasMedia; onActivated: win.picture ? backend.rotate(90) : backend.toggleLoop() }
    Shortcut { sequence: "Shift+R"; enabled: win.picture; onActivated: backend.rotate(-90) }
    Shortcut { sequence: ","; enabled: win.playable; onActivated: { backend.stepFrame(-1) } }
    Shortcut { sequence: "."; enabled: win.playable; onActivated: { backend.stepFrame(1) } }
    Shortcut {
        sequence: "PgUp"
        onActivated: {
            if (win.picture)
                return win.step(false)
            backend.jumpChapter(-1)
        }
    }
    Shortcut {
        sequence: "PgDown"
        onActivated: {
            if (win.picture)
                return win.step(true)
            backend.jumpChapter(1)
        }
    }
    Shortcut { sequence: "["; enabled: win.playable; onActivated: { backend.changeRate(-0.25); win.showLevel(true) } }
    Shortcut { sequence: "]"; enabled: win.playable; onActivated: { backend.changeRate(0.25); win.showLevel(true) } }
    Shortcut { sequence: "Backspace"; enabled: win.playable; onActivated: { backend.resetRate(); win.showLevel(true) } }
    Shortcut { sequence: "Up"; onActivated: win.picture ? win.arrow(0, -1) : (backend.changeVolume(0.05), win.showLevel(false)) }
    Shortcut { sequence: "Down"; onActivated: win.picture ? win.arrow(0, 1) : (backend.changeVolume(-0.05), win.showLevel(false)) }
    Shortcut { sequence: "M"; enabled: win.playable; onActivated: { backend.toggleMute(); win.showLevel(false) } }
    Shortcut {
        sequence: "C"
        enabled: win.playable
        onActivated: backend.cycleSubtitles()
    }
    Shortcut {
        sequence: "A"
        enabled: win.playable
        onActivated: backend.cycleAudio()
    }
    Shortcut { sequence: "Tab"; onActivated: win.overlayShown = !win.overlayShown }
    Shortcut { sequence: "F"; onActivated: win.toggleFullscreen() }
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (win.overlayShown)
                win.overlayShown = false
            else if (win.fullscreen)
                win.showNormal()
        }
    }
    Shortcut { sequence: "N"; onActivated: win.step(true) }
    Shortcut { sequence: "P"; onActivated: win.step(false) }
    Shortcut { sequences: ["Return", "Enter"]; enabled: backend.ended && backend.nextName !== ""; onActivated: backend.next() }
    Shortcut { sequence: "I"; enabled: backend.hasMedia; onActivated: infoCard.opened ? infoCard.close() : infoCard.open() }
    Shortcut { sequences: ["Ctrl+C", "Ctrl+Shift+C"]; enabled: backend.hasMedia; onActivated: backend.copy() }
    Shortcut { sequence: "Ctrl+S"; enabled: win.playable; onActivated: backend.saveFrame() }
    Shortcut { sequence: "Ctrl+P"; enabled: win.picture; onActivated: backend.print() }
    Shortcut { sequence: "E"; enabled: backend.canEdit; onActivated: backend.edit() }
    // Recoverable from the Trash, and with Ctrl+Z, so it doesn't ask first,
    // as Omarchy's imv binding didn't.
    Shortcut {
        sequence: "Del"
        enabled: backend.hasMedia
        onActivated: backend.trash()
    }
    Shortcut { sequence: "Ctrl+Z"; onActivated: backend.undoTrash() }
    Shortcut { sequence: "Ctrl+O"; onActivated: backend.openDialog() }
    Shortcut {
        sequence: "Ctrl+M"
        enabled: backend.playlistCount > 0
        onActivated: win.toggleGrid()
    }
    function toggleGrid() {
        // What was playing waits behind the grid.
        if (!gridShown && backend.playing)
            backend.togglePlay()
        gridShown = !gridShown
    }
    function zoomGrid(factor) {
        gridTileSize = Math.max(120, Math.min(720, Math.round(gridTileSize * factor)))
    }
    Shortcut { sequences: ["Ctrl++", "Ctrl+="]; enabled: win.gridShown; onActivated: win.zoomGrid(1.25) }
    Shortcut { sequences: ["Ctrl+-", "Ctrl+_"]; enabled: win.gridShown; onActivated: win.zoomGrid(0.8) }
    Shortcut { sequences: ["?", "F1"]; onActivated: help.opened ? help.close() : help.open() }
    Shortcut { sequences: ["Q", "Ctrl+Q"]; onActivated: win.close() }

    // Right-to-left languages mirror the window; the Translator sets the
    // application's layout direction.
    Item {
        id: root
        anchors.fill: parent
        LayoutMirroring.enabled: win.rightToLeft
        LayoutMirroring.childrenInherit: true

        // Kept until the first file, so a window with nothing to play never
        // starts Qt Multimedia's FFmpeg backend.
        Loader {
            id: videoLoader
            anchors.fill: parent
            visible: !backend.isPicture && !win.reshaping
            active: backend.playerReady
            sourceComponent: VideoOutput {
                id: video
                objectName: "video"
                fillMode: VideoOutput.PreserveAspectFit
                // endOfStreamPolicy is Qt 6.9+; on 6.8 the last frame already stays.
                // Omaxian: read through the id. A bare name that 6.8 lacks throws a
                // ReferenceError, which also skipped setVideoSink (no picture).
                Component.onCompleted: {
                    if (video.endOfStreamPolicy !== undefined) video.endOfStreamPolicy = VideoOutput.KeepLastFrame
                    backend.setVideoSink(videoSink)
                }
                // Detached as destruction begins, before the sink is torn
                // down, so the decoder's thread never hands it a frame after.
                Component.onDestruction: backend.setVideoSink(null)
            }
        }
        readonly property rect picture: videoLoader.item && backend.hasVideo
                                        ? videoLoader.item.contentRect : Qt.rect(0, 0, width, height)

        // A picture, which never starts the player.
        PictureView {
            id: pictureView
            anchors.fill: parent
            visible: win.picture && backend.error === ""
            animated: backend.animated
            vector: backend.vector
            transparent: backend.transparent
            vectorSize: backend.pictureSize
            turn: backend.rotation
            onZoomChanged: win.poke()
            // Once both sides have turned, not in between.
            onTurnedWidthChanged: Qt.callLater(win.sizeToMedia)
            onTurnedHeightChanged: Qt.callLater(win.sizeToMedia)
            onReadyChanged: {
                win.sizeToMedia()
                if (ready)
                    win.holding = false
            }
            onFailed: backend.pictureFailed()
        }
        // The next picture decodes out of sight, as the window takes its
        // shape, and the view takes it from Qt's cache once both are done:
        // the last picture stays until then, so stepping through a folder
        // never flashes black, nor shows a picture in the last one's shape.
        // A video between them lets it go, so it can't show for a moment after.
        Image {
            id: nextPicture
            visible: false
            asynchronous: true
            autoTransform: true
            source: win.picture && !backend.vector && !backend.animated ? backend.pictureSource : ""
        }
        function showPicture() {
            if (!win.picture) {
                pictureView.source = ""
                return
            }
            // The window is asked for the picture's shape first.
            win.sizeToMedia()
            const source = backend.pictureSource
            if (source.toString() === "" || win.reshaping)
                return
            if (!win.nextPictureDecoded())
                return
            pictureView.source = source
        }
        Connections {
            target: nextPicture
            function onStatusChanged() { root.showPicture() }
            function onSourceChanged() { root.showPicture() }
        }
        Connections {
            target: win
            function onReshapingChanged() { root.showPicture() }
            function onPictureChanged() { root.showPicture() }
        }
        Connections {
            target: backend
            function onPictureChanged() { root.showPicture() }
        }

        // A song: its cover and its name.
        ColumnLayout {
            anchors.centerIn: parent
            visible: win.playable && !backend.hasVideo && !backend.loading && backend.error === ""
            spacing: 14
            width: Math.min(parent.width - 48, 420)
            Image {
                Layout.alignment: Qt.AlignHCenter
                visible: backend.coverArt !== ""
                source: backend.coverArt
                fillMode: Image.PreserveAspectFit
                Layout.preferredWidth: Math.min(root.width * 0.6, root.height * 0.55, 360)
                Layout.preferredHeight: Layout.preferredWidth
            }
            Icon {
                Layout.alignment: Qt.AlignHCenter
                visible: backend.coverArt === ""
                name: "music"
                size: 64
                color: "#6a6a70"
            }
            Text {
                Layout.fillWidth: true
                text: backend.title
                color: "white"
                font.pixelSize: 20
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: backend.artist !== ""
                text: backend.artist
                color: "#9a9aa0"
                font.pixelSize: 15
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
        }

        // Subtitles, drawn in one style whether they came from the file or
        // from beside it, sized to the picture.
        Text {
            id: subtitle
            objectName: "subtitle"
            visible: text !== ""
            text: backend.subtitleText
            textFormat: Text.PlainText
            color: "white"
            width: root.picture.width * 0.9
            x: root.picture.x + (root.picture.width - width) / 2
            y: root.picture.y + root.picture.height - height - root.picture.height * 0.06
               - (win.overlayShown ? Math.max(0, 140 - (root.height - root.picture.y - root.picture.height)) : 0)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.pixelSize: Math.max(14, Math.round(root.picture.height * 0.045))
            font.weight: Font.Medium
            style: Text.Outline
            styleColor: Qt.rgba(0, 0, 0, 0.6)
            Rectangle {
                z: -1
                anchors.centerIn: parent
                width: subtitle.contentWidth + 24
                height: subtitle.contentHeight + 8
                color: Qt.rgba(0, 0, 0, 0.55)
            }
        }

        // Nothing open yet: a play button, and a click anywhere opens files.
        Icon {
            anchors.centerIn: parent
            visible: !backend.hasMedia && !win.opening
            name: "play"
            size: 120
            color: theme.accent
        }

        // What went wrong, in plain words, rather than a black picture.
        ColumnLayout {
            anchors.centerIn: parent
            visible: backend.hasMedia && backend.error !== ""
            width: Math.min(parent.width - 48, 520)
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: (backend.isPicture ? qsTr("Can't show %1") : qsTr("Can't play %1")).arg(backend.fileName)
                color: "white"
                font.pixelSize: 17
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
            Text {
                objectName: "error"
                Layout.fillWidth: true
                text: backend.error
                color: "#9a9aa0"
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }

        // Clicking plays and pauses; a double click is fullscreen, and its
        // second click undoes the first one's pause.
        // A picture only goes fullscreen.
        TapHandler {
            id: tap
            enabled: backend.hasMedia
            onTapped: {
                if (!backend.isPicture)
                    backend.togglePlay()
                if (tap.tapCount === 2)
                    win.toggleFullscreen()
            }
        }
        TapHandler {
            enabled: !backend.hasMedia
            onTapped: backend.openDialog()
        }
        // The wheel is the volume; over a picture it zooms instead.
        WheelHandler {
            enabled: win.playable
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const steps = event.angleDelta.y / 120
                if (steps === 0)
                    return
                backend.changeVolume(0.05 * steps)
                win.showLevel(false)
            }
        }
        // The pointer hides after a second of stillness.
        HoverHandler {
            id: pointer
            property bool still: false
            cursorShape: !backend.hasMedia ? Qt.PointingHandCursor
                         : still && !win.overlayShown ? Qt.BlankCursor : Qt.ArrowCursor
            onPointChanged: { still = false; stillTimer.restart() }
        }
        Timer { id: stillTimer; interval: 1000; onTriggered: pointer.still = true }

        DropArea {
            anchors.fill: parent
            onDropped: drop => {
                if (drop.hasUrls) {
                    backend.openUrls(drop.urls)
                    drop.accept()
                }
            }
        }

        // The thin line, which grows into a timeline when the pointer comes
        // to the bottom edge or a key seeks. Fullscreen, there's no line, only
        // the timeline when the pointer comes.
        Item {
            id: bottomEdge
            visible: win.playable && !win.overlayShown
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 40
            HoverHandler { id: edgeHover }
            Rectangle {
                anchors.fill: parent
                visible: bareTimeline.expanded
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) }
                }
            }
            Timeline {
                id: bareTimeline
                objectName: "progressLine"
                visible: expanded || !win.fullscreen
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: expanded ? 16 : 0
                anchors.rightMargin: expanded ? 16 : 0
                anchors.bottomMargin: expanded ? 6 : 0
                expanded: edgeHover.hovered
            }
        }

        // The corner: playing or paused, the time, the file; for a picture,
        // where it is in the folder and how far it is zoomed.
        Rectangle {
            id: cornerOsd
            objectName: "cornerOsd"
            property bool shown: false
            visible: opacity > 0
            opacity: shown && backend.hasMedia && !win.overlayShown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            x: win.rightToLeft ? parent.width - width - 20 : 20
            y: 20
            width: cornerRow.implicitWidth + 28
            height: 40
            radius: Math.min(4, theme.radius)
            color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.85)
            Row {
                id: cornerRow
                anchors.centerIn: parent
                spacing: 12
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: backend.isPicture ? "picture" : backend.playing ? "play" : "pause"
                    size: 14
                    color: theme.accent
                }
                Text {
                    objectName: "cornerStatus"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    // Formatted only while it shows, not on every position update.
                    text: !cornerOsd.visible ? ""
                          : backend.isPicture ? win.pictureStatus()
                          : backend.duration > 0 ? Format.clock(backend.position) + " / " + Format.clock(backend.duration)
                          : Format.clock(backend.position)
                    color: theme.foreground
                    font.family: "monospace"
                    font.pixelSize: 13
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: backend.fileName
                    color: theme.colors.muted
                    font.pixelSize: 13
                    elide: Text.ElideMiddle
                    width: Math.min(implicitWidth, win.width * 0.5)
                }
            }
        }
        Timer {
            id: cornerTimer
            interval: 2000
            // A paused video keeps it; a picture, which never plays, doesn't.
            onTriggered: cornerOsd.shown = win.playable && (!backend.playing || backend.loading)
        }

        // The volume and the speed, the changes a key makes that show:
        // briefly, in the middle.
        Rectangle {
            id: levelOsd
            objectName: "levelOsd"
            property bool shown: false
            property bool speed: false
            property string message
            visible: opacity > 0
            opacity: shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, levelColumn.implicitWidth + 52)
            height: levelColumn.implicitHeight + 32
            radius: theme.radius
            color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.85)
            Column {
                id: levelColumn
                anchors.centerIn: parent
                spacing: 8
                Text {
                    objectName: "levelMessage"
                    visible: levelOsd.message !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(implicitWidth, levelOsd.parent.width - 92)
                    text: levelOsd.message
                    color: theme.foreground
                    font.pixelSize: 17
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    objectName: "levelValue"
                    visible: levelOsd.message === ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: levelOsd.speed
                          ? backend.rate.toLocaleString(Qt.locale(), 'f', backend.rate * 4 % 4 === 0 ? 0 : 2) + "×"
                          : backend.muted ? qsTr("Muted")
                          : Math.round(backend.volume * 100).toLocaleString(Qt.locale(), 'f', 0) + "%"
                    color: theme.accent
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: levelOsd.message === ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: levelOsd.speed ? qsTr("Speed") : qsTr("Volume")
                    color: theme.colors.muted
                    font.pixelSize: 13
                }
            }
        }
        Timer { id: levelTimer; interval: 2000; onTriggered: levelOsd.shown = false }

        // Made only while it shows, so its clock and timeline cost nothing
        // during bare playback.
        Loader {
            id: controls
            objectName: "overlay"
            anchors.fill: parent
            active: win.overlayShown && backend.hasMedia
            sourceComponent: ControlsOverlay {
                fullscreen: win.fullscreen
                picture: pictureView
                onToggleFullscreen: win.toggleFullscreen()
                onShowKeys: help.open()
                onShowGrid: win.toggleGrid()
                opacity: 0
                Component.onCompleted: opacity = 1
                Behavior on opacity { NumberAnimation { duration: 150 } }
            }
        }
    }

    Loader {
        id: gridLoader
        anchors.fill: parent
        active: win.gridShown
        sourceComponent: MediaGrid {
            tileSize: win.gridTileSize
            // The window takes the shape of the file picked, once it has
            // one; the one already open, behind the grid, has it now.
            onPicked: index => {
                const opened = backend.go(index)
                win.gridShown = false
                if (!opened) {
                    win.sizeToMedia()
                    // The file already open plays when picked, as any other would.
                    if (win.playable && !backend.playing)
                        backend.togglePlay()
                }
            }
            onClosed: {
                win.gridShown = false
                win.sizeToMedia()
            }
        }
        onLoaded: item.forceActiveFocus()
    }

    // I: what's in the file.
    Popup {
        id: infoCard
        objectName: "info"
        anchors.centerIn: Overlay.overlay
        width: Math.min(win.width - 40, 560)
        height: Math.min(win.height - 40, infoColumn.implicitHeight + 40)
        modal: true
        focus: true
        // Darkened behind, as a player's picture should be, not washed out.
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }
        padding: 20
        // A modal popup holds the window's keys, so its own keys close it and
        // quit while it is open.
        Shortcut { sequence: "I"; enabled: infoCard.opened; onActivated: infoCard.close() }
        Shortcut { sequences: ["Q", "Ctrl+Q"]; enabled: infoCard.opened; onActivated: win.close() }
        background: Rectangle {
            color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.95)
            border.color: theme.colors.selection
            radius: theme.radius
        }
        Flickable {
            anchors.fill: parent
            contentHeight: infoColumn.implicitHeight
            clip: true
            ColumnLayout {
                id: infoColumn
                width: parent.width
                spacing: 6
                LayoutMirroring.enabled: win.rightToLeft
                LayoutMirroring.childrenInherit: true
                Repeater {
                    model: backend.info
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 16
                        Label {
                            Layout.preferredWidth: 110
                            text: modelData.label
                            color: theme.colors.muted
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.value
                            wrapMode: Text.Wrap
                        }
                    }
                }
                Label {
                    visible: backend.chapters.length > 0
                    Layout.topMargin: 8
                    text: qsTr("Chapters")
                    color: theme.colors.muted
                    font.capitalization: Font.AllUppercase
                    font.pixelSize: 11
                }
                Repeater {
                    model: backend.chapters
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 16
                        Label {
                            Layout.preferredWidth: 110
                            text: Format.clock(modelData.start)
                            font.family: "monospace"
                            color: modelData.title === backend.chapterTitle ? theme.accent : theme.colors.muted
                        }
                        Label {
                            Layout.fillWidth: true
                            text: modelData.title
                            color: modelData.title === backend.chapterTitle ? theme.accent : theme.foreground
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // ?: every key.
    Popup {
        id: help
        objectName: "help"
        anchors.centerIn: Overlay.overlay
        width: Math.min(win.width - 40, helpGrid.implicitWidth + 48)
        height: Math.min(win.height - 40, helpGrid.implicitHeight + 48)
        modal: true
        focus: true
        // Darkened behind, as a player's picture should be, not washed out.
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }
        padding: 24
        Shortcut { sequences: ["?", "F1"]; enabled: help.opened; onActivated: help.close() }
        Shortcut { sequences: ["Q", "Ctrl+Q"]; enabled: help.opened; onActivated: win.close() }
        background: Rectangle {
            color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.95)
            border.color: theme.colors.selection
            radius: theme.radius
        }
        Flickable {
            anchors.fill: parent
            contentHeight: helpGrid.implicitHeight
            contentWidth: width
            clip: true
            GridLayout {
                id: helpGrid
                columns: 2
                columnSpacing: 24
                rowSpacing: 6
                // A popup is not an Item and doesn't inherit the window's
                // mirroring, so its content opts in.
                LayoutMirroring.enabled: win.rightToLeft
                LayoutMirroring.childrenInherit: true
                Repeater {
                    model: win.shortcutList
                    delegate: Label {
                        required property var modelData
                        required property int index
                        Layout.row: index
                        Layout.column: 0
                        Layout.columnSpan: modelData.header ? 2 : 1
                        Layout.topMargin: modelData.header && index > 0 ? 12 : 0
                        text: modelData.header ? modelData.action : modelData.keys
                        color: modelData.header ? theme.colors.muted : theme.accent
                        font.family: modelData.header ? win.font.family : "monospace"
                        font.bold: !modelData.header
                        font.capitalization: modelData.header ? Font.AllUppercase : Font.MixedCase
                    }
                }
                Repeater {
                    model: win.shortcutList
                    delegate: Label {
                        required property var modelData
                        required property int index
                        visible: !modelData.header
                        Layout.row: index
                        Layout.column: 1
                        text: modelData.action
                    }
                }
            }
        }
    }
}

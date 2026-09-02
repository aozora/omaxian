import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Ui
import qs.Commons
import "MediaHelper.js" as MediaHelper

// Popup now-playing controller for any MPRIS player (mpv, browsers, VLC,
// Spotify, playerctld…) — ported from MrDemonc/Omarchy-media-control, which
// targets the same qs.Ui/qs.Commons kit this port carries (BorderSurface,
// KeyboardPanel, PanelSlider, Border.controlSpec, Style.space/font/spacing
// tokens all match 1:1, so the popup came across with no API shims).
//
// `local.mpd` (bar/widgets/Mpd.qml + scripts/mpd.sh, an `mpc idleloop`
// process) is retired by this port: with `mpdris2` installed, MPD bridges
// itself onto the session bus as `org.mpris.MediaPlayer2.mpd` and shows up
// in `Mpris.players` like any other source — see MediaHelper.js for the
// small MPD-aware additions (native-player classification, icon, display
// name) layered on top of the upstream helper. `i3_autostart` starts
// `mpDris2` alongside `mpd` so the bridge is actually running each session.
//
// Left click: open/close the popup · middle click: play/pause · scroll:
// next/previous · click the source badge to switch players when more than
// one is active.
//
// MPRIS titles/artists/album/player names are untrusted (browser tabs).
// Every Text {} uses textFormat: Text.PlainText so Qt AutoText cannot
// fetch a remote <img src> from metadata — same hardening as Omarchy 4.0.2.
BarWidget {
  id: root
  moduleName: "omaxian.media"

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color bg: root.bar ? root.bar.background : Color.background
  readonly property color dim: Qt.darker(root.fg, 1.4)
  readonly property color subdim: Qt.darker(root.fg, 1.7)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  // MPRIS Players
  readonly property var players: Mpris.players ? Mpris.players.values : []
  property string preferredPlayerKey: ""
  property bool showSourceList: false
  property bool popupOpen: false
  property int coverStyle: 0

  // Seeking and progress state
  property bool isSeeking: false
  property real livePosition: 0
  property real basePosition: 0
  property double lastSyncTime: 0
  property real lastKnownMprisPos: -1
  property string lastTrackSignature: ""

  // Filter valid players with metadata or playback capability
  readonly property var activeSourcePlayers: {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (MediaHelper.hasMetadata(p) || (p && p.isPlaying)) {
        list.push(p)
      }
    }
    // Sort playing first, then non-proxy, then alphabetical
    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (MediaHelper.isProxyPlayer(a) !== MediaHelper.isProxyPlayer(b)) return MediaHelper.isProxyPlayer(a) ? 1 : -1
      var la = a.trackTitle || a.identity || ""
      var lb = b.trackTitle || b.identity || ""
      return la.localeCompare(lb)
    })
    return list
  }

  // Determine active player
  readonly property var activePlayer: {
    if (preferredPlayerKey !== "") {
      for (var i = 0; i < players.length; i++) {
        if (MediaHelper.playerKey(players[i]) === preferredPlayerKey) {
          return players[i]
        }
      }
    }
    if (activeSourcePlayers.length > 0) {
      return activeSourcePlayers[0]
    }
    return players.length > 0 ? players[0] : null
  }

  readonly property bool hasMedia: activePlayer !== null && !!(activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property bool isPlaying: activePlayer ? !!activePlayer.isPlaying : false
  readonly property string trackTitle: activePlayer ? (activePlayer.trackTitle || "Untitled") : "No media"
  readonly property string trackArtist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string trackAlbum: activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string effectiveArtUrl: MediaHelper.getEffectiveArtUrl(activePlayer)
  readonly property string playerApp: activePlayer ? MediaHelper.playerDisplayName(activePlayer) : ""
  readonly property string playerGlyph: activePlayer ? MediaHelper.playerIcon(activePlayer) : "󰝚"
  readonly property bool isWebSource: activePlayer ? MediaHelper.isWebPlayer(activePlayer) : false
  readonly property real trackLength: (activePlayer && !isWebSource && MediaHelper.isValidDuration(activePlayer.length))
    ? MediaHelper.normalizeSeconds(activePlayer.length)
    : 0
  readonly property bool hasKnownDuration: !isWebSource && trackLength > 5
  readonly property real playerVolume: activePlayer && typeof activePlayer.volume === "number" ? Math.max(0, Math.min(1, activePlayer.volume)) : 1.0

  readonly property string currentTrackSignature: activePlayer
    ? (String(activePlayer.trackTitle || "") + "||" + String(activePlayer.trackArtist || "") + "||" + String(activePlayer.length || 0))
    : ""

  // Reset progress timeline when track changes
  onCurrentTrackSignatureChanged: {
    if (currentTrackSignature !== lastTrackSignature) {
      lastTrackSignature = currentTrackSignature
      var rawPos = (activePlayer && hasKnownDuration) ? MediaHelper.normalizeSeconds(activePlayer.position) : 0
      basePosition = rawPos
      lastKnownMprisPos = rawPos
      lastSyncTime = Date.now()
      livePosition = rawPos
    }
  }

  // Resync when active player changes
  onActivePlayerChanged: {
    if (activePlayer) {
      var rawPos = hasKnownDuration ? MediaHelper.normalizeSeconds(activePlayer.position) : 0
      basePosition = rawPos
      lastKnownMprisPos = rawPos
      lastSyncTime = Date.now()
      livePosition = rawPos
    }
  }

  // Update sync timestamp when playback state changes
  onIsPlayingChanged: {
    if (activePlayer && hasKnownDuration) {
      var rawPos = MediaHelper.normalizeSeconds(activePlayer.position)
      basePosition = rawPos > 0 ? rawPos : livePosition
      lastKnownMprisPos = rawPos
      lastSyncTime = Date.now()
    }
  }

  // Timer to smoothly advance timeline while playing
  Timer {
    id: positionTimer
    interval: 250
    running: root.popupOpen && root.isPlaying && !root.isSeeking && root.hasKnownDuration
    repeat: true
    onTriggered: {
      if (!root.activePlayer || !root.hasKnownDuration) return

      var mprisPos = MediaHelper.normalizeSeconds(root.activePlayer.position)
      var elapsed = (Date.now() - root.lastSyncTime) / 1000.0
      var computed = root.basePosition + elapsed

      // If player reported a real external seek event
      if (mprisPos > 0 && Math.abs(mprisPos - computed) > 2.0 && Math.abs(mprisPos - root.lastKnownMprisPos) > 0.05) {
        root.basePosition = mprisPos
        root.lastKnownMprisPos = mprisPos
        root.lastSyncTime = Date.now()
        computed = mprisPos
      }

      if (computed >= root.trackLength) {
        root.livePosition = root.trackLength
      } else {
        root.livePosition = Math.max(0, computed)
      }
    }
  }

  // Process runner for busctl DBus fallback
  Process {
    id: dbusProc
    function exec(args) {
      command = args
      running = true
    }
  }

  function close() {
    popupOpen = false
    showSourceList = false
  }

  function togglePlayPause() {
    if (!activePlayer) return
    if (activePlayer.canTogglePlaying) {
      activePlayer.togglePlaying()
    } else if (activePlayer.isPlaying && activePlayer.canPause) {
      activePlayer.pause()
    } else if (!activePlayer.isPlaying && activePlayer.canPlay) {
      activePlayer.play()
    }
  }

  function previousTrack() {
    if (activePlayer && activePlayer.canGoPrevious) {
      activePlayer.previous()
    }
  }

  function nextTrack() {
    if (activePlayer && activePlayer.canGoNext) {
      activePlayer.next()
    }
  }

  function stopTrack() {
    if (!activePlayer) return
    if (typeof activePlayer.stop === "function") {
      activePlayer.stop()
    } else if (activePlayer.canPause) {
      activePlayer.pause()
    }
  }

  function seek(targetSeconds) {
    if (!activePlayer || !hasKnownDuration) return
    var target = Math.max(0, targetSeconds)
    var targetUs = target * 1000000

    if (typeof activePlayer.setPosition === "function") {
      activePlayer.setPosition(target)
    } else {
      activePlayer.position = target
    }

    if (activePlayer.dbusName) {
      var trackId = activePlayer.trackId || "/org/mpris/MediaPlayer2/TrackList/NoTrack"
      dbusProc.exec(["busctl", "--user", "call", String(activePlayer.dbusName), "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "SetPosition", "ox", String(trackId), String(Math.round(targetUs))])
    }

    basePosition = target
    lastKnownMprisPos = target
    lastSyncTime = Date.now()
    livePosition = target
  }

  function setPlayerVolume(vol) {
    if (activePlayer && typeof activePlayer.volume === "number") {
      activePlayer.volume = Math.max(0, Math.min(1, vol))
    }
  }

  function selectPlayer(player) {
    if (!player) return
    preferredPlayerKey = MediaHelper.playerKey(player)
    showSourceList = false
  }

  // Widget dimensions on the bar
  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  // Bar button with active state & tooltip
  BarIconButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: root.isPlaying ? "󰎆" : "󰝚"
    active: root.isPlaying || root.popupOpen
    useActiveColor: root.isPlaying
    tooltipText: root.hasMedia ? (root.trackTitle + (root.trackArtist ? " — " + root.trackArtist : "")) : "Media Controller"

    iconComponent: Component {
      Text {
        textFormat: Text.PlainText
        text: root.isPlaying ? "󰎆" : (root.hasMedia ? "󰐊" : "󰝚")
        color: barButton.active && barButton.useActiveColor
          ? (root.bar ? root.bar.foreground : Color.accent)
          : (root.hasMedia ? root.fg : root.dim)
        font.family: barButton.fontFamily
        font.pixelSize: barButton.fontSize
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }

    onPressed: function(button) {
      if (button === Qt.MiddleButton) {
        root.togglePlayPause()
      } else {
        root.popupOpen = !root.popupOpen
      }
    }

    onWheelMoved: function(delta) {
      if (delta > 0) {
        root.previousTrack()
      } else if (delta < 0) {
        root.nextTrack()
      }
    }
  }

  // Keyboard-accessible layer-shell popup
  KeyboardPanel {
    id: panel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.popupOpen
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(350))
    contentHeight: panel.fittedContentHeight(popupLayout.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Keys.onEscapePressed: function(event) {
        root.close()
        event.accepted = true
      }

      Column {
        id: popupLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // Top Header: Player Source + Stop Button & CAVA Visualizer Effect
        Row {
          width: parent.width
          Item {
            width: parent.width
            height: Math.max(sourceHeaderLeft.height, cavaContainer.height)

            // Left Group: Source badge + Stop button
            Row {
              id: sourceHeaderLeft
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              // Player badge
              BorderSurface {
                id: sourceBadge
                radius: Style.spacing.labelGap
                color: Style.normalFillFor(root.fg, Color.accent)
                borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
                width: sourceBadgeRow.implicitWidth + Style.space(16)
                height: sourceBadgeRow.implicitHeight + Style.space(8)

                Row {
                  id: sourceBadgeRow
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Text {
                    textFormat: Text.PlainText
                    text: root.playerGlyph
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: root.playerApp !== "" ? root.playerApp : "Media Player"
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    visible: root.activeSourcePlayers.length > 1
                    text: root.showSourceList ? "▲" : "▼"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption * 0.8
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: root.activeSourcePlayers.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: {
                    if (root.activeSourcePlayers.length > 1) {
                      root.showSourceList = !root.showSourceList
                    }
                  }
                }
              }

              // Stop Button next to the source badge
              Button {
                id: stopBtn
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰓛"
                foreground: root.fg
                iconSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(3)
                visible: root.isPlaying
                tooltipText: "Stop"
                onClicked: root.stopTrack()
              }
            }

            // Header Right: CAVA Audio Visualizer Effect
            Item {
              id: cavaContainer
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: cavaRow.implicitWidth
              height: Style.space(20)

              Row {
                id: cavaRow
                anchors.bottom: parent.bottom
                spacing: Style.space(3)
                height: parent.height

                Repeater {
                  model: [
                    { minH: 3, maxH: 15, d1: 280, d2: 380, d3: 240, d4: 420 },
                    { minH: 4, maxH: 19, d1: 220, d2: 340, d3: 390, d4: 260 },
                    { minH: 3, maxH: 16, d1: 360, d2: 250, d3: 310, d4: 410 },
                    { minH: 4, maxH: 20, d1: 250, d2: 400, d3: 230, d4: 330 },
                    { minH: 3, maxH: 14, d1: 390, d2: 270, d3: 350, d4: 210 }
                  ]

                  Rectangle {
                    id: cavaBar
                    required property var modelData
                    required property int index

                    width: Style.space(3.5)
                    height: Style.space(modelData.minH)
                    anchors.bottom: parent.bottom
                    radius: 0
                    color: root.isPlaying
                      ? (root.bar ? root.bar.foreground : Color.accent)
                      : root.dim
                    opacity: root.isPlaying ? 0.95 : 0.35

                    SequentialAnimation on height {
                      running: root.popupOpen && root.isPlaying
                      loops: Animation.Infinite

                      NumberAnimation {
                        to: Style.space(modelData.maxH)
                        duration: modelData.d1
                        easing.type: Easing.InOutQuad
                      }
                      NumberAnimation {
                        to: Style.space(modelData.minH + 3)
                        duration: modelData.d2
                        easing.type: Easing.InOutQuad
                      }
                      NumberAnimation {
                        to: Style.space(modelData.maxH - 3)
                        duration: modelData.d3
                        easing.type: Easing.InOutQuad
                      }
                      NumberAnimation {
                        to: Style.space(modelData.minH)
                        duration: modelData.d4
                        easing.type: Easing.InOutQuad
                      }
                    }

                    Behavior on height {
                      enabled: !root.isPlaying
                      NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                      ColorAnimation { duration: 200 }
                    }
                    Behavior on opacity {
                      NumberAnimation { duration: 200 }
                    }
                  }
                }
              }
            }
          }
        }

        // Multi-Source Selector Dropdown / Drawer
        Column {
          id: sourceDrawer
          visible: root.showSourceList && root.activeSourcePlayers.length > 1
          width: parent.width
          spacing: Style.space(4)

          PanelSeparator {
            foreground: root.fg
          }

          Text {
            textFormat: Text.PlainText
            text: "MEDIA SOURCES"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: Style.font.caption * 0.1
          }

          Repeater {
            model: root.activeSourcePlayers

            BorderSurface {
              id: playerItemRow
              required property var modelData
              readonly property var p: modelData
              readonly property bool isSelected: root.activePlayer && MediaHelper.playerKey(root.activePlayer) === MediaHelper.playerKey(p)

              width: parent.width
              height: playerItemContent.implicitHeight + Style.space(8)
              radius: Style.spacing.labelGap
              color: isSelected ? Style.selectedFillFor(root.fg, Color.accent) : "transparent"
              borderSpec: isSelected ? Border.controlSpec("normal", root.fg, Color.accent) : Border.none()

              Row {
                id: playerItemContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text {
                  textFormat: Text.PlainText
                  text: MediaHelper.playerIcon(playerItemRow.p)
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  width: parent.width - Style.space(40)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(1)

                  Text {
                    textFormat: Text.PlainText
                    text: playerItemRow.p.trackTitle || MediaHelper.playerDisplayName(playerItemRow.p)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: playerItemRow.isSelected
                    elide: Text.ElideRight
                    width: parent.width
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: playerItemRow.p.trackArtist || (playerItemRow.p.isPlaying ? "Playing" : "Paused")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    width: parent.width
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  text: playerItemRow.p.isPlaying ? "󰏤" : "󰐊"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: root.selectPlayer(playerItemRow.p)
              }
            }
          }

          PanelSeparator {
            foreground: root.fg
          }
        }

        // STATE 1: ACTIVE MEDIA
        Column {
          id: mediaContent
          visible: root.activePlayer !== null
          width: parent.width
          spacing: Style.space(12)

          // Hero: Album Art + Track / Artist info
          Row {
            width: parent.width
            spacing: Style.space(12)

            // Album Artwork Box (Click to toggle Normal / Spinning Vinyl)
            Item {
              id: coverArtWrapper
              width: Style.space(78)
              height: Style.space(78)

              BorderSurface {
                id: coverArtBox
                anchors.fill: parent
                radius: root.coverStyle === 1 ? width / 2 : Style.spacing.labelGap
                color: Style.normalFillFor(root.fg, Color.accent)
                borderSpec: Border.controlSpec("normal", root.fg, Color.accent)
                clip: true

                Behavior on radius {
                  NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }

                // Masked Image Container (Ensures true circular masking)
                Item {
                  id: coverImageContainer
                  anchors.fill: parent
                  anchors.margins: Style.space(1)
                  layer.enabled: true
                  layer.smooth: true
                  layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: maskShape
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 0.02
                  }

                  Image {
                    id: coverImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    mipmap: true
                    source: root.effectiveArtUrl
                    visible: status === Image.Ready && source !== ""
                  }
                }

                // Alpha Mask for image clipping
                Rectangle {
                  id: maskShape
                  anchors.fill: parent
                  anchors.margins: Style.space(1)
                  radius: root.coverStyle === 1 ? width / 2 : Style.spacing.labelGap
                  color: "white"
                  visible: false
                  layer.enabled: true

                  Behavior on radius {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                  }
                }

                // Fallback Artwork Icon
                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  visible: !coverImage.visible || root.effectiveArtUrl === ""
                  text: root.playerGlyph !== "󰝚" ? root.playerGlyph : "󰝚"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  opacity: 0.85
                }

                // Vinyl Spindle Center Hole (Visible in circular vinyl mode)
                Rectangle {
                  id: vinylCenter
                  visible: root.coverStyle === 1
                  anchors.centerIn: parent
                  width: Style.space(18)
                  height: Style.space(18)
                  radius: width / 2
                  color: root.bg
                  border.width: Style.space(2)
                  border.color: root.fg
                  opacity: 0.95

                  Rectangle {
                    anchors.centerIn: parent
                    width: Style.space(6)
                    height: Style.space(6)
                    radius: width / 2
                    color: Color.accent
                  }
                }

                // Spinning animation while playing in circular mode
                NumberAnimation on rotation {
                  id: spinAnimation
                  running: root.popupOpen && root.isPlaying && root.coverStyle === 1
                  loops: Animation.Infinite
                  from: 0
                  to: 360
                  duration: 8500
                  paused: !root.isPlaying
                }
              }

              // Click to toggle cover art style
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: {
                  root.coverStyle = (root.coverStyle + 1) % 2
                  if (root.coverStyle === 0) {
                    coverArtBox.rotation = 0
                  }
                }
              }
            }

            // Track Details Column
            Column {
              width: parent.width - coverArtWrapper.width - Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                textFormat: Text.PlainText
                id: titleText
                text: root.trackTitle
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                id: artistText
                visible: root.trackArtist !== ""
                text: root.trackArtist
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                id: albumText
                visible: root.trackAlbum !== "" && root.trackAlbum !== root.trackTitle
                text: root.trackAlbum
                color: root.subdim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          // Timeline Progress & Seek Bar (Visible only when duration is valid and known)
          Column {
            visible: root.hasKnownDuration
            width: parent.width
            spacing: Style.space(2)

            // Time labels
            Row {
              width: parent.width
              Item {
                width: parent.width
                height: curTimeText.implicitHeight

                Text {
                  textFormat: Text.PlainText
                  id: curTimeText
                  anchors.left: parent.left
                  text: MediaHelper.formatTime(root.livePosition)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  text: MediaHelper.formatTime(root.trackLength)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            // Seek Slider
            PanelSlider {
              id: seekSlider
              width: parent.width
              bar: root.bar
              minimum: 0
              maximum: Math.max(1, root.trackLength)
              value: Math.min(maximum, Math.max(0, root.livePosition))
              enabled: root.activePlayer && (root.activePlayer.canSeek !== false)

              onMoved: function(val) {
                root.isSeeking = true
                root.livePosition = val
              }

              onReleased: function(val) {
                root.seek(val)
                root.isSeeking = false
              }
            }
          }

          // Playback Controls Row
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(10)

            // Previous Track Button
            Button {
              iconText: "󰒮"
              foreground: root.fg
              iconSize: Style.font.iconLarge
              horizontalPadding: Style.space(14)
              verticalPadding: Style.space(8)
              enabled: root.activePlayer && root.activePlayer.canGoPrevious
              opacity: enabled ? 1.0 : 0.35
              tooltipText: "Previous"
              onClicked: root.previousTrack()
            }

            // Play / Pause Hero Button
            Button {
              iconText: root.isPlaying ? "󰏤" : "󰐊"
              foreground: root.fg
              iconSize: Style.font.display
              horizontalPadding: Style.space(22)
              verticalPadding: Style.space(8)
              selected: root.isPlaying
              enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
              opacity: enabled ? 1.0 : 0.4
              tooltipText: root.isPlaying ? "Pause" : "Play"
              onClicked: root.togglePlayPause()
            }

            // Next Track Button
            Button {
              iconText: "󰒭"
              foreground: root.fg
              iconSize: Style.font.iconLarge
              horizontalPadding: Style.space(14)
              verticalPadding: Style.space(8)
              enabled: root.activePlayer && root.activePlayer.canGoNext
              opacity: enabled ? 1.0 : 0.35
              tooltipText: "Next"
              onClicked: root.nextTrack()
            }
          }

          PanelSeparator {
            foreground: root.fg
          }

          // Volume Control Row
          Row {
            width: parent.width
            spacing: Style.space(8)
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: root.playerVolume === 0 ? "󰖁" : (root.playerVolume < 0.5 ? "󰕿" : "󰕾")
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              width: Style.space(20)
              horizontalAlignment: Text.AlignHCenter

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.playerVolume > 0) {
                    root.setPlayerVolume(0)
                  } else {
                    root.setPlayerVolume(1.0)
                  }
                }
              }
            }

            PanelSlider {
              id: volSlider
              width: parent.width - Style.space(70)
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              minimum: 0
              maximum: 1.0
              step: 0.02
              value: root.playerVolume
              onMoved: function(val) { root.setPlayerVolume(val) }
              onReleased: function(val) { root.setPlayerVolume(val) }
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: Math.round(root.playerVolume * 100) + "%"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              width: Style.space(34)
              horizontalAlignment: Text.AlignRight
            }
          }
        }

        // STATE 2: NO MEDIA IDLE
        Column {
          id: emptyContent
          visible: root.activePlayer === null
          width: parent.width
          spacing: Style.space(12)
          topPadding: Style.space(10)
          bottomPadding: Style.space(10)

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: "󰎆"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge * 1.2
          }

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No active media"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Start playing audio or video in your browser, MPD, Spotify, or media player to see controls here."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            width: parent.width - Style.space(24)
          }
        }
      }
    }
  }
}

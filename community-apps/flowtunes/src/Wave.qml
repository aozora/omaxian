import QtQuick

// A tune's own shape, drawn in square dots on a grid like a terminal's, which
// fill with the accent as it plays. A click on the shape plays from there.
//
// While a tune is made, the same dots are already there as a wave still
// forming: columns rising and falling like a level meter, low and loose at
// first, gathering into something like a tune as the work goes on. Once the
// tune is done, each column settles from where it is onto the tune's own
// height, so the one becomes the other. Fantasi draws its songs the same way.
Item {
    id: root
    // How loud the tune is from start to end, as levels from 0 to 1.
    property var wave: []
    // How far through it the playing is, 0 to 1.
    property real progress: 0
    property color played
    property color unplayed
    // A tune is being made.
    property bool forming: false
    signal seek(real fraction)

    // As many columns as a finished tune has: Flow::waveBars.
    readonly property int formingColumns: 96
    readonly property int columns: wave.length > 0 ? wave.length : live ? formingColumns : 0
    // The forming wave is in the frame: while the tune is made, and until it
    // has settled into its shape or faded away.
    readonly property bool live: forming || settle < 1
    // 0 while the wave forms, 1 once the columns are the tune's own shape.
    property real settle: 1
    // The forming wave fades in as the work starts, and out if it's given up.
    property real presence: 1
    // How gathered the forming wave is, 0 to 1: it grows over about as long
    // as a tune takes to make, and stays there if the tune takes longer.
    property real grown: 0
    NumberAnimation { id: growing; target: root; property: "grown"; from: 0; to: 1; duration: 40000 }
    // Seconds the wave has moved for. It stands still for anyone who has
    // asked their desktop for less motion.
    property real time: 0
    // styleHints.accessibility is Qt 6.10+; on 6.8 the wave always moves.
    readonly property bool calm: Application.styleHints.accessibility !== undefined && Application.styleHints.accessibility.motionPreference === Qt.ReducedMotion
    NumberAnimation on time {
        running: root.live && root.visible && !root.calm
        from: 0
        to: 3600
        duration: 3600000
        loops: Animation.Infinite
    }

    // How tall column `index` of `count` stands, 0 to 1, after `time`
    // seconds with `formed` of the work done. It moves like a level meter:
    // two waves travelling left to right at their own speeds, each column
    // twitching a little by itself, all of it pulsing to a beat. Barely
    // begun, that's low and even from end to end; as the work goes on it
    // grows taller and takes a tune's outline.
    function formingLevel(index, count, time, formed) {
        const x = (index + 0.5) / count
        const turn = 2 * Math.PI
        // Each column's own number, 0 to 1, the same every time.
        const own = Math.abs(Math.sin(index * 12.9898) * 43758.5453) % 1
        const slowWave = Math.sin(turn * (x * 1.6 - time * 0.42))
        const quickWave = Math.sin(turn * (x * 4.7 - time * 1.05))
        const twitch = Math.sin(time * (5 + 4 * own) + own * turn)
        const meter = 0.5 + 0.5 * (0.5 * slowWave + 0.3 * quickWave + 0.2 * twitch)
        const beat = Math.exp(-5 * ((time * 1.7) % 1))
        const ends = Math.min(1, x * 9, (1 - x) * 7)
        const passages = 0.5 + 0.5 * Math.sin(turn * (x * 2.3 - time * 0.05))
        const outline = ends * (0.65 + 0.35 * passages)
        const loose = 0.06 + 0.2 * meter
        const gathered = (0.12 + 0.88 * meter * (0.5 + 0.5 * own)) * outline
        return (loose + (gathered - loose) * formed) * (0.84 + 0.16 * beat)
    }
    // How tall a column stands now: as the forming wave has it, its own
    // height in the tune, or on the way from one to the other.
    function columnLevel(index) {
        const own = index < wave.length ? wave[index] : 0
        return settle >= 1 ? own : (1 - settle) * formingLevel(index, columns, time, grown) + settle * own
    }

    onFormingChanged: {
        if (forming) {
            vanish.stop()
            settling.stop()
            settle = 0
            presence = 0
            appear.restart()
            growing.restart()
        } else {
            // The tune and the end of the work arrive together, in no set order.
            Qt.callLater(root.conclude)
        }
    }
    Component.onCompleted: if (forming) {
        settle = 0
        growing.restart()
    }
    // The work is over: with a tune, the wave settles into its shape; with
    // none, or one whose shape couldn't be read, it fades away.
    function conclude() {
        if (forming || settle >= 1)
            return
        appear.stop()
        growing.stop()
        if (wave.length > 0)
            settling.start()
        else
            vanish.start()
    }
    NumberAnimation { id: appear; target: root; property: "presence"; to: 1; duration: 600; easing.type: Easing.OutCubic }
    ParallelAnimation {
        id: settling
        NumberAnimation { target: root; property: "settle"; to: 1; duration: 800; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "presence"; to: 1; duration: 300 }
    }
    SequentialAnimation {
        id: vanish
        NumberAnimation { target: root; property: "presence"; to: 0; duration: 400; easing.type: Easing.OutCubic }
        // Gone, so the next tune shown is in its own shape at once.
        PropertyAction { target: root; property: "settle"; value: 1 }
        PropertyAction { target: root; property: "presence"; value: 1 }
    }

    // A column of dots for each stretch of the tune, as tall as it's loud,
    // mirrored about the middle line, in the accent once played. Never
    // mirrored left to right: a tune runs that way in every language. One
    // item draws them all, and only when something has changed: every frame
    // while a wave forms, a column at a time while a tune plays, not at all
    // while it rests.
    Canvas {
        id: dots
        objectName: "waveDots"
        anchors.fill: parent
        opacity: root.presence
        // The grid: as wide as the frame, with as many rows above and below
        // the middle one as fit.
        readonly property real pitch: root.columns > 0 ? width / root.columns : 0
        readonly property int rows: pitch > 0 ? Math.max(3, Math.min(15, Math.floor((height / pitch - 1) / 2))) : 0
        // The columns the tune has played through.
        readonly property int playedColumns: Math.floor(root.progress * root.columns + 0.5)
        readonly property color playedColor: root.played
        readonly property color unplayedColor: root.unplayed
        onPlayedColumnsChanged: requestPaint()
        onPlayedColorChanged: requestPaint()
        onUnplayedColorChanged: requestPaint()
        onRowsChanged: requestPaint()
        onPitchChanged: requestPaint()
        // A forming wave is drawn some thirty times a second: dots on a grid
        // move no more smoothly for being drawn more often.
        property real drawnAt: 0
        Connections {
            target: root
            function onTimeChanged() {
                if (Math.abs(root.time - dots.drawnAt) >= 0.03) {
                    dots.drawnAt = root.time
                    dots.requestPaint()
                }
            }
            function onSettleChanged() { dots.requestPaint() }
            function onWaveChanged() { dots.requestPaint() }
        }
        function tint(alpha, color) {
            return "rgba(" + Math.round(color.r * 255) + "," + Math.round(color.g * 255) + "," + Math.round(color.b * 255) + "," + color.a * alpha + ")"
        }
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const columns = root.columns, rows = dots.rows, pitch = dots.pitch
            if (columns <= 0 || rows <= 0)
                return
            const settle = root.settle, grown = root.grown, time = root.time
            const dot = Math.max(2, Math.round(pitch * 0.62))
            const inset = (pitch - dot) / 2
            const top = (height - pitch * (rows * 2 + 1)) / 2
            // Dots of a kind are drawn together: eight shades of the accent,
            // and eight of what the rest of a tune is drawn in.
            const shades = 8
            const kinds = []
            for (let kind = 0; kind < shades * 2; ++kind)
                kinds.push([])
            // Fewer strays the further along, none once it's a tune.
            const strays = 0.1 * (1 - 0.7 * grown) * (1 - settle)
            const body = 0.4 + 0.4 * grown
            for (let c = 0; c < columns; ++c) {
                const tall = root.columnLevel(c) * rows
                const rest = c < dots.playedColumns ? 0 : shades
                const x = Math.round(c * pitch + inset)
                for (let r = -rows; r <= rows; ++r) {
                    const away = Math.abs(r)
                    // Each dot's own number, 0 to 1, the same every time.
                    const own = Math.abs(Math.sin(c * 127.1 + r * 311.7) * 43758.5453) % 1
                    // In a forming wave a column's tip fades in and out as it
                    // rises and falls, and is its brightest dot; the dots
                    // under it come in two shades, more of them the brighter
                    // one as the work goes on. In a tune a dot is there or it
                    // isn't.
                    const cover = Math.max(0, Math.min(1, tall + 0.5 - away))
                    const whole = away <= Math.round(tall) ? 1 : 0
                    let alpha = 0
                    if (settle < 1) {
                        const tip = tall - away < 1
                        alpha = cover * (tip ? 1 : body * (own < 0.4 + 0.6 * grown ? 1 : 0.45)) * (1 - settle)
                        if (cover <= 0 && own < strays)
                            alpha = (0.12 + 0.2 * (root.calm ? 0.5 : 0.5 + 0.5 * Math.sin(time * (1.5 + own * 3) + own * 40))) * (1 - settle)
                    }
                    alpha += whole * settle
                    const shade = Math.round(Math.min(1, alpha) * shades)
                    if (shade > 0)
                        kinds[rest + shade - 1].push(x, Math.round(top + (r + rows) * pitch + inset))
                }
            }
            // What isn't played yet turns from the accent to its own colour
            // as the wave settles.
            const a = dots.playedColor, b = dots.unplayedColor
            const turning = Qt.rgba(a.r + (b.r - a.r) * settle, a.g + (b.g - a.g) * settle,
                                    a.b + (b.b - a.b) * settle, a.a + (b.a - a.a) * settle)
            for (let kind = 0; kind < kinds.length; ++kind) {
                const places = kinds[kind]
                if (places.length === 0)
                    continue
                ctx.fillStyle = tint((kind % shades + 1) / shades, kind < shades ? a : turning)
                ctx.beginPath()
                for (let i = 0; i < places.length; i += 2)
                    ctx.rect(places[i], places[i + 1], dot, dot)
                ctx.fill()
            }
        }
    }
    TapHandler {
        enabled: !root.live && root.wave.length > 0
        onTapped: point => root.seek(point.position.x / root.width)
    }
}

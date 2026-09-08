import QtQuick
import qs.Commons

// One chart for every series the panel draws.
//
// Temperature, wind and precipitation differ in how the marks are shaped, not
// in anything else: they share a time axis, a value axis, an uncertainty band
// and a hover readout. Keeping them in one component means the axis maths is
// written and corrected once, and the three views stay visually consistent
// because they are literally the same drawing code.
//
// Each point is `{ time, value, min, max }`. `min`/`max` are the 10-90 %
// forecast band; where they are absent the mark is drawn without a band rather
// than with a zero-width one, so "no uncertainty published" reads differently
// from "uncertainty is nil".
//
// Marks are painted on a Canvas; tick labels are real Text items so they pick
// up the theme font and stay crisp. Only paths go through the Canvas, and it
// repaints on data or geometry change, never per frame.
Item {
  id: root

  // "line" draws a stroked curve over a filled band — temperature, wind.
  // "bars" draws a column per point with a whisker for the band — precipitation.
  property string mode: "line"

  property var points: []
  // Optional second curve on the same axes, e.g. gusts under wind speed.
  property var secondary: []
  property string secondaryLabel: ""
  property string primaryLabel: ""

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  property string unit: ""
  property int decimals: 0
  // Never let the value axis collapse onto a single line: a flat series still
  // needs vertical room or it is drawn on top of the axis and reads as absent.
  property real minimumSpan: 1.0
  // Precipitation and wind are only meaningful from zero up; temperature is not.
  property bool baselineAtZero: false
  property int hourLabelStep: 3

  readonly property int axisWidth: Style.space(34)
  readonly property int axisHeight: Style.space(16)
  readonly property int plotLeft: axisWidth
  readonly property int plotTop: Style.space(6)
  readonly property real plotWidth: Math.max(1, width - plotLeft - Style.space(6))
  readonly property real plotHeight: Math.max(1, height - plotTop - axisHeight)

  readonly property bool hasData: points.length > 0

  implicitHeight: Style.space(120)

  // ------------------------------------------------------------- domain

  // Time domain comes from the primary series alone. The secondary curve is
  // drawn on the same window even if it runs longer, so the two are always
  // read against the same hours.
  readonly property real timeFrom: hasData ? points[0].time : 0
  readonly property real timeTo: hasData ? points[points.length - 1].time : 1

  readonly property var valueDomain: {
    var low = baselineAtZero ? 0 : Number.POSITIVE_INFINITY
    var high = Number.NEGATIVE_INFINITY

    function consider(list) {
      for (var i = 0; i < list.length; i++) {
        var p = list[i]
        var candidates = [p.value, p.min, p.max]
        for (var c = 0; c < candidates.length; c++) {
          var v = candidates[c]
          if (v === null || v === undefined || !isFinite(v)) continue
          if (v < low) low = v
          if (v > high) high = v
        }
      }
    }
    consider(points)
    consider(secondary)

    if (!isFinite(low) || !isFinite(high)) return { low: 0, high: 1 }
    if (high - low < root.minimumSpan) {
      var pad = (root.minimumSpan - (high - low)) / 2
      low -= pad
      high += pad
      if (root.baselineAtZero && low < 0) { high -= low; low = 0 }
    }
    // Headroom so the peak of the curve is not clipped by the plot edge.
    var margin = (high - low) * 0.08
    return { low: root.baselineAtZero ? Math.max(0, low - (low > 0 ? margin : 0)) : low - margin, high: high + margin }
  }

  function xFor(time) {
    var span = timeTo - timeFrom
    if (span <= 0) return plotLeft + plotWidth / 2
    return plotLeft + (time - timeFrom) / span * plotWidth
  }

  function yFor(value) {
    var span = valueDomain.high - valueDomain.low
    if (span <= 0) return plotTop + plotHeight / 2
    return plotTop + (valueDomain.high - value) / span * plotHeight
  }

  // ------------------------------------------------------------- hover

  // Index of the point under the pointer, or -1. Driving the readout off an
  // index rather than off pixel coordinates keeps the label snapped to real
  // data instead of interpolating between samples.
  property int hoverIndex: -1
  readonly property var hoverPoint: (hoverIndex >= 0 && hoverIndex < points.length) ? points[hoverIndex] : null
  readonly property var hoverSecondary: (hoverIndex >= 0 && hoverIndex < secondary.length) ? secondary[hoverIndex] : null

  function indexNear(px) {
    if (!hasData) return -1
    var best = -1
    var bestDistance = Number.POSITIVE_INFINITY
    for (var i = 0; i < points.length; i++) {
      var distance = Math.abs(xFor(points[i].time) - px)
      if (distance < bestDistance) {
        bestDistance = distance
        best = i
      }
    }
    return bestDistance <= plotWidth ? best : -1
  }

  onPointsChanged: { hoverIndex = -1; canvas.requestPaint() }
  onSecondaryChanged: canvas.requestPaint()
  onWidthChanged: canvas.requestPaint()
  onHeightChanged: canvas.requestPaint()
  onForegroundChanged: canvas.requestPaint()
  onAccentChanged: canvas.requestPaint()

  // ------------------------------------------------------------- marks

  Canvas {
    id: canvas
    anchors.fill: parent
    renderStrategy: Canvas.Cooperative
    antialiasing: true

    function rgba(color, alpha) {
      return Qt.rgba(color.r, color.g, color.b, alpha)
    }

    // Points whose value is null break the curve. Splitting into runs first
    // means a gap is drawn as a gap rather than as a straight line across the
    // missing hours.
    function runsOf(list) {
      var runs = []
      var run = []
      for (var i = 0; i < list.length; i++) {
        if (list[i].value === null || list[i].value === undefined) {
          if (run.length > 0) { runs.push(run); run = [] }
          continue
        }
        run.push(list[i])
      }
      if (run.length > 0) runs.push(run)
      return runs
    }

    function strokeRuns(ctx, list, color, width, dashed) {
      var runs = runsOf(list)
      ctx.strokeStyle = color
      ctx.lineWidth = width
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      if (dashed && ctx.setLineDash) ctx.setLineDash([Style.space(3), Style.space(3)])
      for (var r = 0; r < runs.length; r++) {
        var run = runs[r]
        ctx.beginPath()
        for (var i = 0; i < run.length; i++) {
          var x = root.xFor(run[i].time)
          var y = root.yFor(run[i].value)
          if (i === 0) ctx.moveTo(x, y)
          else ctx.lineTo(x, y)
        }
        // A single surviving sample has no line to draw; mark it so the value
        // is still visible.
        if (run.length === 1) ctx.arc(root.xFor(run[0].time), root.yFor(run[0].value), width, 0, Math.PI * 2)
        ctx.stroke()
      }
      if (dashed && ctx.setLineDash) ctx.setLineDash([])
    }

    function fillBand(ctx, list, color) {
      var runs = []
      var run = []
      for (var i = 0; i < list.length; i++) {
        var p = list[i]
        var hasBand = p.min !== null && p.min !== undefined && p.max !== null && p.max !== undefined
        if (!hasBand) {
          if (run.length > 1) runs.push(run)
          run = []
          continue
        }
        run.push(p)
      }
      if (run.length > 1) runs.push(run)

      ctx.fillStyle = color
      for (var r = 0; r < runs.length; r++) {
        var segment = runs[r]
        ctx.beginPath()
        for (var a = 0; a < segment.length; a++) {
          var x = root.xFor(segment[a].time)
          var y = root.yFor(segment[a].max)
          if (a === 0) ctx.moveTo(x, y)
          else ctx.lineTo(x, y)
        }
        for (var b = segment.length - 1; b >= 0; b--) {
          ctx.lineTo(root.xFor(segment[b].time), root.yFor(segment[b].min))
        }
        ctx.closePath()
        ctx.fill()
      }
    }

    function drawBars(ctx) {
      var count = root.points.length
      if (count === 0) return
      // Leave a hairline between columns so adjacent hours stay countable.
      var slot = root.plotWidth / count
      var barWidth = Math.max(1, Math.min(Style.space(14), slot - Style.space(2)))
      var zeroY = root.yFor(Math.max(root.valueDomain.low, 0))

      for (var i = 0; i < count; i++) {
        var p = root.points[i]
        if (p.value === null || p.value === undefined) continue
        var x = root.xFor(p.time) - barWidth / 2
        var y = root.yFor(p.value)
        var height = Math.max(p.value > 0 ? 1 : 0, zeroY - y)

        ctx.fillStyle = rgba(root.accent, 0.55)
        ctx.fillRect(x, y, barWidth, height)

        // The 90 % end of the band, drawn as a whisker above the bar: the
        // difference between "1 mm expected" and "1 mm expected, 6 mm possible"
        // is the whole point of showing precipitation at all.
        if (p.max !== null && p.max !== undefined && p.max > p.value) {
          var topY = root.yFor(p.max)
          ctx.strokeStyle = rgba(root.accent, 0.9)
          ctx.lineWidth = Math.max(1, Style.space(1))
          ctx.beginPath()
          ctx.moveTo(x + barWidth / 2, y)
          ctx.lineTo(x + barWidth / 2, topY)
          ctx.moveTo(x + barWidth * 0.25, topY)
          ctx.lineTo(x + barWidth * 0.75, topY)
          ctx.stroke()
        }
      }
    }

    // Local midnights inside the plotted window, as vertical rules.
    function drawMidnights(ctx) {
      if (root.timeTo - root.timeFrom < 26 * 3600000) return
      var cursor = new Date(root.timeFrom)
      cursor.setHours(24, 0, 0, 0)
      ctx.strokeStyle = rgba(root.foreground, 0.22)
      ctx.lineWidth = 1
      while (cursor.getTime() < root.timeTo) {
        var x = Math.round(root.xFor(cursor.getTime())) + 0.5
        ctx.beginPath()
        ctx.moveTo(x, root.plotTop)
        ctx.lineTo(x, root.plotTop + root.plotHeight)
        ctx.stroke()
        cursor.setHours(cursor.getHours() + 24)
      }
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      if (!root.hasData) return

      // Baseline, so a curve sitting near zero is legible against it.
      var zeroValue = Math.max(root.valueDomain.low, Math.min(root.valueDomain.high, 0))
      ctx.strokeStyle = rgba(root.foreground, 0.15)
      ctx.lineWidth = 1
      ctx.beginPath()
      ctx.moveTo(root.plotLeft, root.yFor(zeroValue) + 0.5)
      ctx.lineTo(root.plotLeft + root.plotWidth, root.yFor(zeroValue) + 0.5)
      ctx.stroke()

      // Midnight rules. On a chart spanning more than a day the hour labels
      // repeat, and "6h" twice with nothing between them is ambiguous; these
      // say where one day ends.
      drawMidnights(ctx)

      if (root.mode === "bars") {
        drawBars(ctx)
      } else {
        // Only the primary series gets a filled band. Two translucent bands
        // overlapping in a popup this narrow read as one grey mass and bury
        // both curves; the secondary keeps its dashed line, which is what it
        // is there to show.
        fillBand(ctx, root.points, rgba(root.accent, 0.18))
        if (root.secondary.length > 0)
          strokeRuns(ctx, root.secondary, rgba(root.foreground, 0.7), Math.max(1, Style.space(1)), true)
        strokeRuns(ctx, root.points, root.accent, Math.max(1, Style.space(2)), false)
      }

      if (root.hoverIndex >= 0 && root.hoverPoint) {
        var hx = root.xFor(root.hoverPoint.time)
        ctx.strokeStyle = rgba(root.foreground, 0.45)
        ctx.lineWidth = 1
        ctx.beginPath()
        ctx.moveTo(hx + 0.5, root.plotTop)
        ctx.lineTo(hx + 0.5, root.plotTop + root.plotHeight)
        ctx.stroke()
      }
    }
  }

  onHoverIndexChanged: canvas.requestPaint()

  // ------------------------------------------------------------- axes

  // Two value labels only. A popup this size cannot carry a full gridline
  // ladder without the numbers crowding the curve they annotate.
  Text {
    x: 0
    y: root.plotTop - height / 2
    width: root.axisWidth - Style.space(4)
    horizontalAlignment: Text.AlignRight
    text: root.hasData ? root.valueDomain.high.toFixed(root.decimals) : ""
    color: Qt.darker(root.foreground, 1.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    textFormat: Text.PlainText
  }

  Text {
    x: 0
    y: root.plotTop + root.plotHeight - height / 2
    width: root.axisWidth - Style.space(4)
    horizontalAlignment: Text.AlignRight
    text: root.hasData ? root.valueDomain.low.toFixed(root.decimals) : ""
    color: Qt.darker(root.foreground, 1.6)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    textFormat: Text.PlainText
  }

  Repeater {
    model: root.hasData ? root.points : []

    Text {
      required property var modelData
      required property int index

      readonly property var stamp: new Date(modelData.time)
      // Label whole hours on the requested step, and always the first sample,
      // so the axis reads from a known starting hour.
      visible: index === 0 || (stamp.getHours() % root.hourLabelStep === 0 && stamp.getMinutes() === 0)
      x: Math.min(root.width - width, Math.max(0, root.xFor(modelData.time) - width / 2))
      y: root.plotTop + root.plotHeight + Style.space(3)
      text: stamp.getHours() + "h"
      color: Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
    }
  }

  // ------------------------------------------------------------- readout

  Rectangle {
    id: readout
    visible: root.hoverPoint !== null
    radius: Style.cornerRadius
    color: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.92)
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
    width: readoutText.implicitWidth + Style.space(12)
    height: readoutText.implicitHeight + Style.space(6)
    // Flip to the left of the cursor when the label would otherwise overflow
    // the plot, so the value stays readable at the end of the series.
    x: {
      if (!root.hoverPoint) return 0
      var anchor = root.xFor(root.hoverPoint.time)
      return Math.max(root.plotLeft, Math.min(anchor + Style.space(8), root.width - width))
    }
    y: root.plotTop

    Text {
      id: readoutText
      anchors.centerIn: parent
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      textFormat: Text.PlainText
      text: {
        if (!root.hoverPoint) return ""
        var stamp = new Date(root.hoverPoint.time)
        var hour = (stamp.getHours() < 10 ? "0" : "") + stamp.getHours() + ":"
          + (stamp.getMinutes() < 10 ? "0" : "") + stamp.getMinutes()
        var line = hour + "  " + root.hoverPoint.value.toFixed(root.decimals) + " " + root.unit
        if (root.hoverPoint.min !== null && root.hoverPoint.min !== undefined
            && root.hoverPoint.max !== null && root.hoverPoint.max !== undefined
            && root.hoverPoint.max > root.hoverPoint.min) {
          line += " (" + root.hoverPoint.min.toFixed(root.decimals)
            + "–" + root.hoverPoint.max.toFixed(root.decimals) + ")"
        }
        if (root.hoverSecondary && root.hoverSecondary.value !== null
            && root.hoverSecondary.value !== undefined && root.secondaryLabel !== "") {
          line += "   " + root.secondaryLabel + " " + root.hoverSecondary.value.toFixed(root.decimals)
        }
        return line
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton
    onPositionChanged: function(mouse) { root.hoverIndex = root.indexNear(mouse.x) }
    onExited: root.hoverIndex = -1
  }
}

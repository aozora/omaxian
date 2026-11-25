import QtQuick

// The pattern on the back of a card: hatching, a lattice, halftone dots, or
// rings, by series. Painted once and again only when its look changes.
Canvas {
  id: back
  property int series: 0
  property color fill: "black"
  property color line: "white"
  property real unit: 1
  // A back that is hidden waits until it shows to be drawn; a canvas already
  // redraws itself when it changes size.
  onSeriesChanged: if (visible) requestPaint()
  onFillChanged: if (visible) requestPaint()
  onLineChanged: if (visible) requestPaint()
  onVisibleChanged: if (visible) requestPaint()
  onPaint: {
    const ctx = getContext("2d")
    ctx.reset()
    ctx.fillStyle = fill
    ctx.fillRect(0, 0, width, height)
    ctx.strokeStyle = line
    ctx.fillStyle = line
    ctx.lineWidth = 1
    ctx.beginPath()
    if (series === 0 || series === 1) {
      const step = (series === 0 ? 7 : 9) * unit
      for (let offset = -height; offset < width; offset += step) {
        ctx.moveTo(offset, height)
        ctx.lineTo(offset + height, 0)
        if (series === 1) {
          ctx.moveTo(offset, 0)
          ctx.lineTo(offset + height, height)
        }
      }
      ctx.stroke()
    } else if (series === 2) {
      const step = 13 * unit
      for (let y = step / 2; y < height + step; y += step)
        for (let x = step / 2; x < width + step; x += step) {
          ctx.moveTo(x + 3.2 * unit, y)
          ctx.arc(x, y, 3.2 * unit, 0, Math.PI * 2)
        }
      ctx.fill()
    } else {
      const reach = Math.hypot(width, height) / 2
      for (let radius = 5 * unit; radius < reach; radius += 8 * unit) {
        ctx.moveTo(width / 2 + radius, height / 2)
        ctx.arc(width / 2, height / 2, radius, 0, Math.PI * 2)
      }
      ctx.stroke()
    }
  }
}

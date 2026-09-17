// Pure helpers for Running Cat: /proc/stat parsing, the CPU-to-speed curve,
// the frame ticker, and sprite-directory listings.
//
// Kept free of QML imports so tests/model.test.mjs can load it in a Node vm
// the same way the import in BarWidget.qml does.

// ------------------------------------------------------------------ numbers

function toNumber(value, fallback) {
  var n = Number(value)
  if (isFinite(n)) return n
  var f = Number(fallback)
  return isFinite(f) ? f : 0
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// shell.json settings arrive as untyped JSON: coerce, reject non-finite
// values, clamp, and round before anything depends on them.
function clampInt(value, fallback, min, max) {
  var n = Number(value)
  if (!isFinite(n)) n = Number(fallback)
  if (!isFinite(n)) n = min
  return clamp(Math.round(n), min, max)
}

// ------------------------------------------------------------------ /proc/stat

// The aggregate line of /proc/stat holds cumulative jiffies since boot:
// cpu user nice system idle iowait irq softirq steal guest guest_nice
function parseCpuJiffies(raw) {
  var text = String(raw || "")
  var end = text.indexOf("\n")
  var line = end === -1 ? text : text.substring(0, end)
  var parts = line.replace(/\s+/g, " ").split(" ")
  if (parts.length < 5 || parts[0] !== "cpu") return null

  var total = 0
  // Fields past `steal` are already counted inside user/nice, so stop at 8.
  for (var i = 1; i < parts.length && i <= 8; i++) total += toNumber(parts[i])
  // iowait is time with nothing to run, so it belongs with idle rather than
  // being charged to a process — this matches what top and btop report.
  var idle = toNumber(parts[4]) + toNumber(parts[5])
  return { total: total, idle: idle }
}

// Usage is a ratio of jiffie deltas, not of wall-clock time, so an uneven
// sampling interval cannot skew it. Returns -1 until two samples exist.
function cpuUsage(previous, current) {
  if (!previous || !current) return -1
  var totalDelta = current.total - previous.total
  var idleDelta = current.idle - previous.idle
  if (totalDelta <= 0) return -1
  return clamp(100 * (1 - idleDelta / totalDelta), 0, 100)
}

// A custom CPU command prints a percentage; take the first number in its
// output so "8%", "8.4" and "CPU: 8 %" all work. Returns -1 when there is none.
function parsePercentText(raw) {
  var match = String(raw || "").match(/-?\d+(?:\.\d+)?/)
  if (!match) return -1
  var value = Number(match[0])
  if (!isFinite(value)) return -1
  return clamp(value, 0, 100)
}

// -------------------------------------------------------------------- speed

// Duration of one full animation cycle for CPU utilization in [0, 100].
// Ports RunCat's f(x) = busy + (idle - busy) * (1 - x)^k, where x is the
// utilization as a fraction. At 0% the cat trots, at 100% it sprints.
function animationCycleMs(utilization, busyMs, idleMs, curve) {
  var x = clamp(toNumber(utilization, 0), 0, 100) / 100
  var busy = Math.max(1, toNumber(busyMs, 250))
  var idle = Math.max(busy, toNumber(idleMs, 1100))
  var k = Math.max(0.05, toNumber(curve, 2))
  return busy + (idle - busy) * Math.pow(1 - x, k)
}

// ------------------------------------------------------------------- ticker

// Exponential moving average half-life guard: a frame gap longer than the
// expected frame duration (and never under this) counts as a stall — a
// suspend, a clock jump — and does not advance the animation.
var MAX_FRAME_DELTA_MS = 250

// Advances a phase through the frames of an animation whose full-cycle
// duration eases toward the latest CPU reading, the way RunCat does it.
// advanceTo(nowMs, frames) returns the frame to show and how long to wait
// for the next boundary, so the widget can re-arm a Timer per frame.
function createTicker(tauMs) {
  var tau = Math.max(0, toNumber(tauMs, 500))
  var targetMs = 0
  var smoothedMs = 0
  var phase = 0
  var lastMs = NaN

  return {
    // A new CPU reading; immediate skips the smoothing for this step.
    setTarget: function(durationMs, immediate) {
      var value = Number(durationMs)
      if (!isFinite(value) || value <= 0) return
      targetMs = value
      if (immediate === true || smoothedMs <= 0) smoothedMs = value
    },

    reset: function() {
      smoothedMs = 0
      phase = 0
      lastMs = NaN
    },

    frameIndex: function(frames) {
      var count = Math.max(0, Math.floor(toNumber(frames, 0)))
      if (count <= 0) return 0
      return Math.max(0, Math.floor(phase * count) % count)
    },

    advanceTo: function(nowMs, frames) {
      var count = Math.max(1, Math.floor(toNumber(frames, 1)))
      var now = toNumber(nowMs, 0)
      var dt = now - lastMs
      lastMs = now

      // A gap counts as a stall only when it far exceeds both the expected
      // frame duration and MAX_FRAME_DELTA_MS (few sprites -> long frames).
      var stallMs = Math.max(MAX_FRAME_DELTA_MS, smoothedMs / count)
      if (isFinite(dt) && dt > 0 && dt <= stallMs && smoothedMs > 0) {
        // Frame-rate-independent lerp: alpha = 1 - e^(-dt / tau).
        var alpha = tau > 0 ? 1 - Math.exp(-dt / tau) : 1
        smoothedMs += alpha * (targetMs - smoothedMs)
        phase = (phase + dt / smoothedMs) % 1
      }

      var index = Math.max(0, Math.floor(phase * count) % count)
      var nextPhase = (Math.floor(phase * count) + 1) / count
      var delay = smoothedMs > 0
        ? Math.max(1, Math.ceil((nextPhase - phase) * smoothedMs))
        : MAX_FRAME_DELTA_MS
      return { index: index, nextDelayMs: delay, cycleMs: smoothedMs }
    }
  }
}

// ------------------------------------------------------------------- sprites

// Sort sprite directory entries by their leading number so 2.svg precedes
// 10.svg; names without a number keep a stable lexicographic order after
// the numbered ones.
function frameOrder(name) {
  var match = String(name).match(/^(\d+)/)
  if (!match) return Number.MAX_SAFE_INTEGER
  return parseInt(match[1], 10)
}

function pathToUrl(path) {
  var parts = String(path || "").replace(/\/+$/, "").split("/")
  for (var i = 0; i < parts.length; i++) parts[i] = encodeURIComponent(parts[i])
  return parts.join("/")
}

// `ls -1 <dir>` output -> frame source URLs, filtered to svg/png and sorted.
function parseFrameList(raw, dir) {
  var base = String(dir || "").trim()
  if (base === "") return []

  var lines = String(raw || "").split("\n")
  var names = []
  for (var i = 0; i < lines.length; i++) {
    var name = lines[i].trim()
    if (name === "" || name.charAt(0) === ".") continue
    if (!/\.(svg|png)$/i.test(name)) continue
    if (name.indexOf("/") !== -1) continue
    names.push(name)
  }

  names.sort(function(a, b) {
    var byOrder = frameOrder(a) - frameOrder(b)
    if (byOrder !== 0) return byOrder
    return a < b ? -1 : (a > b ? 1 : 0)
  })

  var urls = []
  for (var j = 0; j < names.length; j++) urls.push("file://" + pathToUrl(base + "/" + names[j]))
  return urls
}

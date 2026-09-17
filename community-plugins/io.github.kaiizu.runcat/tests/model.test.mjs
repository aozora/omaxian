// Runs Model.js in a Node vm the same way the QML side imports it: as a
// plain script whose top-level functions become the module's API.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import vm from "node:vm"

const source = readFileSync(new URL("../Model.js", import.meta.url), "utf8")
const sandbox = {}
vm.createContext(sandbox)
vm.runInContext(source, sandbox)
const Model = sandbox

// ------------------------------------------------------------------ numbers

test("clampInt coerces, clamps and rounds", () => {
  assert.equal(Model.clampInt("12", 5, 0, 100), 12)
  assert.equal(Model.clampInt("nope", 5, 0, 100), 5)
  assert.equal(Model.clampInt(undefined, 5, 1, 4), 4)
  assert.equal(Model.clampInt(-2, 5, 1, 4), 1)
  assert.equal(Model.clampInt(3.6, 5, 0, 10), 4)
})

// ------------------------------------------------------------------ /proc/stat

test("parseCpuJiffies reads the aggregate line", () => {
  const sample = "cpu  100 20 30 400 50 5 5 0 0 0\ncpu0 50 10 15 200 25 2 3 0 0 0\nintr 12345\n"
  const parsed = Model.parseCpuJiffies(sample)
  // total = user..steal = 100+20+30+400+50+5+5+0
  assert.equal(parsed.total, 610)
  assert.equal(parsed.idle, 450) // idle + iowait
})

test("parseCpuJiffies tolerates spacing and rejects junk", () => {
  assert.equal(Model.parseCpuJiffies("cpu\t5\t5\t5\t85").idle, 85)
  assert.equal(Model.parseCpuJiffies("intr 1 2 3"), null)
  assert.equal(Model.parseCpuJiffies(""), null)
  assert.equal(Model.parseCpuJiffies(undefined), null)
})

test("cpuUsage is the ratio of jiffie deltas", () => {
  const previous = { total: 1000, idle: 800 }
  // 100 total jiffies passed, 25 of them idle -> 75% busy
  assert.equal(Model.cpuUsage(previous, { total: 1100, idle: 825 }), 75)
})

test("cpuUsage waits for two samples and ignores a stalled counter", () => {
  assert.equal(Model.cpuUsage(null, { total: 100, idle: 50 }), -1)
  assert.equal(Model.cpuUsage({ total: 100, idle: 50 }, { total: 100, idle: 50 }), -1)
})

test("parsePercentText takes the first number it finds", () => {
  assert.equal(Model.parsePercentText("8%"), 8)
  assert.equal(Model.parsePercentText("CPU: 42.5 %\n"), 42.5)
  assert.equal(Model.parsePercentText("all good"), -1)
  assert.equal(Model.parsePercentText("150"), 100)
})

// -------------------------------------------------------------------- speed

test("animationCycleMs eases between the two ends", () => {
  assert.equal(Model.animationCycleMs(0, 250, 1100, 2), 1100)
  assert.equal(Model.animationCycleMs(100, 250, 1100, 2), 250)
  // f(x) = 250 + 850 * (1 - x)^2 at x = 0.5
  assert.equal(Model.animationCycleMs(50, 250, 1100, 2), 250 + 850 * 0.25)
})

test("animationCycleMs is monotonic in load and never faster than busy", () => {
  let last = Infinity
  for (let cpu = 0; cpu <= 100; cpu += 10) {
    const value = Model.animationCycleMs(cpu, 250, 1100, 2)
    assert.ok(value <= last, `cycle must not rise with load (cpu ${cpu})`)
    last = value
  }
  // A misconfigured idle below busy collapses to busy instead of inverting.
  assert.equal(Model.animationCycleMs(0, 500, 100, 2), 500)
})

// ------------------------------------------------------------------- ticker

test("ticker advances one frame per boundary at the target cycle", () => {
  const ticker = Model.createTicker(500)
  ticker.setTarget(1000, true) // 5 frames -> a boundary every 200ms

  let now = 0
  let result = ticker.advanceTo(now, 5)
  assert.equal(result.index, 0)

  const seen = [0]
  for (let i = 0; i < 4; i++) {
    now += result.nextDelayMs
    result = ticker.advanceTo(now, 5)
    seen.push(result.index)
  }
  assert.deepEqual(seen, [0, 1, 2, 3, 4])

  now += result.nextDelayMs
  result = ticker.advanceTo(now, 5)
  assert.equal(result.index, 0, "a full cycle wraps back to the first frame")
  assert.equal(now, 1000)
})

test("ticker eases toward a new target when smoothing is on", () => {
  const ticker = Model.createTicker(500)
  ticker.setTarget(100, true)
  ticker.advanceTo(0, 4)

  ticker.setTarget(1100) // not immediate: eased in
  let now = 0
  let result = ticker.advanceTo(0, 4)
  for (let i = 0; i < 50; i++) {
    now += result.nextDelayMs
    result = ticker.advanceTo(now, 4)
  }
  assert.ok(result.cycleMs > 1000, `expected eased approach, got ${result.cycleMs}`)
  assert.ok(result.cycleMs <= 1100)
})

test("ticker treats a long gap as a stall and does not jump frames", () => {
  const ticker = Model.createTicker(500)
  ticker.setTarget(1000, true)
  ticker.advanceTo(0, 5)
  const afterStall = ticker.advanceTo(60000, 5)
  assert.equal(afterStall.index, 0)
  assert.ok(afterStall.nextDelayMs > 0)
})

// ------------------------------------------------------------------ sprites

test("parseFrameList keeps images, sorts by leading number, encodes paths", () => {
  const listing = "10.svg\n2.png\nnotes.txt\n.sprite.svg\n1.svg\nsub/3.svg\n"
  // Spread into a host-realm array: the vm's Array prototype differs.
  const frames = [...Model.parseFrameList(listing, "/tmp/my cats")]
  assert.deepEqual(frames, [
    "file:///tmp/my%20cats/1.svg",
    "file:///tmp/my%20cats/2.png",
    "file:///tmp/my%20cats/10.svg",
  ])
  assert.deepEqual([...Model.parseFrameList("anything", "")], [])
})

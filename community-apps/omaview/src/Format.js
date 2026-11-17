.pragma library

// 1:02:03 or 02:03, in the digits every player uses.
function clock(ms) {
    const total = Math.max(0, Math.floor(ms / 1000))
    const h = Math.floor(total / 3600), m = Math.floor(total / 60) % 60, s = total % 60
    const pad = n => (n < 10 ? "0" : "") + n
    return h > 0 ? h + ":" + pad(m) + ":" + pad(s) : pad(m) + ":" + pad(s)
}

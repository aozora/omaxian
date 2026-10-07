.pragma library
// The scalar subset Omarchy's theme files and omastorm's config.toml use:
// sections, quoted strings, numbers, and true/false, keyed as
// "section.key". Other TOML values are ignored; this is not a general
// TOML parser.
function parse(raw) {
    var result = {}, section = "";
    for (var line of String(raw).split("\n")) {
        var heading = line.match(/^\s*\[([^\]]+)\]\s*(?:#.*)?$/);
        if (heading) { section = heading[1]; continue; }
        var kv = line.match(/^\s*([\w-]+)\s*=\s*(?:"([^"\\]*)"|'([^']*)'|(-?\d+(?:\.\d+)?)|(true|false))\s*(?:#.*)?$/);
        if (!kv) continue;
        var value = kv[2] !== undefined ? kv[2] : kv[3] !== undefined ? kv[3] : kv[4] !== undefined ? Number(kv[4]) : kv[5] === "true";
        result[(section ? section + "." : "") + kv[1]] = value;
    }
    return result;
}

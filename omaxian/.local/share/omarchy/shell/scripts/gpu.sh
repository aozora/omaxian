#!/usr/bin/env bash
# GPU usage one-shot for omaxian.sysstats.
# Prefer: nvidia-smi (NVIDIA) → radeontop (AMD) → intel_gpu_top (Intel).
# Prints "󰓅 NN%" or "󰓅 N/A". Never fails the bar poll.
set -u

ICON="󰓅"

na() {
	echo "${ICON} N/A"
	exit 0
}

emit() {
	local pct="$1"
	[[ -n "$pct" ]] || na
	# Strip decimals / whitespace; clamp display to 0–100.
	pct="${pct%%.*}"
	pct="${pct//[^0-9]/}"
	[[ -n "$pct" ]] || na
	(( pct > 100 )) && pct=100
	printf '%s %02d%%\n' "$ICON" "$pct"
	exit 0
}

# PCI vendor id present under a real DRM card (skip non-card nodes).
has_vendor() {
	local want="$1" f
	for f in /sys/class/drm/card[0-9]*/device/vendor; do
		[[ -r "$f" ]] || continue
		[[ "$(<"$f")" == "$want" ]] && return 0
	done
	return 1
}

# --- NVIDIA (proprietary) -------------------------------------------------
if command -v nvidia-smi >/dev/null 2>&1; then
	# First GPU; ignore errors from missing driver / container.
	line="$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
	if [[ -n "$line" && "$line" != "[N/A]" && "$line" != "N/A" ]]; then
		emit "$line"
	fi
fi

# --- AMD ------------------------------------------------------------------
if has_vendor "0x1002" && command -v radeontop >/dev/null 2>&1; then
	line="$(radeontop -l 1 -d - 2>/dev/null | awk '/gpu/{print; exit}' || true)"
	pct="$(echo "$line" | grep -oE 'gpu[[:space:]]+[0-9.]+%' | awk '{print $2}' | tr -d '%' || true)"
	[[ -n "$pct" ]] && emit "$pct"
fi

# --- Intel ----------------------------------------------------------------
# intel-gpu-tools: one JSON sample (~100ms). Engine busy% → max across engines.
if has_vendor "0x8086" && command -v intel_gpu_top >/dev/null 2>&1; then
	json="$(timeout 2s intel_gpu_top -J -s 100 -o - 2>/dev/null | head -c 65536 || true)"
	if [[ -n "$json" ]]; then
		pct="$(
			GPU_JSON="$json" python3 - <<'PY' 2>/dev/null || true
import json, os, re, sys
raw = os.environ.get("GPU_JSON", "")
# intel_gpu_top -J may emit one object or a stream; take the first {...} block.
m = re.search(r"\{.*\}", raw, re.S)
if not m:
    sys.exit(1)
try:
    data = json.loads(m.group(0))
except json.JSONDecodeError:
    sys.exit(1)
engines = data.get("engines")
busy = []
if isinstance(engines, list):
    for e in engines:
        if isinstance(e, dict) and "busy" in e:
            try: busy.append(float(e["busy"]))
            except (TypeError, ValueError): pass
elif isinstance(engines, dict):
    for e in engines.values():
        if isinstance(e, dict) and "busy" in e:
            try: busy.append(float(e["busy"]))
            except (TypeError, ValueError): pass
if not busy:
    sys.exit(1)
print(max(busy))
PY
		)"
		[[ -n "$pct" ]] && emit "$pct"
	fi
fi

na

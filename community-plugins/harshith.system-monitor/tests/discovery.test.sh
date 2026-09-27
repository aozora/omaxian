#!/usr/bin/env bash
# Exercises GPU discovery against fixture sysfs trees, so the vendor matrix is
# verified rather than assumed on machines that only have one kind of card.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/discover-sensors.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failures=0

card() { # <tree> <card> [busy] [vram_total] [temp]
  local dir="$work/$1/$2/device"
  mkdir -p "$dir"
  [[ -n "${3:-}" ]] && printf '%s\n' "$3" >"$dir/gpu_busy_percent"
  if [[ -n "${4:-}" ]]; then
    printf '%s\n' "$4" >"$dir/mem_info_vram_total"
    printf '%s\n' "1000" >"$dir/mem_info_vram_used"
  fi
  if [[ -n "${5:-}" ]]; then
    mkdir -p "$dir/hwmon/hwmon0"
    printf '%s\n' "$5" >"$dir/hwmon/hwmon0/temp1_input"
  fi
  return 0
}

check() { # <name> <tree> <key> <expected-substring-or-EMPTY>
  local out actual
  out="$(OMARCHY_SYSMON_DRM_ROOT="$work/$2" bash "$script" | grep "^$3	" || true)"
  actual="${out#*	}"
  if [[ "$4" == "EMPTY" ]]; then
    if [[ -z "$actual" ]]; then echo "  ok   $1: $3 absent"; else
      echo "  FAIL $1: $3 expected absent, got '$actual'"; failures=$((failures+1)); fi
  elif [[ "$actual" == *"$4"* ]]; then
    echo "  ok   $1: $3 -> $actual"
  else
    echo "  FAIL $1: $3 expected '*$4*', got '$actual'"; failures=$((failures+1))
  fi
}

echo "AMD hybrid (discrete + integrated) - picks the card with more VRAM"
card amd card0 "100" "536870912"   "35000"
card amd card1 "6"   "17095983104" "28000"
check "amd" amd gpu_busy  "card1"
check "amd" amd gpu_temp  "card1"
check "amd" amd gpu_vram_total "card1"

echo "Intel Arc (no busy counter anywhere) - still reports temperature"
card intel card0 "" "" "40000"
card intel card1 "" "" "52000"
check "intel" intel gpu_busy EMPTY
check "intel" intel gpu_temp "card"
check "intel" intel gpu_vram_total EMPTY

echo "Intel xe (package temp is temp2_input, there is no temp1) - still found"
mkdir -p "$work/xe/card0/device/hwmon/hwmon0"
printf '48000\n' >"$work/xe/card0/device/hwmon/hwmon0/temp2_input"
check "xe" xe gpu_busy EMPTY
check "xe" xe gpu_temp "temp2_input"

echo "Card with both temp1 and temp2 - temp1 wins (amdgpu edge sensor over the rest)"
mkdir -p "$work/temp-precedence/card0/device/hwmon/hwmon0"
printf '30000\n' >"$work/temp-precedence/card0/device/hwmon/hwmon0/temp1_input"
printf '55000\n' >"$work/temp-precedence/card0/device/hwmon/hwmon0/temp2_input"
check "temp-precedence" temp-precedence gpu_temp "temp1_input"

echo "NVIDIA proprietary (nothing readable) - reports nothing at all"
card nvidia card0 "" "" ""
check "nvidia" nvidia gpu_busy EMPTY
check "nvidia" nvidia gpu_temp EMPTY

echo "nouveau alongside AMD - utilisation outranks a temperature-only card"
card mixed card0 ""    ""            "60000"
card mixed card1 "12"  "8589934592"  "45000"
check "mixed" mixed gpu_busy "card1"
check "mixed" mixed gpu_temp "card1"

echo "AMD with less VRAM than a temperature-only card - utilisation still wins"
card rank card0 ""   "34359738368" "60000"
card rank card1 "3"  "8589934592"  "45000"
check "rank" rank gpu_busy "card1"

echo
if (( failures == 0 )); then echo "all discovery fixtures passed"; else
  echo "$failures failing check(s)"; exit 1; fi

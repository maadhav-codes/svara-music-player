#!/usr/bin/env bash
set -euo pipefail
output_dir="${1:-docs/device-measurements}"
adb_bin="${ADB:-adb}"
mkdir -p "$output_dir"
"$adb_bin" get-state
"$adb_bin" shell getprop ro.product.model > "$output_dir/model.txt"
"$adb_bin" shell getprop ro.build.version.sdk > "$output_dir/api.txt"
"$adb_bin" shell cat /proc/meminfo > "$output_dir/device-memory.txt"
for attempt in 1 2 3 4 5; do
  "$adb_bin" shell am force-stop app.svara
  "$adb_bin" shell am start -W -n app.svara/.MainActivity > "$output_dir/cold-start-$attempt.txt"
done
"$adb_bin" shell dumpsys meminfo app.svara > "$output_dir/app-memory.txt"
"$adb_bin" shell dumpsys gfxinfo app.svara framestats > "$output_dir/android-frames.txt"
"$output_dir"

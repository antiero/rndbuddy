#!/bin/zsh
set -euo pipefail
app_root="$(cd "$(dirname "$0")/.." && pwd)"
benchmark_dir="$(mktemp -d /tmp/rndbuddy-audio-benchmark.XXXXXX)"
xcrun swiftc -swift-version 6 -Onone -parse-as-library -o "$benchmark_dir/benchmark" \
  "$app_root/tools/AudioRenderBenchmark.swift" \
  "$app_root/rndbuddy/Audio/MacAudioRender.swift" \
  "$app_root/rndbuddy/Audio/StereoAudioMixer.swift" \
  "$app_root/rndbuddy/Audio/AudioRenderDiagnostics.swift" \
  "$app_root/rndbuddy/Audio/AudioCaptureStats.swift" \
  "$app_root/rndbuddy/Audio/AudioRecordingSink.swift"
"$benchmark_dir/benchmark"

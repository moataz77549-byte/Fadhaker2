#!/usr/bin/env bash
set -euo pipefail
fixture_dir="${1:-/tmp/tarteel/radio-fixtures}"
mkdir -p "$fixture_dir"
for spec in "a:440" "b:660" "c:880" "d:990" "emergency:1100"; do
  name="${spec%%:*}"; frequency="${spec##*:}"
  ffmpeg -hide_banner -loglevel error -f lavfi -i "sine=frequency=${frequency}:sample_rate=44100:duration=20" \
    -ac 2 -c:a aac -b:a 96k -movflags +faststart -y "$fixture_dir/track-${name}.m4a"
done
ffmpeg -hide_banner -loglevel error -f lavfi -i "sine=frequency=330:sample_rate=44100:duration=2" \
  -ac 2 -c:a aac -b:a 96k -movflags +faststart -y "$fixture_dir/fallback.m4a"
printf 'Generated non-religious development tones in %s\n' "$fixture_dir"

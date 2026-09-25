#!/usr/bin/env bash
set -euo pipefail

fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/generated"
mkdir -p "$fixture_dir"

tone=(-f lavfi -i "sine=frequency=440:sample_rate=44100:duration=2" -map_metadata -1)
ffmpeg -nostdin -hide_banner -loglevel error -y "${tone[@]}" -c:a libmp3lame -b:a 128k "$fixture_dir/valid.mp3"
ffmpeg -nostdin -hide_banner -loglevel error -y "${tone[@]}" -c:a aac -b:a 96k "$fixture_dir/valid.m4a"
ffmpeg -nostdin -hide_banner -loglevel error -y "${tone[@]}" -c:a aac -b:a 96k -f adts "$fixture_dir/valid.aac"
ffmpeg -nostdin -hide_banner -loglevel error -y "${tone[@]}" -c:a pcm_s16le "$fixture_dir/valid.wav"
ffmpeg -nostdin -hide_banner -loglevel error -y "${tone[@]}" -c:a flac "$fixture_dir/valid.flac"
ffmpeg -nostdin -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=660:sample_rate=32000:duration=1" -ac 1 -c:a pcm_s16le "$fixture_dir/mono-odd-rate.wav"
ffmpeg -nostdin -hide_banner -loglevel error -y -f lavfi -i "testsrc=size=32x32:rate=1:duration=2" -f lavfi -i "sine=duration=2" -shortest -c:v libx264 -c:a aac "$fixture_dir/audio-video.mp4"
printf '%s' 'this is not an mp3' > "$fixture_dir/fake.mp3"
head -c 200 "$fixture_dir/valid.mp3" > "$fixture_dir/corrupt.mp3"
: > "$fixture_dir/zero.mp3"
printf '%s' 'unsupported text content' > "$fixture_dir/unsupported.txt"

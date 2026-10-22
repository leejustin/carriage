#!/bin/zsh
# Records the App Store app preview: the scripted scene from `-previewScript`, with the sounds it played mixed back
# in (a simulator's screen recording is silent), cut to 886 x 1920 at 30 fps.
#
#   scripts/preview/make.sh [simulator UDID]     # an iPhone Pro Max simulator; writes docs/previews/iphone.mp4
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
UDID=${1:-$(xcrun simctl list devices available | grep -F "iPhone 18 Pro Max (" | head -1 | grep -oE '[0-9A-F-]{36}')}
WORK=$(mktemp -d)
DERIVED="${TMPDIR:-/tmp}/carriage-screenshots"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcodebuild -project "$ROOT/Carriage.xcodeproj" -scheme Carriage -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath "$DERIVED" build -quiet
python3 -I "$ROOT/scripts/preview/record.py" "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/Carriage.app" "$WORK" 33

# Start a second before the first sound, with the page already up, and stop just after the last.
OFFSET=$(cat "$WORK/offset.txt")
AUDIO=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/preview-sound.wav")
START=$(( OFFSET - 1.0 ))
LENGTH=$(( AUDIO + 1.3 > 30 ? 30 : AUDIO + 1.3 ))
ffmpeg -v error -y -i "$WORK/screen.mov" -i "$WORK/preview-sound.wav" -filter_complex \
  "[0:v]trim=start=$START:duration=$LENGTH,setpts=PTS-STARTPTS,fps=30,scale=886:1925:flags=lanczos,crop=886:1920:0:5,format=yuv420p[v];[1:a]adelay=1000|1000,apad,atrim=0:$LENGTH,aresample=48000[a]" \
  -map "[v]" -map "[a]" -c:v libx264 -profile:v high -level 4.0 -preset slow -crf 16 -c:a aac -b:a 256k -ar 48000 -ac 2 \
  -movflags +faststart "$ROOT/docs/previews/iphone.mp4"
echo "wrote docs/previews/iphone.mp4 ($LENGTH s)"

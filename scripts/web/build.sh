#!/bin/zsh
# Builds the Carriage website in web/ from the art in docs/web-art (drawn by scripts/StoreScreenshots.swift), the app
# preview, the icon and the font. Deploy with scripts/web/deploy.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/web/assets"
mkdir -p "$OUT"
for f in laptop-seafoam laptop-cherry laptop-night phone; do
  for w in 1000 1600; do
    ffmpeg -v error -y -i "$ROOT/docs/web-art/$f.png" -vf "scale=$w:-1:flags=lanczos" -c:v libwebp -quality 82 -pix_fmt yuva420p "$OUT/$f-$w.webp"
  done
done
sips -s format jpeg -s formatOptions 82 -Z 1200 "$ROOT/docs/web-art/og.png" --out "$OUT/og.jpg" >/dev/null
cp "$ROOT/docs/previews/iphone.mp4" "$OUT/typing.mp4"
ffmpeg -v error -y -ss 9 -i "$ROOT/docs/previews/iphone.mp4" -frames:v 1 -q:v 3 "$OUT/typing-poster.jpg"
sips -Z 180 "$ROOT/Carriage/Assets.xcassets/AppIcon.appiconset/AppIcon.png" --out "$OUT/icon-180.png" >/dev/null
sips -Z 64 "$ROOT/Carriage/Assets.xcassets/AppIcon.appiconset/AppIcon.png" --out "$OUT/icon-64.png" >/dev/null
cp "$ROOT/Carriage/Fonts/CourierPrime-Regular.ttf" "$ROOT/Carriage/Fonts/CourierPrime-OFL.txt" "$OUT/"
du -sh "$OUT"

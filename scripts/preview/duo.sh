#!/bin/zsh
# Lays a Duo screen recording (from record.py with FOLD=off and -laptopPreview) over the half-folded Duo drawn by
# scripts/StoreScreenshots.swift, so the video shows the machine itself: each half of the screen bent onto its glass.
#
#   scripts/preview/duo.sh <recording folder> <web|film> <out.mp4>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK=$1 KIND=$2 OUT=$3
PIECES="$ROOT/docs/web-art/duo-video/$KIND"
read W H < <(sips -g pixelWidth -g pixelHeight "$PIECES/background.png" | awk '/pixel/ {print $2}' | paste -sd' ' -)
read VW VH < <(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0 "$WORK/screen.mov" | tr ',' ' ')
HALF=$(( VH / 2 ))
corner() { python3 -I -c "import json,sys; c=json.load(open('$PIECES/corners.json'))['$1']; print(':'.join(f'x{i}={p[0]:.2f}:y{i}={p[1]:.2f}' for i,p in enumerate(c)))"; }
TOP=$(corner top) BOTTOM=$(corner bottom)

# Start a second before the first sound, and stop shortly after the last.
OFFSET=$(cat "$WORK/offset.txt")
AUDIO=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$WORK/preview-sound.wav")
START=$(( OFFSET - 1.0 ))
LENGTH=$(( AUDIO + 1.3 ))

ffmpeg -v error -y -i "$WORK/screen.mov" -i "$WORK/preview-sound.wav" \
  -loop 1 -i "$PIECES/background.png" -loop 1 -i "$PIECES/mask-top.png" -loop 1 -i "$PIECES/mask-bottom.png" -filter_complex "
  [0:v]trim=start=$START:duration=$LENGTH,setpts=PTS-STARTPTS,fps=30,split=2[a][b];
  [a]crop=$VW:$HALF:0:0,scale=$W:$H,perspective=${TOP}:sense=destination,format=rgba[ta];
  [b]crop=$VW:$HALF:0:$HALF,scale=$W:$H,perspective=${BOTTOM}:sense=destination,format=rgba[ba];
  [3:v]format=gray,lut=y='if(gt(val,235),255,0)',boxblur=1[mt];
  [4:v]format=gray,lut=y='if(gt(val,235),255,0)',boxblur=1[mb];
  [ta][mt]alphamerge[t];[ba][mb]alphamerge[bm];
  [2:v][t]overlay=shortest=1[x];[x][bm]overlay=shortest=1,format=yuv420p[v];
  [1:a]adelay=1000|1000,apad,atrim=0:$LENGTH,acompressor=threshold=-26dB:ratio=4:attack=1:release=90:makeup=2,loudnorm=I=-16:TP=-1.5,aresample=48000[au]" \
  -map "[v]" -map "[au]" -t $LENGTH -c:v libx264 -profile:v high -preset slow -crf 18 -c:a aac -b:a 192k -ar 48000 -ac 2 \
  -movflags +faststart "$OUT"
echo "wrote $OUT ($LENGTH s)"

#!/bin/zsh
# Cuts the launch film from scripts/film/timeline.txt: mood shots, typed title cards, the typed close-up, the real
# Duo recording and an end card, over the app's recorded keys and optional music. 1920 x 1080, 30 fps.
#
#   scripts/film/make.sh <clips folder, or - for none> [music file]       writes docs/previews/launch-film.mp4
#   TAGLINE="Write with intent." sets the end card's line.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CLIPS=$1
MUSIC=${2:-}
WORK=$(mktemp -d)
DUO="$ROOT/docs/previews/duo-film.mp4"
DUO_FROM=${DUO_FROM:-5.5}     # where in the Duo recording to start: just before the first key
CREAM=0xF3ECDD
cd "$ROOT"

ffmpeg -nostdin -v error -y -ss $DUO_FROM -i "$DUO" -vn -ac 1 -ar 48000 "$WORK/duo.wav"
swift scripts/film/Film.swift "$WORK" scripts/film/timeline.txt "$WORK/duo.wav" ${MUSIC:+"$MUSIC"} > "$WORK/cut.txt"

n=0
: > "$WORK/list.txt"
while read kind name count; do
  n=$((n + 1))
  out="$WORK/seg-$n.mp4"
  length=$(( count / 30.0 ))
  fadeout=$(( length - 0.35 ))
  fades="fade=t=in:st=0:d=0.35:color=$CREAM,fade=t=out:st=$fadeout:d=0.35:color=$CREAM"
  common=(-an -frames:v $count -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -r 30)
  case $kind in
    clip) ffmpeg -nostdin -v error -y -i "$CLIPS/$name.mp4" -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=30,tpad=stop_mode=clone:stop_duration=2,$fades" $common "$out" ;;
    card|word) ffmpeg -nostdin -v error -y -framerate 30 -i "$WORK/$name/frame-%04d.png" -vf "$fades" $common "$out" ;;
    duo)  ffmpeg -nostdin -v error -y -ss $DUO_FROM -i "$DUO" -vf "fps=30,$fades" $common "$out" ;;
    end)  ffmpeg -nostdin -v error -y -loop 1 -framerate 30 -i "$WORK/$name/frame.png" -vf "fade=t=in:st=0:d=0.5:color=$CREAM" $common "$out" ;;
  esac
  echo "file '$out'" >> "$WORK/list.txt"
done < "$WORK/cut.txt"

ffmpeg -nostdin -v error -y -f concat -safe 0 -i "$WORK/list.txt" -i "$WORK/soundtrack.wav" -map 0:v -map 1:a -c:v copy \
  -af "acompressor=threshold=-24dB:ratio=2.5:attack=3:release=120:makeup=1.5,loudnorm=I=-16:TP=-1.5" -c:a aac -b:a 192k -ar 48000 -ac 2 \
  -shortest -movflags +faststart "$ROOT/docs/previews/launch-film.mp4"
cat "$WORK/cut.txt"
echo "wrote docs/previews/launch-film.mp4"

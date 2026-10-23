#!/bin/zsh
# Cuts the launch film: three Dreamina shots of an old typewriter, typed title cards, the real Duo recording and an
# end card, over a soundtrack of the real recorded keys and rain. 1920 x 1080, for YouTube and Product Hunt.
#
#   scripts/film/make.sh <folder with find.mp4, typing.mp4, return.mp4>    writes docs/previews/launch-film.mp4
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CLIPS=$1
WORK=$(mktemp -d)
DUO="$ROOT/docs/previews/duo-film.mp4"
DUO_FROM=5.5      # where in the Duo recording to start: just before the first key
CREAM=0xF3ECDD
cd "$ROOT"

ffmpeg -v error -y -ss $DUO_FROM -i "$DUO" -vn -ac 1 -ar 48000 "$WORK/duo.wav"
swift scripts/film/Film.swift "$WORK" "$WORK/duo.wav" > "$WORK/timeline.txt"

n=0
: > "$WORK/list.txt"
while read kind name start length; do
  n=$((n + 1))
  out="$WORK/seg-$n.mp4"
  fadeout=$(( length - 0.35 ))
  fades="fade=t=in:st=0:d=0.35:color=$CREAM,fade=t=out:st=$fadeout:d=0.35:color=$CREAM"
  common=(-an -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -r 30)
  case $kind in
    clip) ffmpeg -nostdin -v error -y -i "$CLIPS/$name.mp4" -t $length -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=30,$fades" $common "$out" ;;
    card) ffmpeg -nostdin -v error -y -framerate 30 -i "$WORK/$name/frame-%04d.png" -t $length -vf "$fades" $common "$out" ;;
    duo)  ffmpeg -nostdin -v error -y -ss $DUO_FROM -i "$DUO" -t $length -vf "fps=30,$fades" $common "$out" ;;
    end)  ffmpeg -nostdin -v error -y -loop 1 -framerate 30 -i "$WORK/$name/frame.png" -t $length -vf "fade=t=in:st=0:d=0.5:color=$CREAM" $common "$out" ;;
  esac
  echo "file '$out'" >> "$WORK/list.txt"
done < "$WORK/timeline.txt"

ffmpeg -v error -y -f concat -safe 0 -i "$WORK/list.txt" -i "$WORK/soundtrack.wav" -map 0:v -map 1:a -c:v copy \
  -af "acompressor=threshold=-26dB:ratio=3:attack=2:release=100:makeup=2,loudnorm=I=-16:TP=-1.5" -c:a aac -b:a 192k -ar 48000 -ac 2 \
  -shortest -movflags +faststart "$ROOT/docs/previews/launch-film.mp4"
cat "$WORK/timeline.txt"
echo "wrote docs/previews/launch-film.mp4"

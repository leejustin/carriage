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

RAW="$ROOT/docs/film/duo-raw.mp4"
# duo-film.mp4 starts a second before the raw recording's first sound.
RAW_LEAD=$(( $(cat "$ROOT/docs/film/duo-raw-offset.txt") - 1.0 ))
ffmpeg -nostdin -v error -y -i "$DUO" -vn -ac 1 -ar 48000 "$WORK/duo.wav"
DUO_FROM=$DUO_FROM swift scripts/film/Film.swift "$WORK" scripts/film/timeline.txt "$WORK/duo.wav" ${MUSIC:+"$MUSIC"} > "$WORK/cut.txt"

n=0
: > "$WORK/list.txt"
while read kind name count behind source crop; do
  n=$((n + 1))
  out="$WORK/seg-$n.mp4"
  length=$(( count / 30.0 ))
  fadeout=$(( length - 0.35 ))
  fades="fade=t=in:st=0:d=0.35:color=$CREAM,fade=t=out:st=$fadeout:d=0.35:color=$CREAM"
  common=(-an -frames:v $count -c:v libx264 -preset slow -crf 17 -pix_fmt yuv420p -r 30)
  case $kind in
    clip) ffmpeg -nostdin -v error -y -i "$CLIPS/$name.mp4" -vf "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=30,tpad=stop_mode=clone:stop_duration=2,$fades" $common "$out" ;;
    card|word)
      if [[ ${behind:--} != - ]]; then
        # The shot faded back behind the words: blurred, softened and washed with the page's cream.
        ffmpeg -nostdin -v error -y -i "$CLIPS/$behind.mp4" -framerate 30 -i "$WORK/$name/frame-%04d.png" -filter_complex \
          "[0:v]scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=30,tpad=stop_mode=clone:stop_duration=4,gblur=sigma=6,eq=saturation=0.7,drawbox=x=0:y=0:w=iw:h=ih:color=0xF3ECDD@0.58:t=fill[bg];[bg][1:v]overlay=format=auto,$fades" \
          $common "$out"
      else
        ffmpeg -nostdin -v error -y -framerate 30 -i "$WORK/$name/frame-%04d.png" -vf "$fades" $common "$out"
      fi ;;
    shot)
      # A moment of the Duo recording, easing in slowly, with its caption faded up over it.
      from=$behind
      case $crop in
        keys)   box=2006:1128:0:1560 ;;
        line)   box=1150:647:110:820 ;;
        margin) box=1420:799:586:700 ;;
        *)      box= ;;
      esac
      push="zoompan=z='1+0.0009*on':x='iw/2-(iw/zoom/2)':y='ih*0.46-(ih/zoom/2)':d=1:s=1920x1080:fps=30"
      if [[ $source == raw ]]; then
        input=(-ss $(( from + RAW_LEAD )) -i "$RAW"); frame="crop=$box,scale=1920:1080,$push"
      else
        input=(-ss $from -i "$DUO"); frame="scale=1920:1080,zoompan=z='1+0.0016*on':x='iw/2-(iw/zoom/2)':y='ih*0.42-(ih/zoom/2)':d=1:s=1920x1080:fps=30"
      fi
      ffmpeg -nostdin -v error -y $input -loop 1 -i "$WORK/$name.png" -filter_complex \
        "[0:v]fps=30,${frame}[v];[1:v]format=rgba,fade=t=in:st=0.15:d=0.3:alpha=1[c];[v][c]overlay=format=auto,${fades}" \
        $common "$out" ;;
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

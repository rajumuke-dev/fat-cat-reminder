#!/bin/bash
# Turn an ordinary cat video into a transparent (HEVC + alpha) loop for the app.
# usage: tools/make-cat-video.sh <input video> <walk|sit> [start_sec] [duration_sec]
#   walk: cat must walk left->right in side view (app flips it for the way back)
#   sit : cat sits/rests; played as a ping-pong loop
set -euo pipefail
IN="$1"; KIND="$2"; START="${3:-0}"; DUR="${4:-10}"
cd "$(dirname "$0")/.."
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
[ -x tools/alphamask ] || swiftc -O tools/alphamask.swift -o tools/alphamask

mkdir "$WORK/fr"
ffmpeg -v error -ss "$START" -t "$DUR" -i "$IN" -vf "fps=24,scale='min(960,iw)':-2" "$WORK/fr/f%04d.png"
OUT=$(tools/alphamask "$WORK/fr" "$WORK/ma" 2>/dev/null | tail -1)
echo "$OUT"
read -r X0 X1 Y0 Y1 <<<"$(echo "$OUT" | sed -E 's/.*x:([0-9]+)-([0-9]+) y:([0-9]+)-([0-9]+).*/\1 \2 \3 \4/')"
W=$(( (X1 - X0 + 16) / 2 * 2 )); H=$(( (Y1 - Y0 + 16) / 2 * 2 )); X=$(( X0 > 8 ? X0 - 8 : 0 )); Y=$(( Y0 > 8 ? Y0 - 8 : 0 ))

CROP="crop='trunc(min($W,iw-$X)/2)*2':'trunc(min($H,ih-$Y)/2)*2':$X:$Y"
[ -z "${FULL_FRAME:-}" ] || CROP="null"   # keep every clip the same framing so walk -> sit lines up
# optional: drop dark non-orange pixels (a hand in the source video) from the cutout
[ -z "${DROP_DARK:-}" ] || CROP="$CROP,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lt(r(X,Y),$DROP_DARK),0,alpha(X,Y))'"
if [ "$KIND" = "sit" ]; then
  FILTER="[0:v]$CROP,format=bgra,split[a][b];[b]reverse[r];[a][r]concat=n=2:v=1[o]"
else
  FILTER="[0:v]$CROP,format=bgra[o]"
fi
ffmpeg -v error -y -framerate 24 -i "$WORK/ma/f%04d.png" -filter_complex "$FILTER" -map "[o]" \
  -c:v hevc_videotoolbox -alpha_quality 0.9 -b:v 6M -tag:v hvc1 -pix_fmt bgra "Resources/cat-$KIND.mov"
echo "Wrote Resources/cat-$KIND.mov (${W}x${H}); rebuild with ./build.sh"

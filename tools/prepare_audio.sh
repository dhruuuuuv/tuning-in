#!/usr/bin/env bash
# prepare_audio.sh — turn a raw recording into an ambiance loop:
#   mono · 48kHz · loudness-matched · seamless crossfade loop · FLAC
#
# usage:
#   # one slot at a time (recommended while curating):
#   ./tools/prepare_audio.sh <slot 1-6> <source-file>
#
#   # all six at once, in order birdsong forest rain stream fire night:
#   ./tools/prepare_audio.sh <birdsong> <forest> <rain> <stream> <fire> <night>
#
# tunables (env vars):
#   START  seconds to skip into the source before grabbing the loop  (default 0)
#   LEN    length of loop body to take, in seconds                    (default 40)
#   XF     crossfade length that makes the loop seamless, in seconds  (default 2)
#   LUFS   target integrated loudness (all six matched to this)       (default -20)
#
# example: take a calm 40s section starting 12s in:
#   START=12 LEN=40 ./tools/prepare_audio.sh 3 ~/Downloads/rain_long.wav

set -euo pipefail

XF="${XF:-2}"
LEN="${LEN:-40}"
START="${START:-0}"
LUFS="${LUFS:--20}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out_dir="$(cd "$here/.." && pwd)/audio"
mkdir -p "$out_dir"

names=(birdsong forest rain stream fire night)

process() {
  local slot="$1" src="$2"
  local idx=$((slot - 1))
  local name="${names[$idx]}"
  local out
  out="$(printf '%s/%02d_%s.flac' "$out_dir" "$slot" "$name")"

  if [[ ! -f "$src" ]]; then
    echo "  ! source not found: $src" >&2
    return 1
  fi

  # duration sanity check: need at least LEN worth, and more than 2*XF
  local dur
  dur="$(ffprobe -v error -show_entries format=duration \
        -of default=nk=1:nw=1 "$src" 2>/dev/null || echo 0)"
  dur="${dur%.*}"
  if (( dur < XF * 2 + 1 )); then
    echo "  ! '$src' is only ${dur}s — too short for a ${XF}s crossfade loop" >&2
    return 1
  fi

  echo "  [$slot] $name  <-  $(basename "$src")  (${START}s +${LEN}s, ${XF}s xfade)"

  # 1. trim to the chosen section, fold to mono, resample, loudness-normalise
  # 2. split, and crossfade the body's tail into a copy of the head so the
  #    loop boundary lands on identical material (seamless).
  ffmpeg -hide_banner -loglevel error -y -i "$src" -filter_complex "
    [0:a]atrim=start=${START}:duration=${LEN},asetpts=N/SR/TB,
         aformat=channel_layouts=mono,aresample=48000,
         loudnorm=I=${LUFS}:TP=-2:LRA=7[a];
    [a]asplit[h][b];
    [h]atrim=0:${XF},asetpts=N/SR/TB[head];
    [b]atrim=start=${XF},asetpts=N/SR/TB[body];
    [body][head]acrossfade=d=${XF}:c1=tri:c2=tri[out]
  " -map "[out]" -ar 48000 -ac 1 -c:a flac -sample_fmt s16 "$out"

  echo "      -> $out"
}

if [[ $# -eq 2 && "$1" =~ ^[1-6]$ ]]; then
  process "$1" "$2"
elif [[ $# -eq 6 ]]; then
  for s in 1 2 3 4 5 6; do process "$s" "${!s}"; done
else
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 1
fi

echo "done. remember to fill in audio/AUDIO_CREDITS.md for each sound."

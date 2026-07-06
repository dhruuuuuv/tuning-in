#!/usr/bin/env bash
# freesound_search.sh — audition CC-licensed candidates from freesound.org
# without leaving the terminal. prints title, author, licence, length, a
# preview URL (open it to listen), and the sound page (to download the original).
#
# setup (one time):
#   1. make a free account at https://freesound.org
#   2. create an API credential: https://freesound.org/apiv2/apply/
#   3. export the API key (the "token"):
#        export FREESOUND_TOKEN=your_api_key_here
#
# usage:
#   ./tools/freesound_search.sh "rain steady loop"
#   ./tools/freesound_search.sh "crackling fire" 20     # cap at 20 results
#
# only CC0 and Attribution (CC-BY) sounds are shown — the licences safe to
# redistribute with the script. credit every one in audio/AUDIO_CREDITS.md.

set -euo pipefail

if [[ -z "${FREESOUND_TOKEN:-}" ]]; then
  echo "error: set FREESOUND_TOKEN first (see the header of this script)." >&2
  exit 1
fi
if [[ $# -lt 1 ]]; then
  echo "usage: $0 \"search terms\" [page_size]" >&2
  exit 1
fi

query="$1"
page_size="${2:-15}"

curl -s -G "https://freesound.org/apiv2/search/text/" \
  --data-urlencode "query=${query}" \
  --data-urlencode 'filter=license:("Creative Commons 0" OR "Attribution")' \
  --data-urlencode "fields=id,name,username,license,duration,previews,url" \
  --data-urlencode "sort=rating_desc" \
  --data-urlencode "page_size=${page_size}" \
  -H "Authorization: Token ${FREESOUND_TOKEN}" \
| jq -r '
  if .detail then "API error: \(.detail)"
  else
    (.results[]? |
      "[\(.id)] \(.name)\n" +
      "   by \(.username)  ·  \(.license)  ·  \(.duration | floor)s\n" +
      "   listen:   \(.previews."preview-hq-mp3")\n" +
      "   download: \(.url)\n")
  end
'

cat <<'EOF'

tip: "listen" is a lossy preview for auditioning. for the best quality,
open the "download" page (logged in) and grab the ORIGINAL file, then run:
  ./tools/prepare_audio.sh <slot 1-6> <that-file>
EOF

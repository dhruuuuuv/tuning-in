#!/usr/bin/env bash
# deploy.sh — push tuning-in to a networked norns over SSH.
#
# norns SSH defaults:  user "we", password "sleep", host "norns.local".
# override with env vars if yours differ:
#   NORNS_HOST=192.168.1.49 NORNS_USER=we ./tools/deploy.sh
#
# after deploying a NEW or CHANGED engine, you must restart the audio stack so
# norns rescans engines: in maiden's REPL run  ;restart  (or reboot the device).
# then on the norns: K1 -> SELECT -> SCRIPT -> tuning-in -> K3 to load.

set -euo pipefail

HOST="${NORNS_HOST:-norns.local}"
USER="${NORNS_USER:-we}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="/home/${USER}/dust/code/tuning-in/"

echo "deploying:"
echo "  from  $here/"
echo "  to    ${USER}@${HOST}:${dest}"
echo

rsync -avz --delete \
  --exclude '.git/' \
  "$here/" "${USER}@${HOST}:${dest}"

echo
echo "deployed. next:"
echo "  1. in maiden REPL:  ;restart      (loads the engine)"
echo "  2. on norns: K1 -> SELECT -> SCRIPT -> tuning-in -> K3"
echo "  3. watch maiden for 'tuning in: all six loops loaded'"

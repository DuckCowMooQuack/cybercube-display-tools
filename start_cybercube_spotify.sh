#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

exec python3 -u ./cybercube_spotify.py \
  --cube "${CYBERCUBE_IP:-192.168.4.26}" \
  --output "${CYBERCUBE_SPOTIFY_OUTPUT:-/tmp/cybercube_spotify.gif}" \
  --token-path "${CYBERCUBE_SPOTIFY_TOKEN_PATH:-$HOME/.config/cybercube/spotify-token.json}" \
  --idle-path "${CYBERCUBE_IDLE_PATH:-/image/Starfield_1.gif}" \
  --interval "${CYBERCUBE_SPOTIFY_INTERVAL:-1}"

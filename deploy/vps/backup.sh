#!/bin/bash
# Latent keeps no database. This copies the env file (the hostname) aside.
set -euo pipefail
ROOT="${1:-/opt/latent}"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="${ROOT}/backups"
mkdir -p "$DEST"
if [ -f "$ROOT/latent.env" ]; then
  cp "$ROOT/latent.env" "$DEST/latent.env.$STAMP"
  echo "Saved $DEST/latent.env.$STAMP"
else
  echo "No latent.env at $ROOT"
  exit 1
fi

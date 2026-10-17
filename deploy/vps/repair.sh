#!/bin/bash
# Re-detect Caddy (host or Requestick's container) and point it at Latent again.
set -euo pipefail

DOMAIN="${1:-}"
LATENT_DIR="${LATENT_DIR:-/opt/latent}"

if [ ! -f "$LATENT_DIR/docker-compose.yml" ] || [ ! -f "$LATENT_DIR/latent.env" ]; then
  echo "No Latent install at $LATENT_DIR."
  exit 1
fi

cd "$LATENT_DIR"

if [ -z "$DOMAIN" ]; then
  DOMAIN="$(grep '^LATENT_DOMAIN=' latent.env | head -1 | cut -d= -f2-)"
fi
if [ -z "$DOMAIN" ]; then
  echo "Usage: sudo ./repair.sh qr.yourmomon.top"
  exit 1
fi

CADDY_LIB=""
for f in "$LATENT_DIR/caddy.sh" "$LATENT_DIR/deploy/vps/caddy.sh"; do
  if [ -f "$f" ]; then CADDY_LIB="$f"; break; fi
done
if [ -z "$CADDY_LIB" ]; then
  echo "Missing caddy.sh"
  exit 1
fi
# shellcheck disable=SC1090
. "$CADDY_LIB"

set -a
# shellcheck disable=SC1091
. "$LATENT_DIR/latent.env"
set +a

latent_detect_caddy
if [ "$CADDY_KIND" = "docker" ] && [ -n "$CADDY_NET" ]; then
  latent_write_net_override "$LATENT_DIR" "$CADDY_NET"
fi

docker compose --env-file latent.env up -d
echo "== waiting =="
for i in $(seq 1 45); do
  if curl -sf --max-time 2 "http://127.0.0.1:${LATENT_PORT:-3070}/" >/dev/null 2>&1; then
    echo "Latent is up."
    break
  fi
  sleep 2
done
if ! curl -sf --max-time 2 "http://127.0.0.1:${LATENT_PORT:-3070}/" >/dev/null 2>&1; then
  docker logs --tail 80 latent-app || true
  exit 1
fi

if [ "$CADDY_KIND" = "none" ]; then
  echo "No existing Caddy — starting ours."
  docker compose --env-file latent.env --profile edge up -d
else
  latent_piggyback "$DOMAIN"
fi

sleep 2
curl -sS -o /dev/null -w "https://${DOMAIN} → HTTP %{http_code}\n" --max-time 10 "https://${DOMAIN}" || true

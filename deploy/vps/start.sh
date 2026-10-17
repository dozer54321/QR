#!/bin/bash
# Latent — start next to an existing Caddy, or with our own Caddy container.
set -euo pipefail

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "Usage: ./start.sh qr.yourmomon.top"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if [ ! -f "$ROOT/docker-compose.yml" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)"
fi
cd "$ROOT"

CADDY_LIB=""
for f in "$ROOT/caddy.sh" "$ROOT/deploy/vps/caddy.sh"; do
  if [ -f "$f" ]; then CADDY_LIB="$f"; break; fi
done
if [ -z "$CADDY_LIB" ]; then
  echo "Missing caddy.sh"
  exit 1
fi
# shellcheck disable=SC1090
. "$CADDY_LIB"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed. On Ubuntu, run:  sudo ./install.sh $DOMAIN"
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but not running, or this user cannot talk to it."
  exit 1
fi

ENV_FILE="$ROOT/latent.env"
if [ -f "$ENV_FILE" ]; then
  echo "Keeping existing latent.env."
else
  umask 077
  cat > "$ENV_FILE" <<EOF
LATENT_DOMAIN=${DOMAIN}
LATENT_PORT=3070
EOF
  echo "Wrote latent.env."
fi

set_env() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" && rm -f "$ENV_FILE.bak"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

set_env LATENT_DOMAIN "$DOMAIN"
if ! grep -q '^LATENT_PORT=' "$ENV_FILE"; then
  set_env LATENT_PORT 3070
fi

if [ -f "$ROOT/VERSION" ]; then
  set_env LATENT_VERSION "$(tr -d '[:space:]' < "$ROOT/VERSION")"
fi

if [ -f "$ROOT/latent-image.tar.gz" ]; then
  echo "Loading prebuilt Latent image..."
  docker load -i "$ROOT/latent-image.tar.gz"
fi

if docker image inspect latent:local >/dev/null 2>&1; then
  VER="$(grep '^LATENT_VERSION=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)"
  if [ -n "$VER" ] && docker image inspect "latent:${VER}" >/dev/null 2>&1; then
    set_env LATENT_IMAGE "latent:${VER}"
  else
    set_env LATENT_IMAGE latent:local
  fi
fi

compose_up() {
  local profiles=()
  if [ "${1:-}" = "edge" ]; then
    profiles=(--profile edge)
  fi
  local img
  img="$(grep '^LATENT_IMAGE=' "$ENV_FILE" | head -1 | cut -d= -f2- || true)"
  if [ -z "$img" ]; then img="latent:local"; fi
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    if docker image inspect latent:local >/dev/null 2>&1; then
      set_env LATENT_IMAGE latent:local
    else
      echo "No Latent image on this machine. Building from this directory..."
      set_env LATENT_IMAGE latent:local
      set -a
      # shellcheck disable=SC1091
      . "$ENV_FILE"
      set +a
      docker compose "${profiles[@]}" --env-file "$ENV_FILE" up -d --build
      return
    fi
  fi
  set -a
  # shellcheck disable=SC1091
  . "$ENV_FILE"
  set +a
  docker compose "${profiles[@]}" --env-file "$ENV_FILE" up -d
}

wait_app() {
  local i
  echo "Waiting for Latent..."
  for i in $(seq 1 45); do
    if curl -sf --max-time 2 "http://127.0.0.1:${LATENT_PORT:-3070}/" >/dev/null 2>&1; then
      echo "Latent is up."
      return 0
    fi
    sleep 2
  done
  echo "Latent did not come up. Last logs:"
  docker logs --tail 120 latent-app 2>/dev/null || true
  docker compose --env-file "$ENV_FILE" ps || true
  return 1
}

latent_detect_caddy

rm -f "$ROOT/docker-compose.override.yml"
if [ "$CADDY_KIND" = "docker" ] && [ -n "$CADDY_NET" ]; then
  latent_write_net_override "$ROOT" "$CADDY_NET"
  echo "Will share Caddy's Docker network: $CADDY_NET"
fi

if [ "$CADDY_KIND" = "none" ]; then
  echo "No existing Caddy — starting Latent with its own Caddy container."
  compose_up edge
  wait_app || true
else
  echo "Using existing Caddy (${CADDY_KIND})."
  if ! compose_up; then
    echo "Compose with the shared network failed — starting on Latent's network only."
    rm -f "$ROOT/docker-compose.override.yml"
    compose_up
  fi
  wait_app || true
  latent_piggyback "$DOMAIN" || {
    echo "Could not piggyback. Check the Caddyfile and that ports 80/443 are Caddy."
    exit 1
  }
fi

echo
echo "Open https://${DOMAIN}  (and https://www.${DOMAIN})"
echo
echo "Logs:   docker compose --env-file latent.env logs -f app"
echo "Stop:   docker compose --env-file latent.env down"
if [ "$(id -u)" -eq 0 ] && [ -f "$ROOT/deploy/vps/update.sh" ]; then
  "$ROOT/deploy/vps/update.sh" --install-timer || true
elif [ -f "$ROOT/deploy/vps/update.sh" ]; then
  echo "Auto-update: sudo $ROOT/deploy/vps/update.sh --install-timer"
fi
